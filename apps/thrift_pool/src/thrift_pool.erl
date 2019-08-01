%%%-------------------------------------------------------------------------------------------------
%%% File    :  thrift_pool.erl
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
-module(thrift_pool).

-export([thrift_call/3, thrift_call/5]).

thrift_call(ServiceName, Call, Args) ->
    thrift_call(ServiceName, Call, Args, true, 1000).

thrift_call(ServiceName, Call, Args, Block, Timeout) ->
    try poolboy:checkout(ServiceName, Block, Timeout) of
        full ->
            {error, full};
        Pid ->
            do_thrift_call(ServiceName, Pid, Call, Args)
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.

do_thrift_call(ServiceName, Pid, Call, Args) ->
    try
        thrift_pool_worker:thrift_call(Pid, Call, Args)
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    after
            ok = poolboy:checkin(ServiceName, Pid)
    end.
