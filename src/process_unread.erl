%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_unread.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  9 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_unread).

-export([handle/3]).
-include("xsync_pb.hrl").

handle(#'UnreadUL'{}, Response, #{xid:=#'XID'{uid=UserId, deviceSN=DeviceSN}}=State) ->
    case maps:take(is_first_unread, State) of
        {IsFirstUnread, NewState} ->
            ok;
        error ->
            IsFirstUnread = false,
            NewState = State
    end,
    NewResponse = handle_unread(Response, UserId, DeviceSN, IsFirstUnread),
    xsync_metrics:inc_response(client_get_unread, NewResponse),
    {NewResponse, NewState}.

handle_unread(Response, UserId, DeviceSN, IsFirstUnread) ->
    case get_unread_conversations(UserId, DeviceSN, IsFirstUnread) of
        [] -> % no unread
            Response;
        UnreadConversations ->
            xsync_proto:set_unread_conversations(Response, UnreadConversations)
    end.

get_unread_conversations(UserId, DeviceSN, true) ->
    case message_store:get_unread_conversations(UserId, DeviceSN) of
        {ok, UnreadConvs} ->
            lists:filtermap(
              fun({UID, Num}) ->
                      case Num >= 0 of
                          true ->
                              {true, {#'XID'{uid = UID}, Num}};
                          false ->
                              false
                      end
              end, UnreadConvs);
        {error, _Reason} ->
            []
    end;
get_unread_conversations(UserId, DeviceSN, false) ->
    case message_store:get_unread_conversations(UserId, DeviceSN) of
        {ok, UnreadConvs} ->
            lists:filtermap(
              fun({UID, Num}) ->
                      case  Num > 0 of
                          true ->
                              {true, {#'XID'{uid=UID}, Num}};
                          false ->
                              false
                      end
              end, UnreadConvs);
        {error, _Reason} ->
            []
    end.
