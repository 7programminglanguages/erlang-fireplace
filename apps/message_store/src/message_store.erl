%%%-------------------------------------------------------------------------------------------------
%%% File    :  message_store.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :
%%% Created :  Nov 14 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(message_store).

-export([
         start/0,
         stop/0,

         get_unread_conversations/2,
         get_unread_messages/4,
         ack_messages/4,

         read/1,

         write_chat_body/2,
         write_chat_index/4,

         write_groupchat_body/2,
         write_groupchat_index/3,
         write_groupchat_sharelist/3,
         init_group_index/2,
         clean_group_index/2,

         set_cacheid/4,
         get_cacheid/3,

         recall_message/1,

         read_roam_message/4,

         sync_multi_device/4,

         incr_apns/2,
         get_apns/1,
         delete_apns/1,
         delete_user/1,

         add_history_body/2,
         delete_history_body/1,
         add_history_index/3,
         delete_history_index/3,
         add_history_event/4,

         adjust_offline/2
        ]).

-define(APP, ?MODULE).


%%****************************************************************************
%% API functions
%%****************************************************************************

%% @doc
%% start app
%% @end
start() ->
    {ok, _} = application:ensure_all_started(?APP).

%% @doc
%% stop app
%% @end
stop() ->
    application:stop(?APP).

%% @doc
%% 
%% @spec User: integer, 123456
%% @spec DeviceSN: integer, 3
%%
%% @return {ok, []} | {ok, [{Conversation, N}]} | {error, <<"balabala">>}
%%     Conversation: integer, 2666
%%     N: integer, means the number of unread msg of this Conversation, and maybe 0
%% @end
get_unread_conversations(User, DeviceSN) ->
    msgst_message_index:get_conversations(User, DeviceSN).

