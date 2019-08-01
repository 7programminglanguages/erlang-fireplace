%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_groupchat_index.erl
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

-module(msgst_groupchat_index).

-export([
         write/3,
         write_sharelist/3,

         init/2,
         clean/2,

         get_unread_messages/4,
         ack_messages/4,
         sync_multi_device/4,
         roam/4,
         cursor_key/2,
         write_history/3,
         write_history_event/4
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

% TODO, how to handle too many unread msgs
write(UserList, Group, _MID) when is_list(UserList) ->
    case msgst_device:get_avail_device_list(UserList) of
        {ok, DeviceListList} ->
            AllQueries = lists:flatmap(
                           fun({_User, {error, _Reason}}) ->
                                   [];
                              ({User, DeviceList}) ->
                                   lists:flatmap(
                                     fun(Device) ->
                                             make_write_redis_query(Group, User, Device)
                                     end, DeviceList)
                           end, lists:zip(UserList, DeviceListList)),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, AllQueries) of
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% write group share list,
%% and will do trim when len is greater than ?REDIS_GROUPCHAT_MID_MAX
write_sharelist(From, Group, MID) ->
    ShareListKey = share_list_key(Group),
    Query = ["LPUSH", ShareListKey, MID],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, LenBin} ->
            case binary_to_integer(LenBin) >  ?REDIS_GROUPCHAT_MID_MAX of
                true ->
                    spawn(fun() -> ltrim_share_list(Group) end);
                false ->
                    skip
            end,
            spawn(fun() -> msgst_history:add_group_index(From, Group, MID) end),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

ltrim_share_list(Group) ->
    ShareListKey = share_list_key(Group),
    Query = ["LTRIM", ShareListKey, 0, ?REDIS_GROUPCHAT_MID_LIMIT],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

init(Group, User) ->
    case get_init_mid(Group) of
        {ok, MID} ->
            case msgst_device:get_avail_device_list(User) of
                {ok, DeviceList} ->
                    AllQueries = lists:map(
                        fun(Device) ->
                            ["HSET", cursor_key(User, Device), Group, MID]
                        end, DeviceList),
                    case redis_pool:qp(?REDIS_INDEX_SERVICE, AllQueries) of
                        {error, Reason} ->
                            {error, Reason};
                        _ ->
                            spawn(fun() -> msgst_history:add_event(User, Group, 0, MID) end),
                            ok
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

clean(Group, User) ->
    case msgst_device:get_avail_device_list(User) of
        {ok, DeviceList} ->
            AllQueries = lists:map(
                fun(Device) ->
                    ["HDEL", cursor_key(User, Device), Group]
                end, DeviceList),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, AllQueries) of
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    maybe_remove_no_cursor_unread(User, Group),
                    spawn(fun() ->
                                  case get_history_latest_mid(Group) of
                                      {ok, MID} ->
                                          msgst_history:add_event(User, Group, 1, MID);
                                      {error, Reason} ->
                                          {error, Reason}
                                  end
                          end),
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end.

get_unread_messages(User, DeviceSN, Group, _StartMID) ->
    Device = msgst_device:get_avail_device(User, DeviceSN),
    case get_mid_list(Group) of
        {ok, []} ->
            {ok, {[], undefined}};
        {error, Reason} ->
            {error, Reason};
        {ok, MIDList} ->
            ReverseMIDList = lists:reverse(MIDList),
            case unread_mids(User, Device, Group, ReverseMIDList) of
                {error, Reason} ->
                    {error, Reason};
                UnreadMIDs ->
                    LimitMIDList = lists:sublist(UnreadMIDs, ?SYNC_MSG_NUM_LIMIT),
                    case msgst_body:read(LimitMIDList) of
                        {ok, MBodyList} ->
                            AvailMBodyList = filter_body(MBodyList, []),
                            {ok, {AvailMBodyList, next_mid(LimitMIDList)}};
                        {error, Reason} ->
                            {error, Reason}
                    end
            end
    end.

next_mid([]) ->
    undefined;
next_mid(L) ->
    lists:last(L).

