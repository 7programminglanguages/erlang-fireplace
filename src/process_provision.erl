%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_provision.erl
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

-module(process_provision).
-export([handle/3]).
-include("logger.hrl").
-include("xsync_pb.hrl").
-include("user_service_types.hrl").

handle(_Payload, Response, #{xid:=XID} = _State) -> %% already login
    stream:apply(Response,
                 [{xsync_proto, set_status, ['OK', <<>>]},
                  {xsync_proto, set_provision_xid, [XID]}]);
handle(Payload, Response, State) ->
    Result = handle_1(Payload, Response, State),
    case Result of
        {NewResponse,_} ->
            xsync_metrics:inc_response(client_auth, NewResponse);
        NewResponse when is_tuple(NewResponse) ->
            xsync_metrics:inc_response(client_auth, NewResponse)
    end,
    Result.

handle_1(undefined, Response, _XID) ->
    xsync_proto:set_status(Response, 'INVALID_PARAMETER', <<"no provision payload">>);
handle_1(#'Provision'{xid = XID,
                    token = Token,
                    password = Password,
                    os_type = OSType,
                    device_guid = DeviceGUID,
                    device_token = DeviceToken,
                    device_notifier = DeviceNotifier,
                    device_info = DeviceInfo,
                    sdk_vsn = SdkVsn
                   } = _Provision, Response, State) ->
    case check_auth(XID, OSType, DeviceGUID) of
        {error, {Code, Reason}} ->
            xsync_proto:set_status(Response, Code, Reason);
        ok ->
            UserId = XID#'XID'.uid,
            Token1 = case Token of
                         <<>> ->
                             Password;
                         _ ->
                             Token
                     end,
            AuthMethod = application:get_env(xsync, auth_method, jwt),
            case do_auth(AuthMethod, UserId, Token1) of
                false ->
                    xsync_proto:set_status(Response, 'INVALID_TOKEN', <<"auth token is not right">>);
                true ->
                    {Action, DeviceSN} = chose_device_sn(XID, DeviceGUID, OSType),
                    DeviceUpdateMethod = application:get_env(xsync, device_update_method, thrift),
                    MaxRetryTimes = application:get_env(xsync, device_update_max_retry_times, 2),
                    case create_or_update_device(DeviceUpdateMethod, Action, UserId, DeviceSN, OSType,
                                 DeviceGUID, DeviceToken, DeviceNotifier, DeviceInfo, MaxRetryTimes) of
                        {ok, NewDeviceSN} ->
                            NewXID = XID#'XID'{deviceSN = NewDeviceSN},
                            State1 = State#{xid=>NewXID,
                                            is_first_unread => true},
                            case do_user_login(State1, SdkVsn, DeviceToken) of
                                {error, Reason} ->
                                    xsync_proto:set_status(Response, 'FAIL', auth_fail_reason(Reason));
                                {ok, NewState} ->
                                    Response1 = stream:apply(Response,
                                                             [{xsync_proto, set_status, ['OK', <<>>]},
                                                              {xsync_proto, set_provision_xid, [NewXID]}]),
                                    {Response1, NewState}
                            end;
                        {error, Code} when is_integer(Code) ->
                            xsync_protosg:set_status(Response, 'FAIL', auth_fail_reason(Code));
                        {error, Reason} when is_atom(Reason) ->
                            xsync_proto:set_status(Response, 'FAIL', auth_fail_reason(Reason))
                    end
            end
    end.

auth_fail_reason(Reason) ->
    <<"auth service fail:", (misc:normalize_reason(Reason))/binary >>.

check_auth(XID, OSType, DeviceGUID) ->
    case check_xid(XID) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            case OSType of
                'UNKNOWN' ->
                    {error, {'INVALID_PARAMETER', <<"no os type">>}};
                _ ->
                    case DeviceGUID of
                        <<>> ->
                            {error, {'INVALID_PARAMETER', <<"no device guid">>}};
                        _ ->
                            ok
                    end
            end
    end.

check_xid(undefined) ->
    {error, {'INVALID_PARAMETER', <<"no user xid">>}};
