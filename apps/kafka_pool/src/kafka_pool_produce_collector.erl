%%%-------------------------------------------------------------------------------------------------
%%% File    :  kafka_pool_produce_collector.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :  Collect kafka produce request and write to kafka batch
%%% Created : 29 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(kafka_pool_produce_collector).
-define(GEN_SERVER, p1_server).
-behaviour(?GEN_SERVER).

%% API
-export([start_link/0,
         produce_async/6,
         produce_sync/6]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-include("logger.hrl").

-record(state, {
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    ?GEN_SERVER:start_link(?MODULE, [], []).

produce_async(Client, Topic, Key, Value, TS, Strategy) ->
    try
        Pid = cuesport:get_worker(?MODULE),
        case is_process_alive(Pid) of
            false ->
                throw(worker_pid_not_alive);
            true ->
                ok
        end,
        ?GEN_SERVER:cast(Pid, {produce_async, Client, Topic, Key, Value, TS, Strategy})
    catch
        C:E ->
            ?ERROR_MSG("fail to produce:Topic=~p, Key=~p, Value=~p,Error=~p",
                       [Topic, Key, Value, {C,E}]),
            {error, {C,E}}
    end.

produce_sync(Client, Topic, Key, Value, TS, Strategy) ->
    try
        Pid = cuesport:get_worker(?MODULE),
        case is_process_alive(Pid) of
            false ->
                throw(worker_pid_not_alive);
            true ->
                ok
        end,
        ?GEN_SERVER:cast(Pid, {produce_sync, Client, Topic, Key, Value, TS, Strategy})
    catch
        C:E ->
            ?ERROR_MSG("fail to produce:Topic=~p, Key=~p, Value=~p,Error=~p",
                       [Topic, Key, Value, {C,E}]),
            {error, {C,E}}
    end.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(_Opts) ->
    {ok, #state{}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast({produce_async, Client, Topic, Key, Value, TS, Strategy}, State) ->
    case kafka_pool:produce_async(Client, Topic, partition_function(Strategy), Key, {TS, Value}) of
        ok ->
            ok;
        {error, _Reason} ->
            ok
    end,
    {noreply, State};
handle_cast({produce_sync, Client, Topic, Key, Value, TS, Strategy}, State) ->
    case kafka_pool:produce_sync(Client, Topic, partition_function(Strategy), Key, {TS, Value}) of
        ok ->
            ok;
        {error, _Reason} ->
            ok
    end,
    {noreply, State};
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
%%% Internal functions
%%%===================================================================

partition_function(random) ->
    fun(_Topic, PartitionCount, _Key, _Value, 1) ->
            {ok, rand:uniform(PartitionCount) -1, 1};
       (_Topic, PartitionCount, _Key, _Value, ClientCount) ->
            {ok, rand:uniform(PartitionCount) -1, rand:uniform(ClientCount)}
    end;
partition_function(hash) ->
    fun(_Topic, PartitionCount, Key, _Value, 1) ->
            {ok, erlang:phash2(Key, PartitionCount), 1};
       (_Topic, PartitionCount, Key, _Value, ClientCount) ->
            {ok, erlang:phash2(Key, PartitionCount), rand:uniform(ClientCount)}
    end.
