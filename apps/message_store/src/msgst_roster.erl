%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_roster.erl
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
-module(msgst_roster).

-export([get_relation/2, is_blocked/2]).

get_relation(UserId, OtherUserId) ->
    case db_type() of
        redis ->
            case msgst_roster_redis:get_relation(UserId, OtherUserId) of
                {error, not_found} ->
                    {ok, stranger};
                {error, Reason} ->
                    {error, Reason};
                {ok, Relation} ->
                    {ok, Relation}
            end;
        thrift_with_redis ->
            case msgst_roster_redis:get_relation(UserId, OtherUserId) of
                {ok, Relation} ->
                    {ok, Relation};
                {error, _} ->
                    msgst_roster_thrift:get_relation(UserId, OtherUserId)
            end
    end.

%% UserId is blocked by OtherUserId
is_blocked(UserId, OtherUserId) ->
    case db_type() of
        redis ->
            case msgst_roster_redis:is_blocked(UserId, OtherUserId) of
                {error, not_found} ->
                    {ok, false};
                {error, Reason} ->
                    {error, Reason};
                {ok, IsBlocked} ->
                    {ok, IsBlocked}
            end;
        thrift_with_redis ->
            case msgst_roster_redis:is_blocked(UserId, OtherUserId) of
                {ok, IsBlocked} ->
                    {ok, IsBlocked};
                _ ->
                    msgst_roster_thrift:is_blocked(UserId, OtherUserId)
            end
    end.

db_type() ->
    application:get_env(message_store, roster_db_type, redis).
