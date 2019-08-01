%%%-------------------------------------------------------------------------------------------------
%%% File    :  stream.erl
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
-module(stream).

-export([apply/2]).

apply(State,[]) ->
    State;
apply(State, [{M,F,A} | Rest]) ->
    ?MODULE:apply(erlang:apply(M,F,[State | A]), Rest);
apply(State, [{F,A} | Rest]) ->
    ?MODULE:apply(erlang:apply(F, [State | A]), Rest).
