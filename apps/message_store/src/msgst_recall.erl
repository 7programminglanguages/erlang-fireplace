%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_recall.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :
%%% Created :  14 Nov 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(msgst_recall).

-export([
         recall/1
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

recall(MID) ->
    case msgst_body:read(MID) of
        {error, <<"not found">>} ->
            ok;
        {error, Reason} ->
            {error, Reason};
        {ok, _MBody} ->
            msgst_body:delete(MID)
    end.


%%****************************************************************************
%% internal functions
%%****************************************************************************


