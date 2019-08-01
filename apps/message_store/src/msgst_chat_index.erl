%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_chat_index.erl
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

-module(msgst_chat_index).

-export([
         write/4,
         get_unread_messages/4,
         ack_messages/4,
         sync_multi_device/4,
         write_history/3,
         delete_history/3,
         roam/4,
         unread_conversation_key/2,
         unread_midlist_key/3
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

%% write MID list
%% and will check len, if len is greater than ?REDIS_CHAT_MID_MAX, then will do trim
write(From, To, 0, MID) ->
    % write a new mid
    case msgst_device:get_avail_device_list(To) of
        {ok, DeviceList} ->
            AllQueries = lists:append(
                           [make_write_redis_query(From, To, Device, MID)
                            ||Device<-DeviceList]),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, AllQueries) of
                {error, Reason} ->
                    {error, Reason};
                ResList ->
                    %% check and do trim
                    spawn(fun()->maybe_ltrim_mid_list(From, To, DeviceList, ResList) end),
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end;
write(From, To, DeviceSN, MID) ->
    Device = msgst_device:get_avail_device(To, DeviceSN),
    Queries = make_write_redis_query(From, To, Device, MID),
    case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end.

maybe_ltrim_mid_list(From, To, [Device|DeviceList], [PushRes, _,_|ResList]) ->
    case PushRes of
        {ok, MidLenBin} ->
            MidLen = binary_to_integer(MidLenBin),
            case MidLen > ?REDIS_CHAT_MID_MAX of
                true ->
                    UnreadMIDListKey = unread_midlist_key(To, Device, From),
                    redis_pool:q(?REDIS_INDEX_SERVICE, ["LTRIM", UnreadMIDListKey, 0, ?REDIS_CHAT_MID_LIMIT]);
               false ->
                    skip
            end;
        _ ->
            skip
    end,
    maybe_ltrim_mid_list(From, To, DeviceList, ResList);
maybe_ltrim_mid_list(_From, _To, [], []) ->
    ok.

%% @doc
%% will return as many unread msgs as possible limited by ?SYNC_MSG_NUM_LIMIT
%% @end
get_unread_messages(User, DeviceSN, Conversation, _StartMID) ->
    Device = msgst_device:get_avail_device(User, DeviceSN),
    case get_mid_list(User, Device, Conversation) of
        {ok, []} ->
            {ok, {[], undefined}};
        {error, Reason} ->
            {error, Reason};
        {ok, MIDList} ->
            ReverseMIDList = lists:reverse(MIDList),
            LimitMIDList = lists:sublist(ReverseMIDList, ?SYNC_MSG_NUM_LIMIT),
            case msgst_body:read(LimitMIDList) of
                {ok, MBodyList} ->
                    AvailMBodyList = filter_body(MBodyList, []),
                    {ok, {AvailMBodyList, next_mid(LimitMIDList)}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ack_messages(User, DeviceSN, Conversation, StartMID) ->
    DefaultDevice = msgst_device:get_default_device(),
    Device = msgst_device:get_avail_device(User, DeviceSN),
    case Device of
        DefaultDevice ->
            ack_messages_1(User, Device, Conversation, StartMID);
        _ ->
            case ack_messages_1(User, Device, Conversation, StartMID) of
                {ok, Result} ->
                    spawn(fun() ->
                                  ack_messages_1(User, DefaultDevice, Conversation, StartMID)
                          end),
                    {ok, Result};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ack_messages_1(User, Device, Conversation, StartMID) ->
    case get_mid_list(User, Device, Conversation) of
        {ok, []} ->
            {ok, [StartMID]};
        {error, Reason} ->
            {error, Reason};
        {ok, MIDList} ->
            ReverseMIDList = lists:reverse(MIDList),
            case mids_to_be_acked(ReverseMIDList, StartMID) of
                [] ->
                    {ok, []};
                AckMIDs ->
                    Queries = make_ack_redis_query(User, Device, Conversation, AckMIDs),
                    case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
                        {error, Reason} ->
                            {error, Reason};
                        _ ->
                            {ok, AckMIDs}
                    end
            end
    end.

sync_multi_device(From, CurDevice, To, MID) ->
    case msgst_device:get_avail_device_list(From) of
        {ok, DeviceList} ->
            case lists:member(CurDevice, DeviceList) of
                true ->
                    OtherDeviceList = DeviceList -- [CurDevice, ?DEFAULT_DEVICE],
                    lists:foreach(fun(Device) -> write_multidevice(To, From, Device, MID) end, OtherDeviceList),
                    ok;
                false ->
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end.

write_multidevice(From, To, Device, MID) ->
    Queries = make_write_redis_query(From, To, Device, MID),
    case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end.

roam(User, Conversation, StartMID, Num) ->
    case get_roam_mids(User, Conversation, StartMID, Num) of
        {error, Reason} ->
            {error, Reason};
        {ok, []} ->
            {ok, {[], undefined}};
        {ok, MIDDescList} ->
            case msgst_body:read_odbc(MIDDescList) of
                {error, Reason} ->
                    {error, Reason};
                {ok, BodyList} ->
                    [NextMID | _] = MIDDescList,
                    {ok, {BodyList, NextMID}}
            end
    end.

%%****************************************************************************
%% internal functions
%%****************************************************************************

make_write_redis_query(From, To, Device, MID) ->
    % add to unread MID list
    UnreadMIDListKey = unread_midlist_key(To, Device, From),
    Query1 = ["LPUSH", UnreadMIDListKey, MID],
    % add unread num
    UnreadConversationKey = unread_conversation_key(To, Device),
    Query2 = ["HINCRBY", UnreadConversationKey, From, 1],
    Query3 = ["HINCRBY", UnreadConversationKey, ?TOTAL_KEY, 1],
    [Query1, Query2, Query3].

make_ack_redis_query(User, Device, Conversation, MIDList) ->
    UnreadMIDListKey = unread_midlist_key(User, Device, Conversation),
    Queries = lists:map(fun(MID) -> ["LREM", UnreadMIDListKey, 1, MID] end, MIDList),
    UnreadConversationKey = unread_conversation_key(User, Device),
    Num = 0 - erlang:length(MIDList),
    Query1 = ["HINCRBY", UnreadConversationKey, Conversation, Num],
    Query2 = ["HINCRBY", UnreadConversationKey, ?TOTAL_KEY, Num],
    [Query1 | [Query2 | Queries]].

unread_midlist_key(User, Device, CID) ->
    <<?UNREAD_MID_LIST_KEY_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(Device))/binary, ":", (integer_to_binary(CID))/binary>>.

unread_conversation_key(User, Device) ->
    <<?UNREAD_CONVERSATION_KEY_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(Device))/binary>>.

