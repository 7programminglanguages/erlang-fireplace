%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta_message.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  10 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_sync_meta_message).
-export([handle/1]).
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").

handle(#'Meta'{
         to = #'XID'{uid = 0}}) ->
    {error, {'INVALID_PARAMETER', <<"no meta to">>}};
handle(#'Meta'{
         payload = #'MessageBody'{
                      type = ChatType
                     }} = Meta0) ->
    Meta = normalize_meta(Meta0),
    case check_user_send_msg(Meta) of
        ok ->
            handle_chat_type(Meta, ChatType);
        {ok, NewMeta} ->
            handle_chat_type(NewMeta, ChatType);
        {error, {Code, Reason}} ->
            {error, {Code, Reason}}
    end;
handle(_) ->
    {error,{'INVALID_PARAMETER', <<"bad meta payload">>}}.

handle_chat_type(Meta, ChatType) ->
    Res = case ChatType of
              'GROUPCHAT' ->
                  process_sync_meta_message_groupchat:handle(Meta);
              'OPER' ->
                  process_sync_meta_message_oper:handle(Meta);
              undefined ->
                  {error, {'INVALID_PARAMETER', <<"bad meta payload's type">>}};
              _ ->
                  process_sync_meta_message_chat:handle(Meta)
          end,
    case Res of
        ok ->
            spawn(fun() ->
                          sync_multi_devices(Meta)
                  end),
            ok;
        ignore_multidevice ->
            ok;
        _ ->
            Res
    end.

check_user_send_msg(Meta) ->
    plugin_antispam_wangyidun:check_meta(Meta).

sync_multi_devices(#'Meta'{id = MsgId,
                           from = From,
                           to = To} = Meta) ->
    UserId = From#'XID'.uid,
    DeviceSN = From#'XID'.deviceSN,
    CID = To#'XID'.uid,
    message_store:sync_multi_device(UserId, DeviceSN, CID, MsgId),
    case msgst_session:get_sessions(UserId) of
        {error, _} ->
            skip;
        {ok, Sessions} ->
            OtherSessions = lists:keydelete(DeviceSN, 1, Sessions),
            xsync_router:notify_receivers_by_notice(To, From, Meta, OtherSessions)
    end.

normalize_meta(#'Meta'{from = From,
                       to = To,
                       payload = Payload}=Meta) ->
    Meta#'Meta'{
      payload = Payload#'MessageBody'{
                  from = From,
                  to = To
                 }
     }.
