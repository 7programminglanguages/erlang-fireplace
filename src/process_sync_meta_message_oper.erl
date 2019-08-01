%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta_message_oper.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  26 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_sync_meta_message_oper).

-export([handle/1]).
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").

handle(#'Meta'{payload = #'MessageBody'{operation = undefined}}) ->
    {error, {'INVALID_PARAMETER', <<"no message op">>}};
handle(#'Meta'{from = From,
               to = To,
               payload =
                   #'MessageBody'{operation =
                                      #'MessageOperation'{
                                         type = 'RECALL',
                                         mid = RelatedMID
                                        }}} = Meta) ->
    case check_recall_msg(From, To, RelatedMID) of
        {error, {Code, Reason}} ->
            {error, {Code, Reason}};
        ok ->
            case message_store:recall_message(RelatedMID) of
                {error, Reason} ->
                    {error, {'FAIL', Reason}};
                ok ->
                    case misc:is_user(To#'XID'.uid) of
                        true ->
                            process_sync_meta_message_chat:handle(Meta);
                        false ->
                            case misc:is_group(To#'XID'.uid) of
                                true ->
                                    process_sync_meta_message_groupchat:handle(Meta);
                                false ->
                                    {error, {'FAIL', <<"bad recall to">>}}
                            end
                    end
            end
    end;
%% READ_ALL,READ_CANCEL message only send multi_devices, do not send to Meta's To
handle(#'Meta'{payload =
                   #'MessageBody'{operation =
                                      #'MessageOperation'{
                                         type = OpType
                                        }}} = Meta) when OpType == 'READ_ALL';
                                                  OpType == 'READ_CANCEL'->
    xsync_router:save(Meta);
handle(#'Meta'{payload =
                   #'MessageBody'{operation =
                                      #'MessageOperation'{
                                         type = 'DELIVER_ACK'
                                        }}} = Meta) ->
    case application:get_env(xsync, enable_deliver_ack, false) of
        true ->
            process_sync_meta_message_chat:handle(Meta),
            ignore_multidevice;
        false ->
            ignore_multidevice
    end;
handle(#'Meta'{from = From,
               to = To,
               payload =
                   #'MessageBody'{operation =
                                      #'MessageOperation'{
                                         type = 'DELETE',
                                         mid = MID
                                        }}} = Meta) ->
    case check_delete(From, To, MID) of
        {error, {Code, Reason}} ->
            {error, {Code, Reason}};
        ignore ->
            ok;
        {ok, UserId, OppoId} ->
            case msgst_history:delete_index(UserId, OppoId, MID) of
                ok ->
                    xsync_router:save(Meta);
                {error, _} ->
                    {error, {'FAIL', <<"db error">>}}
            end
    end;
handle(Meta) ->
    process_sync_meta_message_chat:handle(Meta).

check_recall_msg(From, To, RelatedMID) ->
    case message_store:read(RelatedMID) of
        {error, <<"not found">>} ->
            {error, {'FAIL', <<"not found">>}};
        {error, _Reason} ->
            {error, {'FAIL', <<"db error">>}};
        {ok, Body} ->
            #'Meta'{timestamp = Timestamp,
                    from = MetaFrom,
                    to = MetaTo} =  xsync_proto:decode_meta(Body),
            case From#'XID'.uid /= MetaFrom#'XID'.uid of
                true ->
                    {error, {'FAIL', <<"bad recall from">>}};
                false ->
                    case To#'XID'.uid /= MetaTo#'XID'.uid of
                        true ->
                            {error, {'FAIL', <<"bad recall to">>}};
                        false ->
                            Now = erlang:system_time(milli_seconds),
                            RecallTimeLimit = application:get_env(xsync, message_recall_time_limit, 120000),
                            case Now - Timestamp > RecallTimeLimit of
                                true ->
                                    {error, {'FAIL', <<"exceed recall time limit">>}};
                                false ->
                                    ok
                            end
                    end
            end
    end.

check_delete(From, _To, MID) ->
    case message_store:read(MID) of
        {error, <<"not found">>} ->
            %% maybe QoS AT_MOST_ONCE, which do not save messagebody
            ignore;
        {error, Reason} ->
            {error, Reason};
        {ok, Body} ->
            UserId = From#'XID'.uid,
            try xsync_proto:decode_meta(Body) of
                #'Meta'{to = #'XID'{uid = OppoId},
                        ns='MESSAGE',
                        payload = #'MessageBody'{
                                     type = 'GROUPCHAT'
                                    }} ->
                    {ok, UserId, OppoId};
                #'Meta'{from = #'XID'{uid = UserId},
                        to = #'XID'{uid = OppoId},
                        ns='MESSAGE',
                        payload = #'MessageBody'{
                                    }} ->
                    {ok, UserId, OppoId};
                #'Meta'{from = #'XID'{uid = OppoId},
                        to = #'XID'{uid = UserId},
                        ns='MESSAGE',
                        payload = #'MessageBody'{
                                    }} ->
                    {ok, UserId, OppoId};
                #'Meta'{} ->
                    {error, {'FAIL', <<"message cannot be delete">>}}

            catch
                _:_ ->
                    {error, {'FAIL', <<"message not exist">>}}
            end
    end.
