%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_group_redis.erl
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
-module(msgst_group_redis).

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

-export([
         member_key/1
]).

is_user_muted(UserId, GroupId) ->
    case redis_pool:q(group, [zscore, mute_key(GroupId), UserId]) of
        {ok, undefined} ->
            false;
        {ok, ExpireTimeBin} ->
            Now = erlang:system_time(milli_seconds),
            ExpireTime = binary_to_integer(ExpireTimeBin),
            Now < ExpireTime orelse ExpireTime < 0;
        {error, Reason} ->
            {error, Reason}
    end.

is_group_member(UserId, GroupId) ->
    case redis_pool:q(group, [zscore, member_key(GroupId), UserId]) of
        {ok, undefined} ->
            false;
        {ok, _} ->
            true;
        {error, Reason} ->
            {error, Reason}
    end.

get_join_time(UserId, GroupId) ->
    case redis_pool:q(group, [zscore, member_key(GroupId), UserId]) of
        {ok, undefined} ->
            {error, not_found};
        {ok, Bin} ->
            {ok, binary_to_integer(Bin)};
        {error, Reason} ->
            {error, Reason}
    end.

get_group_members(GroupId) ->
    case redis_pool:q(group, [zrange, member_key(GroupId), 0, -1]) of
        {ok, UserIdBins} ->
            UserIds = lists:map(
                        fun(Bin) ->
                                binary_to_integer(Bin)
                        end, UserIdBins),
            {ok, UserIds};
        {error, Reason} ->
            {error, Reason}
    end.

get_group_members_count(GroupId) ->
    case redis_pool:q(group, [zcard, member_key(GroupId)]) of
        {ok, CountBin} ->
            {ok, binary_to_integer(CountBin)};
        {error, Reason} ->
            {error, Reason}
    end.

get_group_message_blocks(GroupId) ->
    case redis_pool:q(group, [smembers, message_block_key(GroupId)]) of
        {ok, UserIdBins} ->
            UserIds = lists:map(
                        fun(Bin) ->
                                binary_to_integer(Bin)
                        end, UserIdBins),
            {ok, UserIds};
        {error, Reason} ->
            {error, Reason}
    end.

get_group_apns_blocks(GroupId) ->
    case redis_pool:q(group, [hgetall, apns_block_key(GroupId)]) of
        {ok, BlockList} ->
            {ok, apns_block_list_to_users(BlockList, [])};
        {error, Reason} ->
            {error, Reason}
    end.

get_group_roles(GroupId, Role) ->
    case redis_pool:q(group, [smembers, role_key(GroupId, Role)]) of
        {ok, UserIdBins} ->
            UserIds = lists:map(
                        fun(Bin) ->
                                binary_to_integer(Bin)
                        end, UserIdBins),
            {ok, UserIds};
        {error, Reason} ->
            {error, Reason}
    end.

apns_block_list_to_users([UserIdBin, <<"1">>|Rest], Acc) ->
    apns_block_list_to_users(Rest, [binary_to_integer(UserIdBin)|Acc]);
apns_block_list_to_users([_,_|Rest], Acc) ->
    apns_block_list_to_users(Rest, Acc);
apns_block_list_to_users(_, Acc) ->
    Acc.

mute_key(GroupId) ->
    <<"g:mutes:",(integer_to_binary(GroupId))/binary>>.

member_key(GroupId) ->
    <<"g:users:", (integer_to_binary(GroupId))/binary>>.

message_block_key(GroupId) ->
    <<"g:blocks:", (integer_to_binary(GroupId))/binary>>.

apns_block_key(GroupId) ->
    <<"g:msg:notify:", (integer_to_binary(GroupId))/binary>>.

role_key(GroupId, Role) ->
    <<"g:roles:",Role/binary,":",  (integer_to_binary(GroupId))/binary>>.
