%%%-------------------------------------------------------------------------------------------------
%%% File    :  redis_pool_sup.erl
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
-module(redis_pool_sup).

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
    {ok, ServiceNames} = application:get_env(redis_pool, services),
    [service_spec(ServiceName)||ServiceName<-ServiceNames].


service_spec(ServiceName) ->
    {ok, Opts} = application:get_env(redis_pool, ServiceName),
    Host = proplists:get_value(host, Opts, ""),
    Port = proplists:get_value(port, Opts, 0),
    DB = proplists:get_value(db, Opts, 0),
    Password = proplists:get_value(password, Opts, ""),
    PoolSizeOrig = proplists:get_value(pool_size, Opts, 1),
    PoolSize = normalize_pool_size(PoolSizeOrig),
    PoolOpts = [ServiceName, PoolSize,
                    [eredis, eredis_client, eredis_parser],
                    {eredis, start_link, [Host, Port, DB, Password]}],
    {ServiceName,
     {cuesport, start_link, PoolOpts},
     permanent,
     infinity,
     supervisor,
     [eredis]
    }.

%%====================================================================
%% Internal functions
%%====================================================================

normalize_pool_size({each_scheduler, Base}) ->
    max(1, round(Base * erlang:system_info(schedulers)));
normalize_pool_size(Number) when is_number(Number)  ->

    max(1, round(Number)).
