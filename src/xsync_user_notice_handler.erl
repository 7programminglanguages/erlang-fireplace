%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_user_notice_handler.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 23 Jan 2019 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_user_notice_handler).

-export([handle/1]).
-include("logger.hrl").
-include("kafka_notice_pb.hrl").
-include("usernotice_pb.hrl").

handle(#'KafkaUserNotice'{type = Event, user = User, content = Content} = KafkaUserNotice) ->
    ?INFO_MSG("HandleUserNotice:~p", [xsync_proto:pr(KafkaUserNotice)]),
    try
        case check_user(User) of
            {error, Reason} ->
                ?ERROR_MSG("fail to check event: notice=~p, Reason=~p", [KafkaUserNotice, Reason]),
                {error, Reason};
            {ok, NewUser} ->
                notify_event(Event, NewUser, Content)
        end
    catch
        C:E ->
            ?ERROR_MSG("fail to handle event: notice=~p, error=~p",
                       [KafkaUserNotice, {C,{E, erlang:get_stacktrace()}}]),
            ok
    end.

check_user(undefined) ->
    {error, bad_from};
check_user(#'XID'{uid = 0}=_XID) ->
    {error, bad_from};
check_user(#'XID'{uid = UserId} = XID) ->
    case misc:is_user(UserId) of
        false ->
            {error, bad_user_id};
        true ->
            {ok, XID#'XID'{deviceSN = 0}}
    end.

notify_event(Event, User, Content) ->
    MetaFrom = xsync_proto:system_conversation(),
    Payload = #'UserNotice'{
                 type = Event,
                 content = Content
                },
    Meta = xsync_proto:new_meta(MetaFrom, User, 'USER_NOTICE', Payload),
    xsync_router:route(Meta).
