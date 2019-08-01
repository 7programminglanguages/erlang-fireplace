%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_device_notice.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 24 Jan 2019 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_device_notice).
-include("xsync_pb.hrl").
-include("usernotice_pb.hrl").
-export([device_login/1, device_logout/1]).

device_login(XID) ->
    send_notice_to_other_devices(XID, 'DEVICE_LOGIN').

device_logout(XID) ->
    send_notice_to_other_devices(XID, 'DEVICE_LOGOUT').

send_notice_to_other_devices(#'XID'{uid = UserId,
                                    deviceSN = DeviceSN}=XID, Event) ->
    case enabled() of
        true ->
            case msgst_session:get_sessions(UserId) of
                {error, _} ->
                    skip;
                {ok, Sessions} ->
                    OtherSessions = lists:keydelete(DeviceSN, 1, Sessions),
                    case OtherSessions of
                        [] ->
                            skip;
                        _ ->
                            Content = jsx:encode(#{deviceSN=>XID#'XID'.uid}),
                            From = xsync_proto:system_conversation(),
                            To = XID#'XID'{deviceSN = 0},
                            Payload = #'UserNotice'{
                                         type = Event,
                                         content = Content
                                        },
                            Meta = xsync_proto:new_meta(From, To, 'USER_NOTICE', Payload),
                            xsync_router:notify_receivers_by_push_metas(From, To, [Meta], OtherSessions)
                    end
            end;
        false ->
            skip
    end.

enabled() ->
    application:get_env(xsync, enable_device_status_change_notice, true).