ack_messages(User, 0, Group, StartMID) ->
    case msgst_device:get_avail_device_list(User) of
        {ok, DeviceList} ->
            lists:foreach(
              fun(Device) ->
                      ack_messages_1(User, Device, Group, StartMID)
              end, DeviceList),
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end;
ack_messages(User, DeviceSN, Group, StartMID) ->
    DefaultDevice = msgst_device:get_default_device(),
    Device = msgst_device:get_avail_device(User, DeviceSN),
    case Device of
        DefaultDevice ->
            ack_messages_1(User, Device, Group, StartMID);
        _ ->
            case ack_messages_1(User, Device, Group, StartMID) of
                {ok, Result} ->
                    spawn(fun() ->
                                  ack_messages_1(User, DefaultDevice, Group, StartMID)
                          end),
                    {ok, Result};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ack_messages_1(User, Device, Group, StartMID) ->
    case get_user_cursor(User, Device, Group) of
        {error, Reason} ->
            {error, Reason};
        {ok, undefined} ->
            {ok, []};
        {ok, Cursor} ->
            do_ack_messages(User, Device, Group, Cursor, StartMID)
    end.

sync_multi_device(From, _CurDevice, Group, _MID) ->
    case msgst_device:get_avail_device_list(From) of
        {ok, DeviceList} ->
            Queries = lists:append(lists:map(fun(Device) -> make_write_redis_query(Group, From, Device) end, DeviceList)),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end.

roam(User, Group, StartMID, Num) ->
    case get_roam_mids(User, Group, StartMID, Num) of
        {error, Reason} ->
            {error, Reason};
        {ok, []} ->
            {ok, {[], undefined}};
        {ok, MIDDescList} ->
            case msgst_body:read_odbc(lists:reverse(MIDDescList)) of
                {error, Reason} ->
                    {error, Reason};
                {ok, BodyList} ->
                    NextMID = lists:last(MIDDescList),
                    {ok, {BodyList, NextMID}}
            end
    end.

%%****************************************************************************
%% internal functions
%%****************************************************************************

make_write_redis_query(Group, User, Device) ->
    % add unread num
    UnreadNumKey = unread_num_key(User, Device),
    Query2 = ["HINCRBY", UnreadNumKey, Group, 1],
    Query3 = ["HINCRBY", UnreadNumKey, ?TOTAL_KEY, 1],
    [Query2, Query3].

make_ack_redis_query(User, Device, Group, MIDList, StartMID) ->
    UnreadNumKey = unread_num_key(User, Device),
    Num = 0 - erlang:length(MIDList),
    Query1 = ["HINCRBY", UnreadNumKey, Group, Num],
    Query2 = ["HINCRBY", UnreadNumKey, ?TOTAL_KEY, Num],
    Query3 = ["HSET", cursor_key(User, Device), Group, StartMID],
    [Query1, Query2, Query3].

unread_num_key(User, Device) ->
    <<?UNREAD_CONVERSATION_KEY_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(Device))/binary>>.

share_list_key(Group) ->
    <<?UNREAD_SHARE_LIST_KEY_PREFIX/binary, (integer_to_binary(Group))/binary>>.

get_init_mid(Group) ->
    ShareListKey = share_list_key(Group),
    Query = ["LINDEX", ShareListKey, 0],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, undefined} ->
            {ok, 0};
        {ok, MidBin} ->
            {ok, binary_to_integer(MidBin)};
        {error, Reason} ->
            {error, Reason}
    end.

cursor_key(User, Device) ->
    <<?UNREAD_CURSOR_KEY_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(Device))/binary>>.

get_mid_list(Group) ->
    ShareListKey = share_list_key(Group),
    Query = ["LRANGE", ShareListKey, 0, ?REDIS_LRANGE_LIMIT],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, MidBinList} ->
            {ok, lists:map(fun(MidBin) -> binary_to_integer(MidBin) end, MidBinList)};
        {error, Reason} ->
            {error, Reason}
    end.

