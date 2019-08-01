%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_roster_notice_worker.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  26 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_roster_notice_worker).

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
-include("kafka_notice_pb.hrl").
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
                {ok, KafkaRosterNotice} ->
                    {ok, ShaperValue} = send_msg(KafkaRosterNotice),
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
    try kafka_notice_pb:decode_msg(Value, 'KafkaRosterNotice') of
        #'KafkaRosterNotice'{} = KafkaRosterNotice ->
            {ok, KafkaRosterNotice}
    catch
        C:E ->
            ?INFO_MSG("fail to decode: msg=~p", [Value]),
            {error, {C,E}}
    end.

ack_msg(KafkaService, Ack) ->
    kafka_pool:ack(KafkaService, Ack).

send_msg(#'KafkaRosterNotice'{} = RosterNotice) ->
    spawn(fun() ->
                  xsync_roster_notice_handler:handle(RosterNotice)
          end),
    {ok, 1}.
