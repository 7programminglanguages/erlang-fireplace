%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_roster_thrift.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  28 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_roster_thrift).

-export([get_relation/2, is_blocked/2]).
-include("logger.hrl").
-include("roster_service_thrift.hrl").

get_relation(UserId, OtherUserId) ->
    case thrift_pool:thrift_call(roster_service_thrift, isFriend, [UserId, OtherUserId]) of
        {ok, Res} ->
            case Res of
                true ->
                    {ok, friend};
                false ->
                    {ok, stranger}
            end;
        {error, Reason} ->
            ?ERROR_MSG("isFriend failed: userId=~p, OtherUserId=~p, Reason=~p",
                       [UserId, OtherUserId, Reason]),
            {error, Reason};
        {exception, #'RosterException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("isFriend failed: userId=~p, OtherUserId=~p, Code=~p, Reason=~p",
                       [UserId, OtherUserId, Code, Reason]),
            {error, {Code, Reason}};
        {exception, Exception} ->
            ?ERROR_MSG("isFriend failed: userId=~p, OtherUserId=~p, Exception=~p",
                       [UserId, OtherUserId, Exception]),
            {error, {exception, Exception}}
    end.

%% UserId is blocked by OtherUserId
is_blocked(UserId, OtherUserId) ->
    case thrift_pool:thrift_call(roster_service_thrift, isBlocked, [UserId, OtherUserId]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            ?ERROR_MSG("isBlocked failed: userId=~p, OtherUserId=~p, Reason=~p",
                       [UserId, OtherUserId, Reason]),
            {error, Reason};
        {exception, #'RosterException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("isBlocked failed: userId=~p, OtherUserId=~p, Code=~p, Reason=~p",
                       [UserId, OtherUserId, Code, Reason]),
            {error, {Code, Reason}};
        {exception, Exception} ->
            ?ERROR_MSG("isBlocked failed: userId=~p, OtherUserId=~p, Exception=~p",
                       [UserId, OtherUserId, Exception]),
            {error, {exception, Exception}}
    end.
