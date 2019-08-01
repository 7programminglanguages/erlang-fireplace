%%%-------------------------------------------------------------------------------------------------
%%% File    :  redis_pool.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  9 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(redis_pool).

-export([q/2, qp/2, check/0, check/1]).
-include("logger.hrl").

q(Service, Command) ->
    try
        Pid = cuesport:get_worker(Service),
        case eredis:q(Pid, Command, get_timeout()) of
            {error, Reason} ->
                ?ERROR_MSG("redis q error: Service=~p, Command=~p, Error=~p",
                           [Service, Command, Reason]),
                maybe_add_metrics(Service, Reason, 1),
                {error, Reason};
            {ok, Value} ->
                maybe_add_metrics(Service, ok, 1),
                {ok, Value}
        end
    catch
        exit:{timeout, _} ->
            ?ERROR_MSG("redis error: Service=~p, Command=~p, Error=~p",
                       [Service, Command, timeout]),
            maybe_add_metrics(Service, timeout, 1),
            {error, timeout};
        Class:Exception ->
            ?ERROR_MSG("redis error: Service=~p, Command=~p, Error=~p",
                       [Service, Command, {Class, {Exception, erlang:get_stacktrace()}}]),
            maybe_add_metrics(Service, exit, 1),
            {error, {Class, Exception}}
    end.

qp(Service, Commands) ->
    try
        Pid = cuesport:get_worker(Service),
        case eredis:qp(Pid, Commands, get_timeout()) of
            {error, Reason} ->
                ?ERROR_MSG("redis error: Service=~p, Commands=~p, Error=~p",
                           [Service, Commands, Reason]),
                maybe_add_metrics(Service, Reason, length(Commands)),
                {error, Reason};
            Values when is_list(Values)  ->
                check_qp_values(Service, Commands, Values),
                maybe_add_metrics(Service, ok, length(Values)),
                Values
        end
    catch
        exit:{timeout, _} ->
            ?ERROR_MSG("redis error: Service=~p, Commands=~p, Error=~p",
                       [Service, Commands, timeout]),
            maybe_add_metrics(Service, timeout, length(Commands)),
            {error, timeout};
        Class:Exception ->
            ?ERROR_MSG("redis error: Service=~p, Commands=~p, Error=~p",
                       [Service, Commands, {Class, {Exception, erlang:get_stacktrace()}}]),
            maybe_add_metrics(Service, exit, length(Commands)),
            {error, {Class, Exception}}
    end.

get_timeout() ->
    application:get_env(redis_pool, default_timeout, 5000).

check_qp_values(Service, Commands, Values) ->
    lists:foreach(
      fun({Command, {error, Reason}}) ->
              ?ERROR_MSG("redis error: Service=~p, Command=~p, Error=~p",
                         [Service, Command, Reason]),
              {error, Reason};
         ({_Command, {ok, Value}}) ->
              {ok, Value}
      end, lists:zip(Commands, Values)).

maybe_add_metrics(Service, Result, Num) ->
    case application:get_env(redis_pool, metrics_module, undefined) of
        undefined ->
            skip;
        Module ->
            Module:inc(redis, [Service, Result], Num)
    end.


check() ->
    Clients = application:get_env(redis_pool, services, []),
    maps:from_list(lists:map(
                     fun(Client) ->
                             check(Client)
                     end, Clients)).

check(Client) ->
    try
        Pids = [Pid||{_, Pid}<-ets:tab2list(Client),
                     is_pid(Pid)],
        ResList = lists:map(
                    fun(Pid) ->
                            try eredis:q(Pid, [get, check_redis]) of
                                {ok, _} ->
                                    {Pid, ok};
                                Other ->
                                    {Pid, Other}
                            catch
                                C:E ->
                                    {Pid, {C,E}}
                            end
                    end, Pids),
        {Client, maps:from_list(ResList)}
    catch
        C:E ->
            {Client, {C,E}}
    end.
