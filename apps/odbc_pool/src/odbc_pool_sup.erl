%%%-------------------------------------------------------------------------------------------------
%%% File    :  odbc_pool_sup.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :  odbc_pool top level supervisor.
%%% Created :  5 Dec 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(odbc_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

-export([
         start_service/1,
         stop_service/1,

         get_random_pid/1
        ]).

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


%%====================================================================
%% Internal functions
%%====================================================================

service_specs() ->
    {ok, ServiceNames} = application:get_env(odbc_pool, services),
    [service_spec(ServiceName)||ServiceName<-ServiceNames].

service_spec(ServiceName) ->
    {ok, Opts} = application:get_env(odbc_pool, ServiceName),
    Host = proplists:get_value(host, Opts, ""),
    Port = proplists:get_value(port, Opts, 0),
    Database = proplists:get_value(database, Opts, ""),
    Username = proplists:get_value(username, Opts, ""),
    Password = proplists:get_value(password, Opts, ""),
    PoolSizeOrig = proplists:get_value(pool_size, Opts, 1),
    PoolSize = normalize_pool_size(PoolSizeOrig),
    StartInterval = proplists:get_value(start_interval, Opts, 30),
    KeepaliveInterval = proplists:get_value(keepalive_interval, Opts, 90),
    Config = [
              {server, Host},
              {port, Port},
              {database, Database},
              {username, Username},
              {password, Password},
              {start_interval, StartInterval},
              {keepalive_interval, KeepaliveInterval}
             ],
    PoolOpts = [ServiceName, PoolSize,
                    [odbc_pool],
                    {odbc_pool, start_link, [Config]}],
    {ServiceName,
     {cuesport, start_link, PoolOpts},
     permanent,
     infinity,
     supervisor,
     [odbc_pool]
    }.

normalize_pool_size({each_scheduler, Base}) ->
    max(1, round(Base * erlang:system_info(schedulers)));
normalize_pool_size(Number) when is_number(Number)  ->

    max(1, round(Number)).

get_random_pid(odbc) ->
    cuesport:get_worker(odbc).


