%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_message_index.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :  this file mainly is an entrance for chat or groupchat
%%% Created :  14 Nov 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(msgst_message_index).

-export([
         get_conversations/2,
         get_unread_messages/4,
         ack_messages/4,
         clone_offline/3,
         remove_offline/2,
         adjust_offline/2,
         sync_multi_device/4,
         add_history_index/3,
         delete_history_index/3,
         roam/4
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

get_conversations(User, DeviceSN) ->
    Device = msgst_device:get_avail_device(User, DeviceSN),
    Key = unread_conversation_key(User, Device),
    Query = ["HGETALL", Key],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, ConversationList} ->
            {ok, conversation_filter(ConversationList, [])};
        {error, Reason} ->
            {error, Reason}
    end.

get_unread_messages(User, Device, Conversation, StartMID) ->
    case chat_type(Conversation) of
        ?CHAT ->
            msgst_chat_index:get_unread_messages(User, Device, Conversation, StartMID);
        ?GROUP_CHAT ->
            msgst_groupchat_index:get_unread_messages(User, Device, Conversation, StartMID)
    end.

ack_messages(User, Device, Conversation, StartMID) ->
    case chat_type(Conversation) of
        ?CHAT ->
            msgst_chat_index:ack_messages(User, Device, Conversation, StartMID);
        ?GROUP_CHAT ->
            msgst_groupchat_index:ack_messages(User, Device, Conversation, StartMID)
    end.

clone_offline(User, FromDevice, ToDevice) ->
    Key = unread_conversation_key(User, FromDevice),
    Query = ["HGETALL", Key],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, []} ->
            ok;
        {ok, ConversationList} ->
            % clone all conversation
            clone_conversation(User, ToDevice, ConversationList),

            {ChatConvList, GroupchatConvList} = lists:partition(
                fun({Conv, _}) ->
                    chat_type(Conv) =:= ?CHAT
                end, conversation_filter(ConversationList, [])),
            % for chat, clone mid list
            ChatList = lists:map(fun({Conv, _}) -> Conv end, ChatConvList),
            clone_mid_list(User, FromDevice, ToDevice, ChatList),
            % for groupchat, clone cursor
            GroupchatList = lists:map(fun({Conv, _}) -> Conv end, GroupchatConvList),
            clone_cursor(User, FromDevice, ToDevice, GroupchatList),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

remove_offline(_User, []) ->
    ok;
remove_offline(User, DeviceList) when is_list(DeviceList) ->
    lists:foreach(fun(Device) -> remove_offline(User, Device) end, DeviceList);
remove_offline(User, Device) ->
    Key = unread_conversation_key(User, Device),
    Query = ["HGETALL", Key],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {ok, []} ->
            ok;
        {ok, ConversationList} ->
            % delete all conversation
            Query1 = ["DEL", Key],
            % for groupchat, delete cursor
            Query2 = ["DEL", cursor_key(User, Device)],
            % for chat, delete mid list
            ChatList = lists:filter(
                fun({Conv, _}) ->
                    chat_type(Conv) =:= ?CHAT
                end, conversation_filter(ConversationList, [])),
            Queries = lists:map( fun({Conv, _}) -> ["DEL", unread_midlist_key(User, Device, Conv)] end, ChatList),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, [Query1 | [Query2 | Queries]]) of
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    ok
            end;
        {error, Reason} ->
            {error, Reason}
    end.

adjust_offline(User, DeviceSN) ->
    case application:get_env(message_store, enable_adjust_offline, true) of
        true ->
            adjust_offline_1(User, DeviceSN);
        false ->
            ok
    end.

