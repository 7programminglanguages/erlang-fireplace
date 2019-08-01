%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_group_router.erl
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
-module(xsync_group_router).

-export([route/1]).
-include("xsync_pb.hrl").
-include("logger.hrl").
-include("messagebody_pb.hrl").

route(Meta) ->
    ?DEBUG("route: meta=~p", [xsync_proto:pr(Meta)]),
    try do_route(Meta) of
        ok ->
            ok;
        {error, Reason} ->
            ?INFO_MSG("fail to route: Meta=~p, Reason=~p",
                       [xsync_proto:pr(Meta), Reason]),
            {error, Reason}
    catch
        C:E ->
            ?ERROR_MSG("fail to route: Meta=~p, Error=~p",
                       [xsync_proto:pr(Meta), {C,{E,erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

do_route(Meta) ->
    case Meta of
        #'Meta'{ns = 'MESSAGE', payload = #'MessageBody'{qos = QoS}} ->
            do_route(Meta, QoS);
        _ ->
            do_route(Meta, 'AT_LEAST_ONCE')
    end.

do_route(Meta, 'AT_LEAST_ONCE') ->
    From = xsync_proto:get_meta_from(Meta),
    To = xsync_proto:get_meta_to(Meta),
    MsgId = xsync_proto:get_meta_id(Meta),
    #'XID'{uid = UserId} = From,
    #'XID'{uid = GroupId} = To,
    case check_route(UserId, GroupId, Meta) of
        {error, Reason} ->
            {error, Reason};
        {ok, MemberList, MessageBlocks} ->
            Body = xsync_proto:encode_meta(Meta),
            kafka_log:log_message_up(From, To, Meta),
            xsync_metrics:inc(message_up, [group], 1),
            case message_store:write_groupchat_body(MsgId, Body) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    SendList = (MemberList -- MessageBlocks) -- [UserId],
                    SkipList = MessageBlocks,
                    case Meta#'Meta'.ns of
                        'MESSAGE' ->
                            do_route_message(GroupId, Meta, SendList, SkipList);
                        'GROUP_NOTICE'->
                            do_route_group_notice(GroupId, Meta, SendList);
                        _ ->
                            {error, bad_meta_ns}
                    end
            end
    end;
do_route(Meta, 'AT_MOST_ONCE') ->
    From = xsync_proto:get_meta_from(Meta),
    To = xsync_proto:get_meta_to(Meta),
    #'XID'{uid = UserId} = From,
    #'XID'{uid = GroupId} = To,
    case check_route(UserId, GroupId, Meta) of
        {error, Reason} ->
            {error, Reason};
        {ok, MemberList, MessageBlocks} ->
            kafka_log:log_message_up(From, To, Meta),
            xsync_metrics:inc(message_up, [group_QoS0], 1),
            SendList = (MemberList -- MessageBlocks) -- [UserId],
            case Meta#'Meta'.ns of
                'MESSAGE' ->
                    do_route_message_by_push_metas(GroupId, [Meta], SendList);
                _ ->
                    {error, bad_meta_ns}
            end
    end;
do_route(Meta, _) ->
    do_route(Meta, 'AT_LEAST_ONCE').

do_route_message(GroupId, Meta, SendList, SkipList) ->
    From = xsync_proto:get_meta_from(Meta),
    MsgId = xsync_proto:get_meta_id(Meta),
    case message_store:write_groupchat_sharelist(From#'XID'.uid, GroupId, MsgId) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            route_message_for_send_list(GroupId, Meta, SendList),
            route_message_for_skip_list(SkipList, GroupId, MsgId),
            ok
    end.


do_route_message_by_push_metas(GroupId, Metas, SendList) ->
    SliceSize = get_group_slice_size(),
    slice_do(SendList, SliceSize,
             fun(SlicedSendList) ->
                     do_route_message_by_push_metas_sliced(GroupId, Metas, SlicedSendList)
             end),
    ok.

do_route_message_by_push_metas_sliced(GroupId, Metas, UserIdList) ->
    {OnlineSessionList, _OfflineUserList} = get_partition_sessions(UserIdList),
    notify_by_push_metas(OnlineSessionList, GroupId, Metas),
    xsync_metrics:inc(message_deliver, [group_msg_QoS0], length(UserIdList)),
    ok.

do_route_group_notice(_GroupId, Meta, SendList) ->
    SliceSize = get_group_slice_size(),
    slice_do(SendList, SliceSize,
             fun(SlicedSendList) ->
                     route_group_notice_sliced(SlicedSendList, Meta)
             end),
    ok.

route_group_notice_sliced(UserIdList, Meta) ->
    System = 0,
    MsgId = xsync_proto:get_meta_id(Meta),
    lists:foreach(
      fun(UserId) ->
              message_store:write_chat_index(System, UserId, 0, MsgId)
      end, UserIdList),
    {OnlineSessionList, _OfflineUserList} = get_partition_sessions(UserIdList),
    notify_by_notice(OnlineSessionList, System, Meta),
    xsync_metrics:inc(message_deliver, [group_event], length(UserIdList)),
    ok.

route_message_for_send_list(GroupId, Meta, SendList) ->
    SliceSize = get_group_slice_size(),
    slice_do(SendList, SliceSize,
             fun(SlicedSendList) ->
                     route_message_for_send_list_sliced(GroupId, Meta, SlicedSendList)
             end),
    ok.

route_message_for_skip_list(SkipList, GroupId, MsgId) ->
    spawn(fun()->
                  lists:foreach(
                    fun(UserId) ->
                            message_store:ack_messages(UserId, 0, GroupId, MsgId)
                    end, SkipList),
                  xsync_metrics:inc(message_deliver, [group_msg], length(SkipList))
          end),
    ok.

route_message_for_send_list_sliced(GroupId, Meta, UserIdList) ->
    MsgId = xsync_proto:get_meta_id(Meta),
    message_store:write_groupchat_index(UserIdList, GroupId, MsgId),
    {OnlineSessionList, OfflineUserList} = get_partition_sessions(UserIdList),
    notify_by_notice(OnlineSessionList, GroupId, Meta),
    notify_by_push(OfflineUserList, GroupId, Meta),
    xsync_metrics:inc(message_deliver, [group_msg], length(UserIdList)),
    ok.

get_partition_sessions(UserIdList) ->
    case msgst_session:get_sessions(UserIdList) of
        {error, _Reason} ->
            {[],UserIdList};
        {ok, SessionsList} ->
            UsersSessions = lists:zip(UserIdList, SessionsList),
            OnlineSessionList = [{UserId, Sessions}||{UserId, Sessions}<-UsersSessions, Sessions /= []],
            OfflineUserList = [UserId||{UserId, []}<-UsersSessions],
            {OnlineSessionList, OfflineUserList}
    end.

notify_by_notice(OnlineSessionList, GroupIdOrSys, Meta) ->
    MsgId = xsync_proto:get_meta_id(Meta),
    From = xsync_proto:make_xid(GroupIdOrSys, 0),
    Num = lists:foldl(
            fun({UserId, Sessions}, Acc) ->
                    lists:foldl(
                      fun({DeviceSN, Session}, Acc2) ->
                              Pid = msgst_session:get_session_pid(Session),
                              To = xsync_proto:make_xid(UserId, DeviceSN),
                              Pid ! {route, From, To, MsgId, []},
                              Acc2 + 1
                      end, Acc, Sessions)
            end, 0, OnlineSessionList),
    xsync_metrics:inc(message_deliver, [group_notice], Num),
    ok.

notify_by_push(PushList, GroupId, Meta) ->
    From = xsync_proto:make_xid(GroupId, 0),
    message_store:incr_apns(PushList, 1),
    lists:foreach(
      fun(UserId) ->
              To = xsync_proto:make_xid(UserId),
              kafka_log:log_message_offline(From, To, Meta)
      end, PushList),
    xsync_metrics:inc(message_deliver, [group_push], length(PushList)),
    ok.

notify_by_push_metas(OnlineSessionList, GroupIdOrSys, Metas) ->
    From = xsync_proto:make_xid(GroupIdOrSys, 0),
    Num = lists:foldl(
            fun({UserId, Sessions}, Acc) ->
                    lists:foldl(
                      fun({DeviceSN, Session}, Acc2) ->
                              Pid = msgst_session:get_session_pid(Session),
                              To = xsync_proto:make_xid(UserId, DeviceSN),
                              Pid ! {route, From, To, Metas, []},
                              Acc2 + 1
                      end, Acc, Sessions)
            end, 0, OnlineSessionList),
    xsync_metrics:inc(message_deliver, [group_push_meta], Num),
    ok.

check_route(UserId, GroupId, _Meta) ->
    case check_user_is_allowed(UserId, GroupId) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            case check_user_is_muted(UserId, GroupId) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    case msgst_group:get_group_members(GroupId) of
                        {error, _Reason} ->
                            {error, db_error};
                        {ok, MemberList} ->
                            case msgst_group:get_group_message_blocks(GroupId) of
                                {error, _Reason} ->
                                    {error, db_error};
                                {ok, MessageBlocks} ->
                                    {ok, MemberList, MessageBlocks}
                            end
                    end
            end
    end.

check_user_is_allowed(0, _) ->
    ok;
check_user_is_allowed(UserId, GroupId) ->
    case msgst_group:is_group_member(UserId, GroupId) of
        {error, _Reason} ->
            {error, db_error};
        false ->
            {error, not_member};
        true ->
            ok
    end.

check_user_is_muted(0, _) ->
    ok;
check_user_is_muted(UserId, GroupId) ->
    case msgst_group:is_user_muted(UserId, GroupId) of
        {error, _Reason} ->
            {error, db_error};
        true ->
            {error, user_muted};
        false ->
            ok
    end.

slice_do(L, N, Fun) ->
    slice_do(L, N, Fun, 1, []).
slice_do([E|L], N, Fun, Now, Acc) when Now =< N ->
    slice_do(L, N, Fun, Now+1, [E|Acc]);
slice_do([E|L], N, Fun, _Now, Acc) ->
    spawn(fun() -> Fun(Acc) end),
    slice_do(L, N, Fun, 2, [E]);
slice_do([], _, Fun, _, Acc) ->
    spawn(fun()->Fun(Acc) end).

get_group_slice_size() ->
    application:get_env(xsync, group_slice_size, 200).
