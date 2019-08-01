%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_status_serial.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  6 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_status_serial).

-behaviour(gen_server).

%% API
-export([start_link/0, serial/4, init_spec/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, {refs = dict:new(),
                keys = dict:new()}).

init_spec() ->
    {?SERVER,
    {?MODULE, start_link, []},
     permanent,
     brutal_kill,
     worker,
     [?MODULE]}.

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

serial(M, F, A, Key) ->
    gen_server:call(?MODULE, {serial, M, F, A, Key}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}}.

handle_call({serial, M, F, A, Key}, From, #state{refs = Refs, keys = Keys}=State) ->
    case dict:is_key(Key, Keys) of
        false ->
            {Pid, Ref} = spawn_monitor(
                           fun() ->
                                   exit({result, apply(M, F, A)})
                           end),
            NewRefs = dict:store(Ref, {Key, Pid}, Refs),
            NewKeys = dict:append(Key, From, Keys),
            {noreply, State#state{refs = NewRefs, keys = NewKeys}};
        true ->
            NewKeys = dict:append(Key, From, Keys),
            {noreply, State#state{keys = NewKeys}}
    end;
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, Result}, #state{refs = Refs,
                                                        keys = Keys} = State) ->
    case dict:find(Ref, Refs) of
        error ->
            {noreply, State};
        {ok, {Key, Pid}} ->
            case Result of
                {result, Value} -> ok;
                Value -> ok
            end,
            {ok, Froms} = dict:find(Key, Keys),
            [gen_server:reply(From, Value) || From <- Froms],
            NewRefs = dict:erase(Ref, Refs),
            NewKeys = dict:erase(Key, Keys),
            {noreply, State#state{refs = NewRefs, keys = NewKeys}}
    end;
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

