%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_metrics.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  3 Jan 2019 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_metrics).
-export([add_event/2]).

add_event(Name, Num) ->
    case application:get_env(message_store, metrics_module, undefined) of
        undefined ->
            skip;
        Module ->
            Module:inc(event, [Name], Num)
    end.
