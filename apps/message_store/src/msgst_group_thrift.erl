%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_group_thrift.erl
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
-module(msgst_group_thrift).

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

-include("logger.hrl").
-include("group_service_types.hrl").

is_user_muted(UserId, GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, isUserMuted, [GroupId, UserId]) of
        {ok, Res} ->
            Res;
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: userId=~p, GroupId=~p, Code=~p, Reason=~p",
                       [UserId, GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

is_group_member(UserId, GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, isGroupMember, [GroupId, UserId]) of
        {ok, Res} ->
            Res;
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: userId=~p, GroupId=~p, Code=~p, Reason=~p",
                       [UserId, GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

get_join_time(_UserId, _GroupId) ->
    {error, not_implement}.

get_group_members(GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, getGroupMembers, [GroupId]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: GroupId=~p, Code=~p, Reason=~p",
                       [GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

get_group_members_count(GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, getGroupMemberCount, [GroupId]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: GroupId=~p, Code=~p, Reason=~p",
                       [GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

get_group_message_blocks(GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, getGroupMsgBlocks, [GroupId]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: GroupId=~p, Code=~p, Reason=~p",
                       [GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

get_group_apns_blocks(GroupId) ->
    case thrift_pool:thrift_call(group_service_thrift, getGroupApnsBlocks, [GroupId]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: GroupId=~p, Code=~p, Reason=~p",
                       [GroupId, Code, Reason]),
            {error, {Code, Reason}}
    end.

get_group_roles(GroupId, Role) ->
    case thrift_pool:thrift_call(group_service_thrift, getGroupRoles, [GroupId, Role]) of
        {ok, Res} ->
            {ok, Res};
        {error, Reason} ->
            {error, Reason};
        {exception, #'GroupException'{errorCode = Code, reason = Reason}} ->
            ?ERROR_MSG("failed: GroupId=~p, Role=~p, Code=~p, Reason=~p",
                       [GroupId, Role, Code, Reason]),
            {error, {Code, Reason}}
    end.
