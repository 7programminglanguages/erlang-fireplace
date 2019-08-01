%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta.erl
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
-module(process_sync_meta).

-include("xsync_pb.hrl").
-export([handle/3]).

handle(undefined, Response, _XID) ->
    Response;
handle(Meta, Response, XID) ->
    NewResponse = handle_1(Meta, Response, XID),
    xsync_metrics:inc_response(client_send_msg, NewResponse),
    NewResponse.

handle_1(#'Meta'{
          id = 0
         }, Response, _XID) ->
    xsync_proto:set_status(Response, 'INVALID_PARAMETER', <<"no meta id">>);
handle_1(#'Meta'{
          id = ClientMID,
          from = From,
          to = To,
          ns = NS
         } = Meta, Response, XID) ->
    case check_sync_meta(From, XID, ClientMID) of
        {error, {Code, Reason}} ->
            stream:apply(Response,
                        [{xsync_proto, set_status, [Code, Reason]},
                         {xsync_proto, set_sync_ack_id, [ClientMID, undefined]}]);
        {ok, NewFrom} ->
            NewTo = normalize_meta_to(To),
            NewMeta =
                stream:apply(Meta,
                            [{xsync_proto, generate_meta_id, []},
                             {xsync_proto, generate_meta_timestamp, []},
                             {xsync_proto, set_meta_from, [NewFrom]},
                             {xsync_proto, set_meta_to, [NewTo]}]),
            ServerMID = xsync_proto:get_meta_id(NewMeta),
            NewResponse = xsync_proto:set_sync_ack_id(Response, ClientMID, ServerMID),
            case handle_ns(NewMeta, NS, XID) of
                {error, {Code, Reason}} ->
                    xsync_proto:set_status(NewResponse, Code, Reason);
                ok ->
                    message_store:set_cacheid(XID#'XID'.uid, XID#'XID'.deviceSN,
                                                           ClientMID, ServerMID),
                    NewResponse
            end
    end.

handle_ns(Meta, NS, XID) ->
    case NS of
        'INFO' ->
            process_sync_meta_info:handle(Meta, XID);
        'MESSAGE' ->
            process_sync_meta_message:handle(Meta);
        _ ->
            {error, {'INVALID_PARAMETER', <<"bad meta namespace">>}}
    end.

normalize_meta_from(#'XID'{uid = UID1}, #'XID'{uid = UID2})
                when UID1 /= 0 andalso UID1 /= UID2 ->
    {error, {'INVALID_PARAMETER', <<"bad meta from uid">>}};
normalize_meta_from(#'XID'{deviceSN = DeviceSN1}, #'XID'{deviceSN = DeviceSN2})
  when DeviceSN1 /= 0 andalso DeviceSN1 /= DeviceSN2 ->
    {error, {'INVALID_PARAMETER', <<"bad meta from deviceSN">>}};
normalize_meta_from(_,XID) ->
    XID.

normalize_meta_to(undefined) ->
    #'XID'{};
normalize_meta_to(#'XID'{uid = 0} = XID) ->
    XID#'XID'{deviceSN = 0};
normalize_meta_to(XID) ->
    XID.

check_sync_meta(From, XID, ClientMID) ->
    case normalize_meta_from(From, XID) of
        {error, Reason} ->
            {error, Reason};
        NewFrom ->
            case check_meta_id_unique(NewFrom, ClientMID) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    {ok, NewFrom}
            end
    end.

check_meta_id_unique(From, ClientMID) ->
    case message_store:get_cacheid(From#'XID'.uid, From#'XID'.deviceSN, ClientMID) of
        {ok, MsgId} when is_integer(MsgId) ->
            {error, {'OK', <<"client msg id duplicated">>}};
        {error, _} ->
            ok
    end.
