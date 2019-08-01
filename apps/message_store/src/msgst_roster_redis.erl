%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_roster_redis.erl
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
-module(msgst_roster_redis).

-export([get_relation/2, is_blocked/2]).

get_relation(UserId, OtherUserId) ->
    case redis_pool:q(roster, [get, roster_key(UserId, OtherUserId)]) of
        {ok, <<"0">>} ->
            {ok, friend};
        {ok, <<"1">>} ->
            {ok, friend_deleted};
        {ok, undefined} ->
            {error, not_found};
        {ok, _} ->
            {ok, stranger};
        {error, Reason} ->
            {error, Reason}
    end.

%% UserId is blocked by OtherUserId
is_blocked(UserId, OtherUserId) ->
    case redis_pool:q(roster, [get, privacy_key(UserId, OtherUserId)]) of
        {ok, <<"1">>} ->
            {ok, true};
        {ok, <<"0">>} ->
            {ok, false};
        {ok, undefined} ->
            {error, not_found};
        {ok, _} ->
            {ok, false};
        {error, Reason} ->
            {error, Reason}
    end.

roster_key(UserId, OtherUserId) when UserId > OtherUserId ->
    <<"roster:",(integer_to_binary(UserId))/binary,":", (integer_to_binary(OtherUserId))/binary>>;
roster_key(UserId, OtherUserId) ->
    <<"roster:",(integer_to_binary(OtherUserId))/binary,":", (integer_to_binary(UserId))/binary>>.

privacy_key(UserId, OtherUserId) ->
    <<"privacy:",(integer_to_binary(UserId))/binary,":", (integer_to_binary(OtherUserId))/binary>>.