adjust_offline_1(User, DeviceSN) ->
    Device = msgst_device:get_avail_device(User, DeviceSN),
    case get_conversations(User, Device) of
        {error, Reason} ->
            {error, Reason};
        {ok, Convers} ->
            Queries = lists:map(
                        fun({Conver, _Num}) ->
                                case chat_type(Conver) of
                                    ?CHAT -> ["LLEN", unread_midlist_key(User, Device, Conver)];
                                    ?GROUP_CHAT -> ["HGET", cursor_key(User, Device), Conver]
                                end
                        end, Convers),
            case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries) of
                {error, Reason} ->
                    {error, Reason};
                ResList ->
                    Queries2 = make_adjust_queries(User, Device, Convers, ResList),
                    case redis_pool:qp(?REDIS_INDEX_SERVICE, Queries2) of
                        {error, Reason} ->
                            {error, Reason};
                        [] ->
                            ok;
                        _ ->
                            maybe_adjust_default_device_offline(User, Device),
                            ok
                    end
            end
    end.

maybe_adjust_default_device_offline(User, Device) ->
    DefaultDevice = msgst_device:get_default_device(),
    Device /= DefaultDevice andalso adjust_offline_1(User, DefaultDevice).



sync_multi_device(From, CurDevice, To, MID) ->
    case chat_type(To) of
        ?CHAT ->
            msgst_chat_index:sync_multi_device(From, CurDevice, To, MID);
        ?GROUP_CHAT ->
            msgst_groupchat_index:sync_multi_device(From, CurDevice, To, MID)
    end.

roam(User, Conversation, StartMID, Num) when Num > ?MYSQL_ROAM_LIMIT ->
    roam(User, Conversation, StartMID, ?MYSQL_ROAM_LIMIT);
roam(User, Conversation, StartMID, Num) ->
    case chat_type(Conversation) of
        ?CHAT ->
            msgst_chat_index:roam(User, Conversation, StartMID, Num);
        ?GROUP_CHAT ->
            msgst_groupchat_index:roam(User, Conversation, StartMID, Num)
    end.


add_history_index(User, CID, MID) ->
    case chat_type(CID) of
        ?CHAT ->
            msgst_chat_index:write_history(User, CID, MID);
        ?GROUP_CHAT ->
            msgst_groupchat_index:write_history(User, CID, MID)
    end.

delete_history_index(User, CID, MID) ->
    case chat_type(CID) of
        ?CHAT ->
            msgst_chat_index:delete_history(User, CID, MID);
        ?GROUP_CHAT ->
            msgst_groupchat_index:write_history_event(User, CID, 2, MID)
    end.

%%****************************************************************************
%% internal functions
%%****************************************************************************

unread_conversation_key(User, Device) ->
    msgst_chat_index:unread_conversation_key(User, Device).

unread_midlist_key(User, Device, CID) ->
    msgst_chat_index:unread_midlist_key(User, Device, CID).

share_list_key(Group) ->
    <<?UNREAD_SHARE_LIST_KEY_PREFIX/binary, (integer_to_binary(Group))/binary>>.

cursor_key(User, Device) ->
    <<?UNREAD_CURSOR_KEY_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(Device))/binary>>.

conversation_filter([?TOTAL_KEY, _Num | ConversationList], ResList) ->
    conversation_filter(ConversationList, ResList);
conversation_filter([Queue, Num | ConversationList], ResList) ->
    conversation_filter(ConversationList, [{binary_to_integer(Queue), erlang:binary_to_integer(Num)} | ResList]);
conversation_filter([], ResList) ->
    ResList.

chat_type(Conversation) ->
    misc:chat_type(Conversation).

clone_conversation(User, ToDevice, ConversationList) ->
    ToKey = unread_conversation_key(User, ToDevice),
    Query = ["HMSET"| [ToKey | ConversationList]],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end.

clone_cursor(_,_,_,[]) ->
    ok;