unread_mids(User, Device, Group, MIDList) ->
    case get_user_cursor(User, Device, Group) of
        % user could not get msg if cursor is undefined
        {ok, undefined} ->
            [];
        {error, Reason} ->
            {error, Reason};
        {ok, Cursor} ->
            unread_mids(MIDList, Cursor)
    end.

unread_mids(MIDList, Cursor) ->
    case lists:dropwhile(fun(MID) -> MID /= Cursor end, MIDList) of
        [Cursor | ResMIDList] ->
            ResMIDList;
        _ ->
            MIDList
    end.

get_user_cursor(User, Device, Group) ->
    CursorKey = cursor_key(User, Device),
    Query = ["HGET", CursorKey, Group],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, undefined} ->
            Cursor = maybe_repair_undefined_cursor(User, Device, Group),
            {ok, Cursor};
        {ok, CursorBin} ->
            {ok, binary_to_integer(CursorBin)};
        {error, Reason} ->
            {error, Reason}
    end.

maybe_repair_undefined_cursor(User, _Device, Group) ->
    case msgst_group:is_group_member(User, Group) of
        true ->
            ?INFO_MSG("Repair user cursor: User=~p, Group=~p", [User, Group]),
            msgst_metrics:add_event(repair_user_cursor, 1),
            case repair(Group, User) of
                {ok, MID} ->
                    MID;
                _ ->
                    undefined
            end;
        false ->
            maybe_remove_no_cursor_unread(User, Group),
            undefined;
        _ ->
            undefined
    end.

repair(Group, User) ->
    case get_repair_mid(Group) of
        {ok, MID} ->
            case msgst_device:get_avail_device_list(User) of
                {ok, DeviceList} ->
                    AllQueries = lists:map(
                        fun(Device) ->
                            ["HSETNX", cursor_key(User, Device), Group, MID]
                        end, DeviceList),
                    case redis_pool:qp(?REDIS_INDEX_SERVICE, AllQueries) of
                        {error, Reason} ->
                            {error, Reason};
                        _ ->
                            {ok, MID}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

get_repair_mid(Group) ->
    ShareListKey = share_list_key(Group),
    Query = ["LRANGE", ShareListKey, 0, 1],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, L} ->
            case lists:reverse(L) of
                [MidBin|_] ->
                    {ok, binary_to_integer(MidBin)};
                [] ->
                    {ok, 0}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

get_unread(User, Device, Group) ->
    UnreadNumKey = unread_num_key(User, Device),
    case redis_pool:q(?REDIS_INDEX_SERVICE, ["HGET", UnreadNumKey, Group]) of
        {ok, undefined} ->
            {ok, 0};
        {ok, NumBin} ->
            Num = binary_to_integer(NumBin),
            {ok, Num};
        {error, Reason} ->
            {error, Reason}
    end.

