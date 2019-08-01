%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_group_notice_handler.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  23 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_group_notice_handler).

-export([handle/1]).
-include("logger.hrl").
-include("kafka_notice_pb.hrl").
-include("groupnotice_pb.hrl").

handle(#'KafkaGroupNotice'{type = Event, group_id = GroupXID0, invoker = Invoker0,
                           to = ToXIDs, roles = Roles, content = Content} = KafkaGroupNotice) ->
    ?INFO_MSG("HandleGroupNotice:~p", [xsync_proto:pr(KafkaGroupNotice)]),
    try
        case check_event(Invoker0, GroupXID0, ToXIDs) of
            {error, Reason} ->
                ?ERROR_MSG("fail to check event: notice=~p, Reason=~p", [KafkaGroupNotice, Reason]),
                {error, Reason};
            {ok, Invoker, GroupXID} ->
                handle_event(Event, GroupXID, Invoker, ToXIDs),
                notify_event(Event, GroupXID, Invoker, ToXIDs, Roles, Content)
        end
    catch
        C:E ->
            ?ERROR_MSG("fail to handle event: notice=~p, error=~p",
                       [KafkaGroupNotice, {C,{E, erlang:get_stacktrace()}}]),
            ok
    end.

handle_event('CREATED', GroupXID, Invoker, ToXIDs) ->
    init_group_cursor([Invoker|ToXIDs], GroupXID);
handle_event('DESTROYED', GroupXID, _Invoker, ToXIDs) ->
    clean_group_cursor(ToXIDs, GroupXID);
handle_event('JOINED', GroupXID, Invoker, _ToXIDs) ->
    init_group_cursor([Invoker], GroupXID);
handle_event('LEAVED', GroupXID, Invoker, _ToXIDs) ->
    clean_group_cursor([Invoker], GroupXID);
handle_event('KICKED', GroupXID, _Invoker, ToXIDs) ->
    clean_group_cursor(ToXIDs, GroupXID);
handle_event(_, _GroupXID, _Invoker, _ToXIDs) ->
    ok.

check_event(Invoker, GroupXID, ToXIDs) ->
    case check_invoker(Invoker) of
        {error, Reason} ->
            {error, Reason};
        {ok, NewInvoker} ->
            case check_group(GroupXID) of
                {error, Reason} ->
                    {error, Reason};
                {ok, NewGroupXID} ->
                    case check_xids(ToXIDs) of
                        {error, Reason} ->
                            {error, Reason};
                        ok ->
                            {ok, NewInvoker, NewGroupXID}
                    end
            end
    end.

check_invoker(undefined) ->
    {ok, #'XID'{}};
check_invoker(#'XID'{uid = 0}=_XID) ->
    {ok, #'XID'{deviceSN = 0}};
check_invoker(#'XID'{uid = UserId} = XID) ->
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

check_group(GroupXID) ->
    case GroupXID of
        undefined ->
            {error, bad_group_xid};
        #'XID'{uid = 0} ->
            {error, bad_group_id};
        #'XID'{uid = GroupId} ->
            case misc:is_group(GroupId) of
                false ->
                    {error, bad_group_id};
                true ->
                    {ok,GroupXID#'XID'{deviceSN = 0}}
            end
    end.

init_group_cursor(XIDs, #'XID'{uid = GroupId}) ->
    lists:foreach(
      fun(XID) ->
              message_store:init_group_index(GroupId, XID#'XID'.uid)
      end, XIDs).

clean_group_cursor(XIDs, #'XID'{uid = GroupId}) ->
    lists:foreach(
      fun(XID) ->
              message_store:clean_group_index(GroupId, XID#'XID'.uid)
      end, XIDs).

notify_event(Event, GroupXID, Invoker, ToXIDs, Roles, Content) ->
    Invokers = get_notify_invokers(Event, GroupXID, Invoker, ToXIDs, Roles, Content),
    Receivers = get_notify_receivers(Event, GroupXID, Invoker, ToXIDs, Roles, Content),
    Admins = get_notify_admins(Event, GroupXID, Invoker, ToXIDs, Roles, Content),
    Members = get_notify_members(Event, GroupXID, Invoker, ToXIDs, Roles, Content),
    NotifyList = lists:usort(Invokers ++ Receivers ++ Admins ++ Members),
    MetaFrom = xsync_proto:system_conversation(),
    lists:foreach(
      fun(XID) ->
              Meta = make_notify_meta(MetaFrom, XID, Event, GroupXID, Invoker, ToXIDs, Content),
              xsync_router:route(Meta)
      end, NotifyList),
    ok.

get_notify_invokers(_Event, _GroupXID, Invoker, _ToXIDs, Roles, _Content) ->
    case lists:member('INVOKER', Roles) of
        true ->
            [Invoker];
        false ->
            []
    end.

get_notify_receivers(_Event, _GroupXID, _Invoker, ToXIDs, Roles, _Content) ->
    case lists:member('TO', Roles) of
        true ->
            case lists:member('MEMBER', Roles) of
                false ->
                    ToXIDs;
                true ->
                    []
            end;
        false ->
            []
    end.

get_notify_admins(_Event, GroupXID, _Invoker, _ToXIDs, Roles, _Content) ->
    case lists:member('ADMIN', Roles) of
        true ->
            case lists:member('MEMBER', Roles) of
                false ->
                    case msgst_group:get_group_roles(GroupXID#'XID'.uid, <<"admin">>) of
                        {error, _Reason} ->
                            [];
                        {ok, UserIds} ->
                            [#'XID'{uid=UserId}||UserId<-UserIds]
                    end;
                true ->
                    []
            end;
        false ->
            []
    end.

get_notify_members(_Event, GroupXID, _Invoker, _ToXIDs, Roles, _Content) ->
    case lists:member('MEMBER', Roles) of
        true ->
            case msgst_group:get_group_members(GroupXID#'XID'.uid) of
                {ok, UserIds} ->
                    [#'XID'{uid=UserId}||UserId<-UserIds];
                {error, _Reason} ->
                    []
            end;
        false ->
            []
    end.

make_notify_meta(MetaFrom, MetaTo, Event, GroupXID, Invoker, ToXIDs, Content) ->
    Payload = #'GroupNotice'{
                 type = Event,
                 gid = GroupXID,
                 from = Invoker,
                 to = ToXIDs,
                 content = Content
                },
    xsync_proto:new_meta(MetaFrom, MetaTo, 'GROUP_NOTICE', Payload).