%% @doc
%% 
%% @spec User: integer, 123456
%% @spec DeviceSN: integer, 3
%% @spec Conversation: integer, 3644748, maybe chat, maybe groupchat
%% @spec StartMID: integer, 2345
%%
%% @return {ok, {[], undefined}} | {ok, {[MBody], NextMID} | {error, <<"balabala">>}
%%     MBody: binary
%%     NextMID: integer, means the MID according to the last one of [MsgBoby]
%% @end
get_unread_messages(User, DeviceSN, Conversation, StartMID) ->
    msgst_message_index:get_unread_messages(User, DeviceSN, Conversation, StartMID).

%% @doc
%% 
%% @spec User: integer, 123456
%% @spec DeviceSN: integer, 3
%% @spec Conversation: integer, 3644748, maybe chat, maybe groupchat
%% @spec StartMID: integer, 2345
%%
%% @return {ok, [MID]} | {error, <<"balabala">>}
%%     MID: integer
%% @end
ack_messages(User, DeviceSN, Conversation, StartMID) ->
    msgst_message_index:ack_messages(User, DeviceSN, Conversation, StartMID).

%% @doc
%% 
%% @spec MID: MID list | integer, 2345
%%
%% @return {ok, MBody} | {error, <<"balabala">>}
%%     MBody: binary
%% @end
read(MID) ->
    msgst_body:read(MID).

%% @doc
%% 
%% @spec MID: integer, 2345
%% @spec MBody: binary
%%
%% @return ok | {error, <<"balabala">>}
%% @end
write_chat_body(MID, MBody) ->
    msgst_body:write(MID, MBody).

%% @doc
%%
%% unread MID list and num
%%
%% @spec From: integer, userid, 1235
%% @spec To: integer, userid, 1235
%% @spec DeviceSN: integer | undefined
%% @spec MID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
write_chat_index(From, To, DeviceSN, MID) ->
    msgst_chat_index:write(From, To, DeviceSN, MID).

%% @doc
%% 
%% @spec MID: integer, 2345
%% @spec MBody: binary
%%
%% @return ok | {error, <<"balabala">>}
%% @end
write_groupchat_body(MID, MBody) ->
    msgst_body:write(MID, MBody).

%% @doc
%% 
%% unread num
%%
%% @spec User: integer, 1235, maybe user list
%% @spec Group: integer, 1235
%% @spec MID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
write_groupchat_index(User, Group, MID) ->
    msgst_groupchat_index:write(User, Group, MID).

%% @doc
%% 
%% unread MID list
%%
%% @spec From: integer, userid, 1235
%% @spec Group: integer, 1235
%% @spec MID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
write_groupchat_sharelist(From, Group, MID) ->
    msgst_groupchat_index:write_sharelist(From, Group, MID).

%% @doc
%%
%% @spec Group: integer, 1235
%% @spec User: integer, 1235
%%
%% @return ok | {error, <<"balabala">>}
%% @end
init_group_index(Group, User) ->
    msgst_groupchat_index:init(Group, User).

%% @doc
%%
%% @spec Group: integer, 1235
%% @spec User: integer, 1235
%%
%% @return ok | {error, <<"balabala">>}
%% @end
clean_group_index(Group, User) ->
    msgst_groupchat_index:clean(Group, User).

%% @doc
%% 
%% used to for returning client the same MID if client sending same msg
%%
%% @spec User: integer, 1235
%% @spec DeviceSN: integer, 5
%% @spec ClientMID: integer, 2345
%% @spec ServerMID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
set_cacheid(User, DeviceSN, ClientMID, ServerMID) ->
    msgst_idcache:set(User, DeviceSN, ClientMID, ServerMID).

%% @doc
%% 
%% used to for returning client the same MID if client sending same msg
%%
%% @spec User: integer, 1235
%% @spec DeviceSN: integer, 5
%% @spec ClientMID: integer, 2345
%%
%% @return {ok, ServerMID} | {error, <<"not found">>} | {error, <<"balabala">>}
%%     ServerMID: integer, 2345
%% @end
get_cacheid(User, DeviceSN, ClientMID) ->
    msgst_idcache:get(User, DeviceSN, ClientMID).

%% @doc
%%
%% @spec User: integer, userid, 1235
%% @spec Conversation: integer, userid, 1235
%% @spec StartMID: integer, 2345
%% @spec EndMID: integer, 2345
%%
%% @return {ok, {[MBody], NextMID}} | {error, <<"balabala">>}
%%     MBody: binary
%%     NextMID: integer, 2345
%% @end
read_roam_message(User, Conversation, StartMID, Num) ->
    msgst_message_index:roam(User, Conversation, StartMID, Num).

%% @doc
%%
%% @spec MID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
recall_message(MID) ->
    msgst_recall:recall(MID).

%% @doc
%%
%% @spec From: integer, userid, 1235
%% @spec CurDeviceSN: integer, 3
%% @spec To: integer, userid, 1235
%% @spec MID: integer, 2345
%%
%% @return ok | {error, <<"balabala">>}
%% @end
sync_multi_device(From, CurDeviceSN, To, MID) ->
    msgst_message_index:sync_multi_device(From, CurDeviceSN, To, MID).

%% @doc
%%
%% @spec User: integer, 1235
%%
%% @return ok | {error, <<"balabala">>}
%% @end
delete_user(User) ->
    % delete all devices
    DeviceList = msgst_device:get_user_all_devices(User),
    msgst_device:remove_user_device(User, DeviceList),
    % delete offline, including conversations and mids / cursors
    msgst_message_index:remove_offline(User, DeviceList),
    % delete apns
    delete_apns(User),
    ok.

%% @doc
%%
%% @spec User: integer, 1235
%% @spec Num: integer, 1
%%
%% @return ok | {error, <<"balabala">>}
%% @end
incr_apns(UserList, Num) ->
    msgst_apns:incr(UserList, Num).

%% @doc
%%
%% @spec User: integer, 1235
%% @spec Num: integer, 1
%%
%% @return ok | {error, <<"balabala">>}
%% @end
delete_apns(User) ->
    msgst_apns:delete(User).

-spec get_apns(User::integer()) ->
                      {ok, ApnsNum::integer()} | {error, binary()}.
get_apns(User) ->
    msgst_apns:get(User).


add_history_body(MID, Body) ->
    msgst_body:write_odbc(MID, Body).

delete_history_body(MID) ->
    msgst_body:delete_odbc(MID).

add_history_index(From, To, MID) ->
    msgst_message_index:add_history_index(From, To, MID).

delete_history_index(User, CID, MID) ->
    msgst_message_index:delete_history_index(User, CID, MID).

add_history_event(User, Group, Type, MID) ->
    msgst_groupchat_index:write_history_event(User, Group, Type, MID).

%% @doc
%% 
%% adjust the offline msg number for each conversation
%%
%% @spec User: integer, 1235
%% @spec DeviceSN: integer, 5
%%
%% @return ok | {error, <<"balabala">>}
%% @end
adjust_offline(User, DeviceSN) ->
    msgst_message_index:adjust_offline(User, DeviceSN).