delete_unread(User, Device, Group) ->
    UnreadNumKey = unread_num_key(User, Device),
    case redis_pool:q(?REDIS_INDEX_SERVICE, ["HDEL", UnreadNumKey, Group]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

incr_total_unread(User, Device, Group, Num) ->
    UnreadNumKey = unread_num_key(User, Device),
    case redis_pool:q(?REDIS_INDEX_SERVICE, ["HINCRBY", UnreadNumKey, Group, Num]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

maybe_remove_no_cursor_unread(User, Group) ->
    case msgst_device:get_avail_device_list(User) of
        {error, Reason} ->
            {error, Reason};
        {ok, DeviceList} ->
            lists:foreach(
              fun(Device) ->
                      case get_unread(User, Device, Group) of
                          {error, Reason} ->
                              {error, Reason};
                          {ok, Num} ->
                              case delete_unread(User, Device, Group) of
                                  {error, Reason} ->
                                      {error, Reason};
                                  ok ->
                                      case Num > 0 of
                                          true ->
                                              incr_total_unread(User, Device, Group, -Num);
                                          false ->
                                              skip
                                      end
                              end
                      end
              end, DeviceList)
    end.

mids_to_be_acked_by_cursor(MIDList, Cursor, StartMID) ->
    UnAckMIDs = unread_mids(MIDList, Cursor),
    mids_to_be_acked(UnAckMIDs, StartMID).

mids_to_be_acked(MIDList, StartMID) ->
    mids_to_be_acked(MIDList, StartMID, []).

mids_to_be_acked([StartMID|_MIDList], StartMID, Acc) ->
    lists:reverse([StartMID|Acc]);
mids_to_be_acked([MID|MIDList], StartMID, Acc) ->
    mids_to_be_acked(MIDList, StartMID, [MID|Acc]);
mids_to_be_acked([], _, _) ->
    [].

filter_body([{error, _} | MBodyList], AvailMBodyList) ->
    filter_body(MBodyList, AvailMBodyList);
filter_body([MBody | MBodyList], AvailMBodyList) ->
    filter_body(MBodyList, [MBody | AvailMBodyList]);
filter_body([], AvailMBodyList) ->
    AvailMBodyList.

do_ack_messages(User, Device, Group, Cursor, StartMID) ->
    case get_mid_list(Group) of
        {ok, []} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason};
        {ok, MIDList} ->
            ReverseMIDList = lists:reverse(MIDList),
            case mids_to_be_acked_by_cursor(ReverseMIDList, Cursor, StartMID) of
                {error, Reason} ->
                    {error, Reason};
                [] ->
                    {ok, []};
                UnAckMIDs ->
                    Queries = make_ack_redis_query(User, Device, Group, UnAckMIDs, StartMID),
                    case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
                        {error, Reason} ->
                            {error, Reason};
                        _ ->
                            {ok, UnAckMIDs}
                    end
            end
    end.

write_history(From, Group, MID) ->
    case application:get_env(message_store, enable_message_history_write_odbc, true) of
        true ->
            Res1 = write_history_1(From, Group, 0, MID),
            Res2 = write_history_1(Group, From, 1, MID),
            {Res1, Res2};
        false ->
            skip
    end.

write_history_1(From, Group, Type, MID) ->
    Query= [<<"insert into message_history (uid, opposite, type, mid) values (">>,
             integer_to_binary(From), <<", ">>, integer_to_binary(Group), <<", ">>,
             integer_to_binary(Type), <<", ">>, integer_to_binary(MID), <<");">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {updated, _} ->
            ok;
        {error, Reason} ->
            ?ERROR_MSG("write history error, Reason:~p, From: ~p, Group:~p, Type:~p, MID:~p~n",
                       [Reason, From, Group, Type, MID]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("write history exception, Class:~p, Exception:~p, From: ~p, Group:~p, Type:~p, MID:~p~n",
                [Class, Exception, From, Group, Type, MID]),
            {error, Exception}
    end.

get_history_latest_mid(Group) ->
    ShareListKey = share_list_key(Group),
    Query = ["LRANGE", ShareListKey, 0, 1],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, [MIDBin | _]} ->
            {ok, binary_to_integer(MIDBin)};
        {ok, []} ->
            {ok, 0};
        {error, Reason} ->
            {error, Reason}
    end.

write_history_event(User, Group, Type, MID) ->
    case application:get_env(message_store, enable_message_history_write_odbc, true) of
        true ->
            write_history_event_1(User, Group, Type, MID);
        false ->
            skip
    end.

write_history_event_1(User, Group, Type, MID) ->
    Query= [<<"insert into message_history_event (uid, gid, type, mid) values (">>,
             integer_to_binary(User), <<", ">>, integer_to_binary(Group), <<", ">>,
             integer_to_binary(Type), <<", ">>, integer_to_binary(MID), <<");">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {error, Reason} ->
            ?ERROR_MSG("write history event error, Reason:~p, User: ~p, Group:~p, Type:~p, MID:~p~n",
                [Reason, User, Group, Type, MID]),
            {error, Reason};
        _ ->
            ok
    catch
        Class:Exception ->
            ?ERROR_MSG("write history event exception, Class:~p, Exception:~p, User: ~p, Group:~p, Type:~p, MID:~p~n",
                [Class, Exception, User, Group, Type, MID]),
            {error, Exception}
    end.

get_roam_mids(User, Group, StartMID, Num) ->
    % must be a group member ?
    case msgst_group:is_group_member(User, Group) of
        true ->
            % without limit: could roam all messages of the group
            % limited: could roam messages only when in group
            case application:get_env(message_store, roam_group_message_without_limit, false) of
                true ->
                    get_roam_mids_without_limit(User, Group, StartMID, Num);
                false ->
                    get_roam_mids_limited(User, Group, StartMID, Num)
            end;
        false ->
            {ok, []}
    end.

get_roam_mids_without_limit(User, Group, 0, Num) when Num > 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
            <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, reslist_to_mid_list(ResList)};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Group, 0, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Group, 0, Num]),
            {error, Exception}
    end;
