%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_status_collector.erl
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
-module(xsync_status_collector).

-export([deregister_cleanup/1,
         collect_mf/2]).

-export([client_num/0,
         message_queue_len/1,
         run_queue/0,
         process_num/0
]).

%%====================================================================
%% Collector API
%%====================================================================

collect_mf(_Registry, Callback) ->
    Metrics = metrics(),
    Timeout = application:get_env(xsync, status_collector_timeout, 2000),
    MetricValues = collect_pal(Metrics, Timeout),
    [Callback(prometheus_model_helpers:create_mf(Key, Desc, gauge, Value))
              ||{Key, Desc, Value}<-MetricValues],
    ok.

deregister_cleanup(_Registry) ->
    ok.

metrics() ->
    DynamicMetrics = application:get_env(xsync, status_collector_metrics, []),
    StaticMetrics =
        [
         {sys_run_queue, "The number of processes and ports that are ready to run", {?MODULE, run_queue, []}},
         {sys_online_num, "Number of client connect to this server", {?MODULE, client_num, []}},
         {sys_message_queue_len, "Total message queue length", {?MODULE, message_queue_len, [[self()]]}},
         {sys_process_num, "Total process num", {?MODULE, process_num, []}}
        ],
    StaticMetrics ++ DynamicMetrics.

collect_pal(Metrics, Timeout) ->
    collect_pal(Metrics, [], [], erlang:monotonic_time(milli_seconds) + Timeout).

collect_pal([{Key, Desc, {M,F,A}}|Metrics], Refs, ValueList, EndTime) ->
    {Pid, Ref} = spawn_monitor(
                   fun() ->
                           exit({collect_value, xsync_status_serial:serial(M,F,A,Key)})
                   end),
    collect_pal(Metrics,[{Ref, Key, Desc, Pid}|Refs], ValueList, EndTime);
collect_pal([], [], ValueList, _EndTime) ->
    ValueList;
collect_pal([], Refs, ValueList, EndTime) ->
    Timeout = max(0,EndTime - erlang:monotonic_time(milli_seconds)),
    receive
        {'DOWN', Ref, process, Pid, {collect_value, Value}} ->
            case lists:keyfind(Ref, 1, Refs) of
                {Ref, Key, Desc, Pid} ->
                    NewValueList = [{Key, Desc, Value}||is_integer(Value)] ++ ValueList,
                    collect_pal([], lists:keydelete(Ref, 1, Refs), NewValueList, EndTime);
                false ->
                    collect_pal([], Refs, ValueList, EndTime)
            end;
        {'DOWN', Ref, process, _Pid, _} ->
            collect_pal([], lists:keydelete(Ref, 1, Refs), ValueList, EndTime)
    after Timeout ->
            lists:foreach(
              fun({Ref, _Key, _Desc, Pid}) ->
                      exit(Pid, kill),
                      receive
                          {'DOWN', Ref, process, Pid, _} ->
                              ok
                      end
              end, Refs),
            ValueList
    end.

client_num() ->
    ranch_conns_sup:active_connections(ranch_server:get_connections_sup(xsync_server)).

message_queue_len(Excludes) ->
    Max = application:get_env(xsync, max_total_message_queue_len, 10000),
    lists:foldl(
      fun(Pid, Acc) when Acc < Max ->
              case lists:member(Pid, Excludes) of
                  true ->
                      Acc;
                  false ->
                      case erlang:process_info(Pid, message_queue_len) of
                          {message_queue_len, Len} ->
                              Len + Acc;
                          _ ->
                              Acc
                      end
              end;
         (_, Acc) ->
              Acc
      end, 0, erlang:processes()).

run_queue() ->
    erlang:statistics(run_queue).

process_num() ->
    length(erlang:processes()).
