%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_roster_notice_handler.erl
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
-module(xsync_roster_notice_handler).

-export([handle/1]).
-include("logger.hrl").
-include("kafka_notice_pb.hrl").
-include("rosternotice_pb.hrl").

handle(#'KafkaRosterNotice'{type = Event, from = From0, tos = ToXIDs, content = Content,
                            roster_vsn = RosterVsn, notify_type = NotifyType} = KafkaRosterNotice) ->
    ?INFO_MSG("HandleRosterNotice:~p", [xsync_proto:pr(KafkaRosterNotice)]),
    try
        case check_event(From0, ToXIDs) of
            {error, Reason} ->
                ?ERROR_MSG("fail to check event: notice=~p, Reason=~p", [KafkaRosterNotice, Reason]),
                {error, Reason};
            {ok, From} ->
                notify_event(Event, From, ToXIDs, Content, RosterVsn, NotifyType)
        end
    catch
        C:E ->
            ?ERROR_MSG("fail to handle event: notice=~p, error=~p",
                       [KafkaRosterNotice, {C,{E, erlang:get_stacktrace()}}]),
            ok
    end.

check_event(From, ToXids) ->
    case check_from(From) of
        {error, Reason} ->
            {error, Reason};
        {ok, NewFrom} ->
            case check_xids(ToXids) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    {ok, NewFrom}
            end
    end.

check_from(undefined) ->
    {error, bad_from};
check_from(#'XID'{uid = 0}=_XID) ->
    {error, bad_from};
check_from(#'XID'{uid = UserId} = XID) ->
    case misc:is_user(UserId) of
        false ->
            {error, bad_user_id};
        true ->
            {ok, XID#'XID'{deviceSN = 0}}
    end.

check_xids(XIDs) ->
    case lists:any(
           fun(#'XID'{uid=UserId, deviceSN = 0}) ->
                   case misc:is_user(UserId) of
                       true ->
                           false;
                       false ->
                           true
                   end;
              (_) ->
                   true
           end, XIDs) of
        true ->
            {error, bad_to_xids};
        false ->
            ok
    end.

notify_event(Event, From, ToXIDs, Content, RosterVsn, NotifyType) ->
    maybe_notify_froms(Event, From, ToXIDs, Content, RosterVsn, NotifyType),
    maybe_notify_tos(Event, From, ToXIDs, Content, RosterVsn, NotifyType),
    ok.


maybe_notify_froms(Event, From, ToXIDs, Content, RosterVsn, NotifyType)->
    case lists:member(NotifyType, ['INVOKER', 'ALL']) of
        true ->
            MetaFrom = xsync_proto:system_conversation(),
            Payload = #'RosterNotice'{
                         type = Event,
                         from = From,
                         to = ToXIDs,
                         content = Content,
                         roster_vsn = RosterVsn
                        },
            Meta = xsync_proto:new_meta(MetaFrom, From, 'ROSTER_NOTICE', Payload),
            xsync_router:route(Meta);
        false ->
            skip
    end.

maybe_notify_tos(Event, From, ToXIDs, Content, RosterVsn, NotifyType) ->
    case lists:member(NotifyType, ['RECEIVER', 'ALL']) of
        true ->
            MetaFrom = xsync_proto:system_conversation(),
            lists:foreach(
              fun(ToXID) ->
                      Payload = #'RosterNotice'{
                                   type = Event,
                                   from = From,
                                   to = [ToXID],
                                   content = Content,
                                   roster_vsn = RosterVsn
                                  },
                      Meta = xsync_proto:new_meta(MetaFrom, ToXID, 'ROSTER_NOTICE', Payload),
                      xsync_router:route(Meta)
              end, ToXIDs);
        false ->
            skip
    end.