check_xid(#'XID'{uid = 0}) ->
    {error, {'INVALID_PARAMETER', <<"no user id">>}};
check_xid(#'XID'{uid = Uid}) ->
    case misc:is_user(Uid) of
        false ->
            {error, {'INVALID_PARAMETER', <<"bad user id">>}};
        true ->
            ok
    end.

chose_device_sn(#'XID'{uid = UserId, deviceSN = DeviceSN}, DeviceGUID, OSType) ->
    case msgst_device:get_device_sn(UserId, DeviceGUID) of
        {ok, NewDeviceSN} ->
            {update, NewDeviceSN};
        _  ->
            case msgst_device:is_valid_device_sn(DeviceSN, OSType) of
                true ->
                    {new, DeviceSN};
                false ->
                    {new, msgst_device:chose_sn(UserId, DeviceGUID, OSType)}
            end
    end.

generate_sn(UserId, DeviceGUID, OSType) ->
    case thrift_pool:thrift_call(user_service_thrift, getUserDevices, [UserId]) of
        {ok, UserDeviceList} when is_list(UserDeviceList) ->
            case lists:keyfind(DeviceGUID, #'UserDevice'.deviceUUID, UserDeviceList) of
                false ->
                    DeviceSet = sets:from_list([UD#'UserDevice'.deviceSN||UD<-UserDeviceList]),
                    {ok, new, msgst_device:chose_sn(UserId, DeviceGUID, OSType, DeviceSet, 1)};
                UserDevice ->
                    {ok, update, UserDevice#'UserDevice'.deviceSN}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

do_auth(jwt, UserId, Token) ->
    Key = application:get_env(xsync, jwt_key, <<"">>),
    UserIdKey = application:get_env(xsync, jwt_user_key, <<"sub">>),
    case jwt:decode(Token, Key) of
        {ok, #{UserIdKey:= UserId}} ->
            true;
        _ ->
            false
    end;
do_auth(none, _UserId, _Token) ->
    true.

create_or_update_device(thrift, update, UserId, DeviceSN, OSType, DeviceGUID,
                             DeviceToken, Notifier, DeviceInfo, _MaxRetryTimes) ->
    spawn(
      fun()->
              DeviceDetail = #'DeviceDetail'{
                                deviceSN = DeviceSN,
                                deviceUUID = DeviceGUID,
                                deviceToken = DeviceToken,
                                notifier = Notifier,
                                deviceInfo = DeviceInfo,
                                platform = msgst_device:platform_to_int(OSType)
                               },
              case thrift_pool:thrift_call(user_service_thrift, updateDevice, [UserId, DeviceDetail]) of
                  {ok, _} ->
                      ok;
                  Reason ->
                      ?ERROR_MSG("fail to update device: user=~p, deviceGUID=~p, deviceSN=~p, reason=~p",
                                 [UserId, DeviceGUID, DeviceSN, Reason])
              end
      end),
    {ok, DeviceSN};
create_or_update_device(thrift, new, UserId, DeviceSN, OSType, DeviceGUID,
                             DeviceToken, Notifier, DeviceInfo, MaxRetryTimes) ->
    DeviceDetail = #'DeviceDetail'{
                      deviceSN = DeviceSN,
                      deviceUUID = DeviceGUID,
                      deviceToken = DeviceToken,
                      notifier = Notifier,
                      deviceInfo = DeviceInfo,
                      platform = msgst_device:platform_to_int(OSType)
                     },
    case thrift_pool:thrift_call(user_service_thrift, createDevice, [UserId, DeviceDetail]) of
        {ok, true} ->
            msgst_device:set_device_sn(UserId, DeviceGUID, DeviceSN),
            {ok, DeviceSN};
        {ok, false} when MaxRetryTimes > 0 ->
            case generate_sn(UserId, DeviceGUID, OSType) of
                {error, Reason} ->
                    {error, Reason};
                {ok, NewAction, NewDeviceSN} ->
                    case NewAction of
                        update ->
                            msgst_device:set_device_sn(UserId, DeviceGUID, NewDeviceSN);
                        _ ->
                            skip
                    end,
                    create_or_update_device(thrift, NewAction, UserId, NewDeviceSN,
                                                 OSType, DeviceGUID, DeviceToken, Notifier, DeviceInfo, MaxRetryTimes - 1)
            end;
        {ok, false} ->
            {error, cannot_create_device_sn};
        {error, Reason} ->
            {error, Reason}
    end;
create_or_update_device(none, _Action, _UserId, DeviceSN, _OSType, _DeviceGUID,
                             _DeviceToken, _Notifier, _DeviceInfo, _IsFirst) ->
    {ok, DeviceSN}.

do_user_login(#{xid := #'XID'{uid = UserId, deviceSN = DeviceSN} = XID,
                transport := Transport, socket:= Socket} = State, SdkVsn, DeviceToken) ->
    case msgst_device:user_login(UserId, DeviceSN, DeviceToken) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            msgst_session:open_session(UserId, DeviceSN, #{}),
            log_user_online(XID, SdkVsn, Transport, Socket),
            spawn(fun()->xsync_device_notice:device_login(XID) end),
            message_store:adjust_offline(UserId, DeviceSN),
            message_store:delete_apns(UserId),
            NewState = init_shaper(State),
            {ok, NewState}
    end.


log_user_online(XID, SdkVsn, Transport, Socket) ->
    Event = online,
    Reason = <<>>,
    case Transport:peername(Socket) of
        {ok, {{P1,P2,P3,P4}, Port}} ->
            IpPort = iolist_to_binary(io_lib:format("~p.~p.~p.~p:~p", [P1,P2,P3,P4,Port]));
        _ ->
            IpPort = <<"0.0.0.0:0">>
    end,
    kafka_log:log_user_status(XID, Event, Reason, IpPort, SdkVsn).

init_shaper(State) ->
    Speed = application:get_env(xsync, client_speed, 3000),
    State#{shaper=>msgst_shaper:new(max, Speed)}.
