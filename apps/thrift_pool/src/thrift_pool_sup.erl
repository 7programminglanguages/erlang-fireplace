%%%-------------------------------------------------------------------------------------------------
%%% File    :  thrift_pool_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(thrift_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_service/1, stop_service/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_service(ServiceName) ->
    Spec = service_spec(ServiceName),
    supervisor:start_child(?MODULE, Spec).

stop_service(ServiceName) ->
    supervisor:terminate_child(?MODULE, ServiceName),
    supervisor:delete_child(?MODULE, ServiceName).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: #{id => Id, start => {M, F, A}}
%% Optional keys are restart, shutdown, type, modules.
%% Before OTP 18 tuples must be used to specify a child. e.g.
%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, { {one_for_one, 100, 10}, service_specs()} }.

service_specs() ->
    {ok, ServiceNames} = application:get_env(thrift_pool, services),
    [service_spec(ServiceName)||ServiceName<-ServiceNames].


service_spec(ServiceName) ->
    {ok, Opts} = application:get_env(thrift_pool, ServiceName),
    PoolSizeOrig = proplists:get_value(pool_size, Opts, 1),
    PoolSize = normalize_pool_size(PoolSizeOrig),
    MaxOverFlowOrig = proplists:get_value(max_overflow, Opts, 2),
    MaxOverFlow = normalize_pool_size(MaxOverFlowOrig),
    PoolArgs = [{name, {local, ServiceName}},
                {worker_module, thrift_pool_worker},
                {size, PoolSize},
                {max_overflow, MaxOverFlow}|Opts],
    WorkerArgs = [ServiceName, Opts],
    poolboy:child_spec(ServiceName, PoolArgs, WorkerArgs).

%%====================================================================
%% Internal functions
%%====================================================================

normalize_pool_size({each_scheduler, Base}) ->
    max(1, round(Base * erlang:system_info(schedulers)));
normalize_pool_size(Number) when is_number(Number)  ->
    max(1, round(Number)).