get_roam_mids_without_limit(User, Group, StartMID, Num) when Num > 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
            <<" and mid < ">>, integer_to_binary(StartMID),
            <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, reslist_to_mid_list(ResList)};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Group, StartMID, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Group, StartMID, Num]),
            {error, Exception}
    end;
get_roam_mids_without_limit(User, Group, StartMID, Num) when Num < 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
            <<" and mid > ">>, integer_to_binary(StartMID),
            <<" and is_del = 0 order by mid asc limit ">>, integer_to_binary(-Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, lists:reverse(reslist_to_mid_list(ResList))};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Group, StartMID, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Group, StartMID, Num]),
            {error, Exception}
    end;
get_roam_mids_without_limit(_,_,_,_) ->
    {ok, []}.

get_roam_mids_limited(User, Group, 0, Num) when Num > 0 ->
    case get_limited_condition(User, Group) of
        {error, Reason} ->
            {error, Reason};
        {ok, Condition} ->
            Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
                    Condition,
                    <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
            try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
                {selected, [<<"mid">>], ResList} ->
                    {ok, reslist_to_mid_list(ResList)};
                {error, Reason} ->
                    ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Reason, User, Group, 0, Num]),
                    {error, Reason}
            catch
                Class:Exception ->
                    ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                        "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Class, Exception, User, Group, 0, Num]),
                    {error, Exception}
            end
    end;
get_roam_mids_limited(User, Group, StartMID, Num) when Num > 0 ->
    case get_limited_condition(User, Group) of
        {error, Reason} ->
            {error, Reason};
        {ok, Condition} ->
            Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
                    <<" and mid < ">>, integer_to_binary(StartMID),
                    Condition,
                    <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
            try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
                {selected, [<<"mid">>], ResList} ->
                    {ok, reslist_to_mid_list(ResList)};
                {error, Reason} ->
                    ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Reason, User, Group, StartMID, Num]),
                    {error, Reason}
            catch
                Class:Exception ->
                    ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                        "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Class, Exception, User, Group, StartMID, Num]),
                    {error, Exception}
            end
    end;
get_roam_mids_limited(User, Group, StartMID, Num) when Num < 0->
    case get_limited_condition(User, Group) of
        {error, Reason} ->
            {error, Reason};
        {ok, Condition} ->
            Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
                    <<" and mid > ">>, integer_to_binary(StartMID),
                    Condition,
                    <<" and is_del = 0 order by mid asc limit ">>, integer_to_binary(-Num), <<";">>],
            try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
                {selected, [<<"mid">>], ResList} ->
                    {ok, lists:reverse(reslist_to_mid_list(ResList))};
                {error, Reason} ->
                    ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Reason, User, Group, StartMID, Num]),
                    {error, Reason}
            catch
                Class:Exception ->
                    ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                        "User: ~p, Group:~p, StartMID:~p, Num:~p~n",
                        [Class, Exception, User, Group, StartMID, Num]),
                    {error, Exception}
            end
    end;
get_roam_mids_limited(_,_,_,_) ->
    {ok, []}.

