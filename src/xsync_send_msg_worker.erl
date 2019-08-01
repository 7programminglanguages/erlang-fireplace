%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_send_msg_worker.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  23 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_send_msg_worker).

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-record(state, {
                name,
                kafka_service,
                shaper,
                sleep_time
}).
-include("logger.hrl").
-include("kafka_send_msg_pb.hrl").
-include("messagebody_pb.hrl").
-include("xsync_pb.hrl").

%%%===================================================================
%%% API
%%%===================================================================

start_link(Opts) ->
    Name = proplists:get_value(name, Opts),
    gen_server:start_link({local, Name}, ?MODULE, Opts, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Opts) ->
    Name = proplists:get_value(name, Opts),
    KafkaService = proplists:get_value(kafka_service, Opts),
    Speed = proplists:get_value(speed, Opts),
    SleepTime = proplists:get_value(sleep_time, Opts, 100),
    Shaper = msgst_shaper:new(max, Speed),
    self() ! loop,
    {ok, #state{
            name = Name,
            kafka_service = KafkaService,
            shaper = Shaper,
            sleep_time = SleepTime
           }}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(loop, #state{} = State) ->
    {NewState, Pause} = try_consume_msg(State),
    case Pause > 0 of
        true ->
            erlang:send_after(Pause, self(), loop);
        false ->
            self() ! loop
    end,
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================

try_consume_msg(#state{kafka_service=KafkaService, sleep_time = SleepTime, shaper = Shaper}=State) ->
    case read_msg(KafkaService) of
        wait ->
            {State, SleepTime};
        {ok, Value, Ack} ->
            case parse_msg(Value) of
                {error, _} ->
                    ack_msg(KafkaService, Ack),
                    {State,0};
                {ok, KafkaSendMsg} ->
                    spawn(fun() ->
                                  ?INFO_MSG("HandleSendMsg:~p", [xsync_proto:pr(KafkaSendMsg)])
                          end),
                    {ok, ShaperValue} = send_msg(KafkaSendMsg),
                    ack_msg(KafkaService, Ack),
                    {NewShaper, Pause} = msgst_shaper:update(Shaper, ShaperValue),
                    {State#state{shaper=NewShaper}, Pause}
            end
    end.

read_msg(KafkaService) ->
    case kafka_pool:fetch(KafkaService) of
        {ok, Value, Ack} ->
            {ok, Value, Ack};
        _ ->
            wait
    end.

parse_msg(Value) ->
    try kafka_send_msg_pb:decode_msg(Value, 'KafkaSendMsg') of
        #'KafkaSendMsg'{} = KafkaSendMsg ->
            {ok, KafkaSendMsg}
    catch
        C:E ->
            ?INFO_MSG("fail to decode: msg=~p", [Value]),
            {error, {C,E}}
    end.

ack_msg(KafkaService, Ack) ->
    kafka_pool:ack(KafkaService, Ack).

send_msg(#'KafkaSendMsg'{type = Type,
                         user_id = From,
                         targets = Tos,
                         ctype = CType,
                         content = Content,
                         config = Config,
                         attachment = Attachment,
                         ext = Ext}) ->
    ShaperValue = lists:foldl(
                    fun(To, Acc) ->
                            MessageBody = #'MessageBody'{
                                             type = Type,
                                             from = From,
                                             to = To,
                                             content = Content,
                                             ctype = CType,
                                             operation = undefined,
                                             config = Config,
                                             attachment = Attachment,
                                             ext = Ext,
                                             qos = 'AT_LEAST_ONCE'
                                            },
                            Meta = xsync_proto:new_meta(From, To, 'MESSAGE', MessageBody),
                            try route_msg(Type, Meta) of
                                {ok, SV} ->
                                    Acc + SV
                            catch
                                _:_ ->
                                    Acc + 1
                            end
                    end, 0, Tos),
    {ok, ShaperValue}.

route_msg('CHAT', #'Meta'{from = #'XID'{}, to = #'XID'{}} = Meta) ->
    spawn(fun()->
                  xsync_router:route(Meta)
          end),
    {ok, 1};
route_msg('GROUPCHAT', #'Meta'{from = #'XID'{}, to = #'XID'{uid = GroupId}} = Meta) ->
    spawn(fun()->
                  xsync_group_router:route(Meta)
          end),
    case msgst_group:get_group_members_count(GroupId) of
        {ok, Value} ->
            {ok, Value};
        {error, _Reason} ->
            {ok, 1}
    end;
route_msg(_, Meta) ->
    spawn(fun()->
                  ?INFO_MSG("skip route msg: meta=~p", [xsync_proto:pr(Meta)])
          end),
    {ok, 1}.
