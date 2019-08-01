%%%-------------------------------------------------------------------------------------------------
%%% File    :  kafka_pool_reader.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  22 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(kafka_pool_reader).

-behaviour(gen_server).
-behaviour(brod_group_subscriber).
%% API
-export([start_link/6, fetch/1, ack/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-export([init/2,
         handle_message/4
        ]).

-define(SERVER, ?MODULE).

-record(state, {
                service,
                topic,
                group_id,
                consumer_config,
                group_config,
                subscriber,
                queue = queue:new(),
                unack_msg = undefined
}).
-include("brod.hrl").

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, Service, Topic, GroupId, ConsumerConfig, GroupConfig) ->
    gen_server:start_link({local, Name}, ?MODULE,
                          [Service, Topic, GroupId, ConsumerConfig, GroupConfig], []).

fetch(Name) ->
    gen_server:call(Name, fetch).

ack(Name, Ack) ->
    gen_server:cast(Name, {ack, Ack}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Service, Topic, GroupId, ConsumerConfig, GroupConfig]) ->
    {ok, #state{
            service = Service,
            topic = Topic,
            group_id = GroupId,
            consumer_config = ConsumerConfig,
            group_config = GroupConfig
           }}.
handle_call(fetch, _From, #state{subscriber = undefined} = State) ->
    NewState = init_group_subscriber(State),
    {reply, empty, NewState};
handle_call(fetch, _From, #state{queue=Queue, unack_msg = undefined}=State) ->
    case queue:out(Queue) of
        {{value, Message}, NewQueue} ->
            {reply, {ok, Message}, State#state{queue = NewQueue, unack_msg = Message}};
        {empty, _} ->
            {reply, empty, State}
    end;
handle_call(fetch, _From, #state{unack_msg = Message}=State) ->
    {reply, {ok, Message}, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({kafka_message, Message}, #state{queue = Queue}=State) ->
    NewQueue = queue:in(Message, Queue),
    {noreply, State#state{queue = NewQueue}};
handle_cast({ack, Ack}, #state{topic=Topic, subscriber = Subscriber,
                               unack_msg = {_Value, Ack}} = State) ->
    {Partition, Offset} = Ack,
    brod_group_subscriber:ack(Subscriber, Topic, Partition, Offset),
    {noreply, State#state{unack_msg = undefined}};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.


%%%===================================================================
%%% brod_group_subscriber callbacks
%%%===================================================================

init(_GroupId, WorkerPid) ->
  {ok, WorkerPid}.

handle_message(_Topic, Partition, #kafka_message{
                                   offset = Offset,
                                   value = Value}, WorkerPid) ->
    gen_server:cast(WorkerPid, {kafka_message, {Value, {Partition, Offset}}}),
    {ok, WorkerPid}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_group_subscriber(#state{service=ClientId, topic=Topic,
                       group_id = GroupId,
                       consumer_config = ConsumerConfig,
                       group_config = GroupConfig} = State) ->
    {ok, Subscriber} =
        brod:start_link_group_subscriber(
          ClientId, GroupId, [Topic], GroupConfig,
          ConsumerConfig,
          _CallbackModule  = ?MODULE,
          _CallbackInitArg = self()),
    State#state{subscriber = Subscriber}.
