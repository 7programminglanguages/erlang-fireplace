%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_conversation.erl
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
-module(process_sync_conversation).

-export([handle/4]).
-include("xsync_pb.hrl").
-include("logger.hrl").

handle(_, undefined, Response, _XID) ->
    Response;
handle(Key, CID, Response, XID) ->
    NewResponse = handle_sync_conversation(Key, CID, Response, XID),
    xsync_metrics:inc_response(client_recv_msg, NewResponse),
    NewResponse.

handle_sync_conversation(Key, CID, Response, XID) ->
    NewCID = normalize_conversation_id(CID),
    Conversation = NewCID#'XID'.uid,
    UserId = XID#'XID'.uid,
    DeviceSN = XID#'XID'.deviceSN,
    {ok, AckMsgIds} = ack_messages(UserId, DeviceSN, Conversation, Key),
    user_messages_ack(CID, XID, AckMsgIds),
    case message_store:get_unread_messages(UserId, DeviceSN, Conversation, Key) of
        {error, Reason} ->
            ReasonDesc = misc:normalize_reason(Reason),
            xsync_proto:set_status(Response, 'FAIL', ReasonDesc);
        {ok, {Bodys, NextMID}} ->
            Metas = decode_metas(Bodys, XID),
            user_messages_down(CID, XID, Metas),
            maybe_repair_unread(XID, CID, AckMsgIds, Bodys),
            xsync_proto:set_unread_messages(Response, Metas, NewCID, NextMID)
    end.

ack_messages(_UserId, _DeviceSN, _Conversation, 0) ->
    {ok, []};
ack_messages(UserId, DeviceSN, Conversation, Key) ->
    case message_store:ack_messages(UserId, DeviceSN, Conversation, Key) of
        {ok, AckMsgIds} ->
            {ok, AckMsgIds};
        {error, _Reason} ->
            {ok, []}
    end.

decode_metas(Bodys, XID) ->
    lists:filtermap(
      fun(Body) ->
              try xsync_proto:decode_meta(Body) of
                  #'Meta'{ from = XID} ->
                      false;
                  #'Meta'{} = Meta ->
                      {true, Meta}
              catch
                  C:E ->
                      ?ERROR_MSG("fail to decode message:XID=~p, Body=~p, Error=~p",
                                 [XID, Body, {C, {E, erlang:get_stacktrace()}}]),
                      false
              end
      end, Bodys).

normalize_conversation_id(#'XID'{} = CID) ->
    CID#'XID'{deviceSN = 0}.

user_messages_ack(From, To, MsgIds) ->
    spawn(fun() ->
                  lists:foreach(
                    fun(MsgId) ->
                            kafka_log:log_message_ack(From, To, MsgId)
                    end, MsgIds)
          end),
    case misc:is_user(From#'XID'.uid) of
        true ->
            xsync_metrics:inc(message_ack, [chat], length(MsgIds));
        false ->
            xsync_metrics:inc(message_ack, [group], length(MsgIds))
    end,
    ok.

user_messages_down(From, To, Metas) ->
    spawn(fun() ->
                  lists:foreach(
                    fun(Meta) ->
                            kafka_log:log_message_down(From, To, Meta)
                    end, Metas)
          end),
    case misc:is_user(From#'XID'.uid) of
        true ->
            xsync_metrics:inc(message_down, [chat], length(Metas));
        false ->
            xsync_metrics:inc(message_down, [group], length(Metas))
    end,
    ok.

maybe_repair_unread(_XID, _CID, [], []) ->
    %%@TODO: do repair
    repair;
maybe_repair_unread(_XID, _CID, _AckMsgIds, _Bodys) ->
    skip.
