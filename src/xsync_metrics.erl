%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_metrics.erl
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

-module(xsync_metrics).

-include("logger.hrl").

-export([inc/2,inc/3, summary/2, summary/3, histogram/2, histogram/3]).

-export([inc_response/2, status/0, status/1, reset/0, reset/1]).

inc(Name, Value) ->
    inc(Name, [], Value).

inc(Name, LabelValues, Value) ->
    spawn(fun() ->
                  try
                      prometheus_counter:inc(Name, format_labels(LabelValues), Value)
                  catch
                      Class:Exception ->
                          ?ERROR_MSG("inc failed: name=~p, value=~p, labelvalues=~p, error=~p",
                                     [Name, Value, LabelValues, {Class,{Exception, erlang:get_stacktrace()}}])
                  end
          end),
    ok.

summary(Name, Value) ->
    summary(Name, [], Value).

summary(Name, LabelValues, Value) ->
    spawn(fun() ->
                  try
                      prometheus_summary:observe(Name, format_labels(LabelValues), Value)
                  catch
                      Class:Exception ->
                          ?ERROR_MSG("summary failed: name=~p, value=~p, labelvalues=~p, error=~p",
                                     [Name, Value, LabelValues, {Class,{Exception, erlang:get_stacktrace()}}])
                  end
          end),
    ok.

histogram(Name, Value) ->
    histogram(Name, [], Value).

histogram(Name, LabelValues, Value) ->
    spawn(fun() ->
                  try
                      prometheus_histogram:observe(Name, format_labels(LabelValues), Value)
                  catch
                      Class:Exception ->
                          ?ERROR_MSG("histogram failed: name=~p, value=~p, labelvalues=~p, error=~p",
                                     [Name, Value, LabelValues, {Class,{Exception, erlang:get_stacktrace()}}])
                  end
          end),
    ok.

format_labels(Labels) ->
    lists:map(
      fun(Label) when is_atom(Label) ->
              atom_to_binary(Label, utf8);
         (Binary) when is_binary(Binary) ->
              Binary
      end, Labels).

inc_response(Name, Response) ->
    {Code, Reason} = xsync_proto:get_status(Response),
    inc(Name, [Code, Reason], 1).

status() ->
    status("").

status(Patten)->
    Tokens = prometheus_tokens(Patten),
    Str = [io_lib:format("~ts~n", [Token])||Token<-Tokens],
    io:format("~ts", [Str]),
    ok.

prometheus_tokens(Patten) ->
    Data = prometheus_text_format:format(),
    Tokens = string:tokens(binary_to_list(Data),"\n"),
    lists:filtermap(
      fun("#"++_) ->
              false;
         (Token) ->
              case re:run(Token, Patten,[]) of
                  {match,_} ->
                      {true, Token};
                  _ ->
                      false
              end
      end, lists:sort(Tokens)).

reset() ->
    reset(default).
reset(Registry) ->
    prometheus_registry:collect(
      Registry,
      fun(_, xsync_status_collector) ->
              skip;
         (_, Collector) ->
              prometheus_collector:collect_mf(
                Registry, Collector,
                fun(MF) ->
                        Name = binary_to_atom(element(2,MF), utf8),
                        lists:foreach(
                          fun(M) ->
                                  LabelValues = [Value||{_,_,Value}<-element(2,M)],
                                  try Collector:remove(Registry, Name, LabelValues) of
                                      _Res -> ok
                                  catch _:_ ->
                                          skip
                                  end
                          end, element(5,MF))
                end)
      end).
