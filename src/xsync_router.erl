%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_router.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  17 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_router).

-export([route/1,
         notify_receivers_by_notice/4,
         notify_receivers_by_push_metas/3,
         notify_receivers_by_push_metas/4,
         save/1]).
-include("logger.hrl").
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").
-include("rosternotice_pb.hrl").
-include("groupnotice_pb.hrl").

route(Meta) ->
    ?DEBUG("route: meta=~p", [xsync_proto:pr(Meta)]),
    try do_route(Meta) of
        ok ->
            ok;
        {error, Reason} ->
            ?INFO_MSG("fail to route: Meta=~p, Reason=~p", [xsync_proto:pr(Meta), Reason]),
            {error, Reason}
    catch
        C:E ->
            ?ERROR_MSG("fail to route: Meta=~p, Error=~p",
                       [xsync_proto:pr(Meta), {C,{E,erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

do_route(Meta) ->
    case Meta of
        #'Meta'{ns = 'MESSAGE', payload = #'MessageBody'{qos = QoS}} ->
            do_route(Meta, QoS);
        _ ->
            do_route(Meta, 'AT_LEAST_ONCE')
    end.

do_route(Meta, 'AT_LEAST_ONCE') ->
    From = xsync_proto:get_meta_from(Meta),
    To = xsync_proto:get_meta_to(Meta),
    MsgId = xsync_proto:get_meta_id(Meta),
    MsgBody = xsync_proto:encode_meta(Meta),
    kafka_log:log_message_up(From, To, Meta),
    case From#'XID'.uid of
        0 ->
            xsync_metrics:inc(message_up, [system], 1);
        _ ->
            xsync_metrics:inc(message_up, [chat], 1)
    end,
    case message_store:write_chat_body(MsgId, MsgBody) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            case message_store:write_chat_index(From#'XID'.uid, To#'XID'.uid, To#'XID'.deviceSN, MsgId) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    notify_receivers(From, To, Meta),
                    maybe_write_history(From, To, Meta),
                    ok
            end
    end;
do_route(Meta, 'AT_MOST_ONCE') ->
    From = xsync_proto:get_meta_from(Meta),
    To = xsync_proto:get_meta_to(Meta),
    kafka_log:log_message_up(From, To, Meta),
    case From#'XID'.uid of
        0 ->
            xsync_metrics:inc(message_up, [system_QoS0], 1);
        _ ->
            xsync_metrics:inc(message_up, [chat_QoS0], 1)
    end,
    notify_receivers_by_push_metas(From, To, [Meta]),
    ok;
do_route(Meta, _) ->
    do_route(Meta, 'AT_LEAST_ONCE').

notify_receivers(From, To, Meta) ->
    case get_sessions(To) of
        [] ->
            notify_receivers_by_push(From, To, Meta);
        Sessions ->
            notify_receivers_by_notice(From, To, Meta, Sessions)
    end,
    case From#'XID'.uid of
        0 ->
            xsync_metrics:inc(message_deliver, [system], 1);
        _ ->
            xsync_metrics:inc(message_deliver, [chat], 1)
    end,
    ok.

notify_receivers_by_push(From, To, Meta) ->
    case is_meta_need_push(Meta) of
        false ->
            ok;
        true ->
            kafka_log:log_message_offline(From, To, Meta),
            message_store:incr_apns([To#'XID'.uid], 1),
            xsync_metrics:inc(message_deliver, [chat_push], 1),
            ok
    end.

notify_receivers_by_notice(From, To, Meta, Sessions) ->
    lists:foreach(
      fun({DeviceSN, Session}) ->
              Pid = msgst_session:get_session_pid(Session),
              MsgId = xsync_proto:get_meta_id(Meta),
              NewTo = To#'XID'{deviceSN = DeviceSN},
              Pid ! {route, From, NewTo, MsgId, []}
      end, Sessions),
    xsync_metrics:inc(message_deliver, [chat_notice], length(Sessions)),
    ok.

notify_receivers_by_push_metas(From, To, Metas) ->
    Sessions = get_sessions(To),
    notify_receivers_by_push_metas(From, To, Metas, Sessions).

notify_receivers_by_push_metas(From, To, Metas, Sessions) ->
    case Sessions of
        [] ->
            skip;
        _ ->
            notify_receivers_by_push_metas_1(From, To, Metas, Sessions)
    end,
    case From#'XID'.uid of
        0 ->
            xsync_metrics:inc(message_deliver, [system_QoS0], 1);
        _ ->
            xsync_metrics:inc(message_deliver, [chat_QoS0], 1)
    end,
    ok.

notify_receivers_by_push_metas_1(From, To, Metas, Sessions) ->
    lists:foreach(
      fun({DeviceSN, Session}) ->
              Pid = msgst_session:get_session_pid(Session),
              NewTo = To#'XID'{deviceSN = DeviceSN},
              Pid ! {route, From, NewTo, Metas, []}
      end, Sessions),
    xsync_metrics:inc(message_deliver, [chat_push_meta], length(Sessions)),
    ok.

get_sessions(#'XID'{uid = UserId, deviceSN = 0}) ->
    case msgst_session:get_sessions(UserId) of
        {ok, Sessions} ->
            Sessions;
        _ ->
            []
    end;
get_sessions(#'XID'{uid = UserId, deviceSN = DeviceSN}) ->
    case msgst_session:get_sessions(UserId, DeviceSN) of
        {ok, Sessions} ->
            Sessions;
        _ ->
            []
    end.

is_meta_need_push(#'Meta'{ns = NS, payload = Payload} = _Meta) ->
    case NS of
        'MESSAGE' ->
            case Payload#'MessageBody'.ctype of
                'COMMAND' ->
                    false;
                _ ->
                    case Payload#'MessageBody'.type of
                        'CHAT' ->
                            true;
                        'GROUPCHAT' ->
                            true;
                        _ ->
                            false
                    end
            end;
        'ROSTER_NOTICE' ->
            Event = Payload#'RosterNotice'.type,
            PushEvents = application:get_env(xsync, push_roster_notices, ['APPLIED']),
            lists:member(Event, PushEvents);
        'GROUP_NOTICE' ->
            Event = Payload#'GroupNotice'.type,
            PushEvents = application:get_env(xsync, push_group_notices, []),
            lists:member(Event, PushEvents);
        _ ->
            false
    end.

save(Meta) ->
    From = xsync_proto:get_meta_from(Meta),
    To = xsync_proto:get_meta_to(Meta),
    MsgId = xsync_proto:get_meta_id(Meta),
    MsgBody = xsync_proto:encode_meta(Meta),
    kafka_log:log_message_up(From, To, Meta),
    case From#'XID'.uid of
        0 ->
            xsync_metrics:inc(message_up, [system_msg_op], 1);
        _ ->
            xsync_metrics:inc(message_up, [chat_msg_op], 1)
    end,
    case message_store:write_chat_body(MsgId, MsgBody) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            ok
    end.

maybe_write_history(From, To, Meta) ->
    case is_write_history(Meta) of
        true ->
            MsgId = xsync_proto:get_meta_id(Meta),
            msgst_history:add_chat_index(From#'XID'.uid, To#'XID'.uid, MsgId);
        false ->
            skip
    end.

is_write_history(#'Meta'{ns = 'MESSAGE',
                         payload = #'MessageBody'{type='OPER'}}) ->
    false;
is_write_history(#'Meta'{ns = 'GROUP_NOTICE'}) ->
    false;
is_write_history(#'Meta'{ns = 'ROSTER_NOTICE'}) ->
    false;
is_write_history(#'Meta'{ns = 'USER_NOTICE'}) ->
    false;
is_write_history(_Meta) ->
    true.