get_mid_list(User, Device, Conversation) ->
    Key = unread_midlist_key(User, Device, Conversation),
    Query = ["LRANGE", Key, 0, ?REDIS_LRANGE_LIMIT],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, MidBinList} ->
            {ok, lists:map(fun(MidBin) -> binary_to_integer(MidBin) end, MidBinList)};
        {error, Reason} ->
            {error, Reason}
    end.

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

message_history_write_odbc_enabled() ->
    application:get_env(message_store, enable_message_history_write_odbc, true).

write_history(From, To, MID) ->
    case message_history_write_odbc_enabled() of
        true ->
            {write_history_1(From, To, 0, MID),
             write_history_1(To, From, 1, MID)};
        false ->
            skip
    end.

write_history_1(From, To, Type, MID) ->
    Query= [<<"insert into message_history (uid, opposite, type, mid) values (">>,
            integer_to_binary(From), <<", ">>, integer_to_binary(To), <<", ">>,
            integer_to_binary(Type), <<", ">>, integer_to_binary(MID), <<");">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {updated, _} ->
            ok;
        {error, Reason} ->
            ?ERROR_MSG("write history error, Reason:~p, From: ~p, To:~p, Type:~p, MID:~p~n",
                       [Reason, From, To, Type, MID]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("write history exception, Class:~p, Exception:~p, From: ~p, To:~p, Type:~p, MID:~p~n",
                [Class, Exception, From, To, Type, MID]),
            {error, Exception}
    end.

delete_history(From, To, MID) ->
    case message_history_write_odbc_enabled() of
        true ->
            delete_history_1(From, To, MID);
        false ->
            skip
    end.

delete_history_1(From, To, MID) ->
    Query = [<<"update message_history set is_del=1">>,
            <<" where uid=">>,integer_to_binary(From),
             <<" and opposite=">>, integer_to_binary(To),
             <<" and mid=">>, integer_to_binary(MID)],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {updated, _} ->
            ok;
        {error, Reason} ->
            ?ERROR_MSG("delete message histroy fail: From=~p, To=~p, MID=~p, Reason=~p",
                       [From, To, MID, Reason]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("delete message histroy fail: From=~p, To=~p, MID=~p, Reason=~p",
                       [From, To, MID, {Class, {Exception, erlang:get_stacktrace()}}]),
            {error, {Class, Exception}}
    end.

next_mid([]) ->
    undefined;
next_mid(L) ->
    lists:last(L).

get_roam_mids(User, Conversation, 0, Num) when Num > 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(User),
            <<" and opposite = ">>, integer_to_binary(Conversation),
            <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, lists:reverse(reslist_to_mid_list(ResList))};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Conversation, 0, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Conversation, 0, Num]),
            {error, Exception}
    end;
get_roam_mids(User, Conversation, StartMID, Num) when Num > 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(User),
            <<" and opposite = ">>, integer_to_binary(Conversation),
            <<" and mid < ">>, integer_to_binary(StartMID),
            <<" and is_del = 0 order by mid desc limit ">>, integer_to_binary(Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, lists:reverse(reslist_to_mid_list(ResList))};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Conversation, StartMID, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Conversation, StartMID, Num]),
            {error, Exception}
    end;
get_roam_mids(User, Conversation, StartMID, Num) when Num < 0 ->
    Query= [<<"select mid from message_history where uid = ">>, integer_to_binary(User),
            <<" and opposite = ">>, integer_to_binary(Conversation),
            <<" and mid > ">>, integer_to_binary(StartMID),
            <<" and is_del = 0 order by mid asc limit ">>, integer_to_binary(-Num), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"mid">>], ResList} ->
            {ok, reslist_to_mid_list(ResList)};
        {error, Reason} ->
            ?ERROR_MSG("read message_history error, Reason:~p, User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Reason, User, Conversation, StartMID, Num]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read message_history exception, Class:~p, Exception:~p,"
                "User: ~p, Conversation:~p, StartMID:~p, Num:~p~n",
                [Class, Exception, User, Conversation, StartMID, Num]),
            {error, Exception}
    end;
get_roam_mids(_,_,_,_) ->
    {ok, []}.

reslist_to_mid_list(L) ->
    lists:map(
      fun([MID]) ->
              binary_to_integer(MID)
      end, L).