clone_cursor(User, FromDevice, ToDevice, GroupchatList) ->
    Query1 = ["HMGET" | [cursor_key(User, FromDevice) | GroupchatList]],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query1) of
        {error, Reason} ->
            {error, Reason};
        {ok,ResList} ->
            ResKVList = lists:append([[K,V]||{K,V}<-lists:zip(GroupchatList, ResList), V /= undefined]),
            case ResKVList of
                [] ->
                    ok;
                _ ->
                    Query2 = ["HMSET" | [cursor_key(User, ToDevice) | ResKVList]],
                    case redis_pool:q(?REDIS_INDEX_SERVICE, Query2) of
                        {error, Reason} ->
                            {error, Reason};
                        _ ->
                            ok
                    end
            end
    end.

clone_mid_list(User, FromDevice, ToDevice, [Chat | ChatList]) ->
    Query1 = ["LRANGE", unread_midlist_key(User, FromDevice, Chat), 0, ?REDIS_LRANGE_LIMIT],
    case redis_pool:q(?REDIS_INDEX_SERVICE, Query1) of
        {error, Reason} ->
            {error, Reason};
        {ok, []} ->
            ok;
        {ok, MIDList} ->
            Query2 = ["RPUSH" | [unread_midlist_key(User, ToDevice, Chat) | MIDList]],
            case redis_pool:q(?REDIS_INDEX_SERVICE, Query2) of
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    ok
            end
    end,
    clone_mid_list(User, FromDevice, ToDevice, ChatList);
clone_mid_list(_User, _FromDevice, _ToDevice, []) ->
    ok.

make_adjust_queries(User, Device, Convers, ResList) ->
    Lens = lists:map(
        fun({{_Conver, Num}, {error, _Reason}}) ->
            Num;
        ({{Conver, Num}, {ok, LenOrCursor}}) ->
            case chat_type(Conver) of
                ?CHAT ->
                    binary_to_integer(LenOrCursor);
                ?GROUP_CHAT when LenOrCursor == undefined ->
                    0;
                ?GROUP_CHAT ->
                    case redis_pool:q(?REDIS_INDEX_SERVICE, ["LRANGE", share_list_key(Conver), 0, -1]) of
                        {error, _Reason} ->
                            Num;
                        {ok, MIDBinList} ->
                            MIDBinLeft = lists:takewhile(fun(M) -> M /= LenOrCursor end, MIDBinList),
                            erlang:length(MIDBinLeft)
                    end
            end
        end, lists:zip(Convers, ResList)),
    Queries = make_adjust_conver_query(User, Device, Convers, Lens, []),
    % total
    case redis_pool:q(?REDIS_INDEX_SERVICE, ["HGET", unread_conversation_key(User, Device), ?TOTAL_KEY]) of
        {error, _Reason} ->
            Queries;
        {ok, undefined} ->
            Queries;
        {ok, TotalBin} ->
            Total = binary_to_integer(TotalBin),
            TotalDiff = lists:sum(Lens) - Total,
            case TotalDiff =/= 0 of
                true ->
                    TotalQuery = ["HINCRBY", unread_conversation_key(User, Device), ?TOTAL_KEY, TotalDiff],
                    [TotalQuery | Queries];
                false ->
                    Queries
            end
    end.

make_adjust_conver_query(User, Device, [{Conver, Num} | Convers], [Len | Lens], Queries) when Num =/= Len ->
    Query = ["HINCRBY", unread_conversation_key(User, Device), Conver, Len - Num],
    ?INFO_MSG("repair user conversation unread: User=~p, Device=~p, CID=~p, Old=~p, New=~p, Incr = ~p",
              [User, Device, Conver, Num, Len, Len-Num]),
    msgst_metrics:add_event(adjust_offline, 1),
    make_adjust_conver_query(User, Device, Convers, Lens, [Query | Queries]);
make_adjust_conver_query(User, Device, [{_Conver, _Num} | Convers], [_Len | Lens], Queries) ->
    make_adjust_conver_query(User, Device, Convers, Lens, Queries);
make_adjust_conver_query(_User, _Device, [], _, Queries) ->
    Queries.
