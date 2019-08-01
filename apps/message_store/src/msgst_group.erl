%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_group.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  18 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_group).

-export([
         is_user_muted/2,
         is_group_member/2,
         get_group_members/1,
         get_group_members_count/1,
         get_group_message_blocks/1,
         get_group_apns_blocks/1,
         get_group_roles/2,
         get_join_time/2
        ]).

is_user_muted(UserId, GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:is_user_muted(UserId, GroupId);
        thrift_with_redis ->
            case msgst_group_redis:is_user_muted(UserId, GroupId) of
                true ->
                    true;
                _ ->
                    msgst_group_thrift:is_user_muted(UserId, GroupId)
            end
    end.

is_group_member(UserId, GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:is_group_member(UserId, GroupId);
        thrift_with_redis ->
            case msgst_group_redis:is_group_member(UserId, GroupId) of
                true ->
                    true;
                _ ->
                    msgst_group_thrift:is_group_member(UserId, GroupId)
            end
    end.

get_join_time(UserId, GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:get_join_time(UserId, GroupId);
        thrift_with_redis ->
            case msgst_group_redis:get_join_time(UserId, GroupId) of
                {ok, Time} ->
                    {ok, Time};
                {error, _} ->
                    msgst_group_thrift:get_join_time(UserId, GroupId)
            end
    end.

get_group_members(GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:get_group_members(GroupId);
        thrift_with_redis ->
            case msgst_group_redis:get_group_members(GroupId) of
                {ok, L} when L /= [] ->
                    {ok, L};
                _ ->
                    msgst_group_thrift:get_group_members(GroupId)
            end
    end.

get_group_members_count(GroupId) ->
     case db_type() of
        redis ->
            msgst_group_redis:get_group_members_count(GroupId);
        thrift_with_redis ->
            case msgst_group_redis:get_group_members_count(GroupId) of
                {ok, Num} when Num /= 0 ->
                    {ok, Num};
                _ ->
                    msgst_group_thrift:get_group_members_count(GroupId)
            end
    end.

get_group_message_blocks(GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:get_group_message_blocks(GroupId);
        thrift_with_redis ->
            case msgst_group_redis:get_group_message_blocks(GroupId) of
                {ok, L} when L /= [] ->
                    {ok, L};
                _ ->
                    msgst_group_thrift:get_group_message_blocks(GroupId)
            end
    end.

get_group_apns_blocks(GroupId) ->
    case db_type() of
        redis ->
            msgst_group_redis:get_group_apns_blocks(GroupId);
        thrift_with_redis ->
            case msgst_group_redis:get_group_apns_blocks(GroupId) of
                {ok, L} when L /= [] ->
                    {ok, L};
                _ ->
                    msgst_group_thrift:get_group_apns_blocks(GroupId)
            end
    end.

get_group_roles(GroupId, Role) ->
    case db_type() of
        redis ->
            msgst_group_redis:get_group_roles(GroupId, Role);
        thrift_with_redis ->
            case msgst_group_redis:get_group_roles(GroupId, Role) of
                {ok, L} when L /= [] ->
                    {ok, L};
                _ ->
                    msgst_group_thrift:get_group_roles(GroupId, Role)
            end
    end.

db_type() ->
    application:get_env(message_store, group_db_type, redis).
