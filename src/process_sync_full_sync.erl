%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_full_sync.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  27 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_sync_full_sync).

-export([handle/5]).
-include("xsync_pb.hrl").
-include("logger.hrl").

handle(_, undefined, Response, _Num, _XID) ->
    Response;
handle(Key, CID, Response, Num, XID) ->
    NewResponse = handle_full_sync(Key, CID, Response, Num, XID),
    xsync_metrics:inc_response(client_recv_msg_history, NewResponse),
    NewResponse.

handle_full_sync(Key, CID, Response, Num, XID) ->
    NewCID = normalize_conversation_id(CID),
    Conversation = NewCID#'XID'.uid,
    UserId = XID#'XID'.uid,
    MaxLen = application:get_env(xsync, message_history_max_query_len, 200),
    QueryNum = case Num >= 0 of
                   true ->
                       min(Num, MaxLen);
                   false ->
                       max(Num, -MaxLen)
               end,
    case message_store:read_roam_message(UserId, Conversation, Key, QueryNum) of
        {error, Reason} ->
            ReasonDesc = misc:normalize_reason(Reason),
            xsync_proto:set_status(Response, 'FAIL', ReasonDesc);
        {ok, {Bodys, NextMID}} ->
            Metas = decode_metas(Bodys, XID),
            xsync_proto:set_unread_messages(Response, Metas, NewCID, NextMID)
    end.

decode_metas(Bodys, XID) ->
    lists:filtermap(
      fun(Body) ->
              try xsync_proto:decode_meta(Body) of
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