get_limited_condition(User, Group) ->
    Query= [<<"select type, mid from message_history_event where uid = ">>, integer_to_binary(User),
            <<" and gid = ">>, integer_to_binary(Group),
            <<" order by mid desc">>, <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"type">>, <<"mid">>], EventList} ->
            case filter_enter_event(EventList, []) of
                [] ->
                    case repair_group_history_event(User, Group) of
                        {ok, AvailEventList} ->
                            {ok, event_list_to_condition(AvailEventList, <<>>)};
                        {error, _} ->
                            {error, <<"not found group event">>}
                    end;
                AvailEventList ->
                    {ok, event_list_to_condition(AvailEventList, <<>>)}
            end;
        {error, Reason} ->
            ?ERROR_MSG("read message_history_event error, Reason:~p, User: ~p, Group:~p~n",
                [Reason, User, Group]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history_event exception, Class:~p, Exception:~p, User: ~p, Group:~p~n",
                [Class, Exception, User, Group]),
            {error, Exception}
    end.

filter_enter_event([[<<"0">>, MID] | EventList], AvailEventList) ->
    filter_exit_event(EventList, [{<<"0">>, MID} | AvailEventList]);
filter_enter_event([], AvailEventList) ->
    AvailEventList;
filter_enter_event([_ | EventList], AvailEventList) ->
    filter_enter_event(EventList, AvailEventList).

filter_exit_event([[<<"1">>, MID] | EventList], AvailEventList) ->
    filter_enter_event(EventList, [{<<"1">>, MID} | AvailEventList]);
filter_exit_event([], AvailEventList) ->
    AvailEventList;
filter_exit_event([_ | EventList], AvailEventList) ->
    filter_exit_event(EventList, AvailEventList).

event_list_to_condition([{<<"0">>, MID} | AvailEventList], _Condition) ->
    event_list_to_condition(AvailEventList, <<" and (mid >= ", MID/binary >>);
event_list_to_condition([{<<"1">>, EndMID1}, {<<"1">>, _EndMID2}|AvailEventList], Condition) ->
    event_list_to_condition([{<<"1">>, EndMID1}|AvailEventList], Condition);
event_list_to_condition([{<<"1">>, EndMID}, {<<"0">>, _StartMID1}, {<<"0">>, StartMID2}|AvailEventList], Condition) ->
    event_list_to_condition([{<<"1">>, EndMID}, {<<"0">>, StartMID2}|AvailEventList], Condition);
event_list_to_condition([{<<"1">>, EndMID}, {<<"0">>, StartMID} | AvailEventList], Condition) ->
    event_list_to_condition(AvailEventList, << Condition/binary, " or (mid between ",
        StartMID/binary, " and ", EndMID/binary, ")">>);
event_list_to_condition([{<<"1">>, _MID}], Condition) ->
    event_list_to_condition([], Condition);
event_list_to_condition([], Condition) ->
    << Condition/binary, <<")">>/binary >>.

reslist_to_mid_list(L) ->
    lists:map(
      fun([MID]) ->
              binary_to_integer(MID)
      end, L).

repair_group_history_event(User, Group) ->
    case msgst_group:get_join_time(User, Group) of
        {error, Reason} ->
            {error, Reason};
        {ok, TimeMS} ->
            case read_group_mid_after_time(User, Group, TimeMS div 1000) of
                {ok, [MID]} ->
                    write_history_event(User, Group, 0, MID),
                    {ok, [{<<"0">>, integer_to_binary(MID)}]};
                {ok, []} ->
                    MID = xsync_proto:generate_msg_id(),
                    write_history_event(User, Group, 0, MID),
                    {ok, [{<<"0">>, integer_to_binary(MID)}]};
                _ ->
                    {error, fail_get_mid}
            end
    end.

read_group_mid_after_time(User, Group, Timestamp) ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(Group),
            <<" and is_del = 0">>,
            <<" and `timestamp` >= from_unixtime('">>, integer_to_binary(Timestamp),<<"')">>,
            <<" order by mid asc limit 1;">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, reslist_to_mid_list(ResList)};
        {error, Reason} ->
            ?ERROR_MSG("read message_history by time error, Reason:~p, User: ~p, Group:~p~n",
                [Reason, User, Group]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history by time  exception, Class:~p, Exception:~p,"
                "User: ~p, Group:~p~n",
                [Class, Exception, User, Group]),
            {error, Exception}
    end.

