%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_device.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  12 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_device).

-include("user_service_types.hrl").
-include("message_store_const.hrl").
-include("logger.hrl").

-export([is_valid_device_sn/2,
         platform_to_int/1,
         int_to_platform/1,
         chose_sn/3,
         chose_sn/5,
         user_login/3,
         remove_user_device/2,
         get_user_all_devices/1,
         get_users_all_devices/1,
         get_avail_device_list/1,
         get_avail_device/2,
         get_default_device/0,
         get_device_sn/2,
         set_device_sn/3
]).


%% @doc
%% for each user
%%     get all devices
%%     delete expired devices
%%     delete offline, including conversations and mid lists
%%     if length(avail devices) > 1
%%         return avail devices, plus default device
%%     else
%%         just return default device
%% @end
get_avail_device_list(UserList) when is_list(UserList) ->
    Now = erlang:system_time(milli_seconds),
    case get_users_all_devices(UserList) of
        {error, Reason} ->
            {error, Reason};
        {ok, DeviceListList} ->
            {ok,lists:map(
                fun({User, {error, Reason}}) ->
                    {User, {error, Reason}};
                ({User, DeviceList}) ->
                    {ExpiredDeviceList, AvailDeviceList} = lists:partition(
                        fun({DeviceSN, Time}) ->
                                check_and_maybe_reset_expired_time(User, DeviceSN, Time, Now)
                        end, DeviceList),
                    ExpiredList = lists:map(fun({DeviceSN, _Time}) -> DeviceSN end, ExpiredDeviceList),
                    spawn(fun() -> msgst_device:remove_user_device(User, ExpiredList) end),
                    spawn(fun() -> msgst_message_index:remove_offline(User, ExpiredList) end),
                    AvailList = lists:map(fun({DeviceSN, _Time}) -> DeviceSN end, AvailDeviceList),
                    check_avail_device_list(AvailList)
                end, lists:zip(UserList, DeviceListList))}
    end;
get_avail_device_list(User) ->
    Now = erlang:system_time(milli_seconds),
    case get_user_all_devices(User) of
        {error, Reason} ->
            {error, Reason};
        {ok,DeviceList} ->
            {ExpiredDeviceList, AvailDeviceList} = lists:partition(
                fun({DeviceSN, Time}) ->
                    check_and_maybe_reset_expired_time(User, DeviceSN, Time, Now)
                end, DeviceList),
            ExpiredList = lists:map(fun({DeviceSN, _Time}) -> DeviceSN end, ExpiredDeviceList),
            spawn(fun() -> msgst_device:remove_user_device(User, ExpiredList) end),
            spawn(fun() -> msgst_message_index:remove_offline(User, ExpiredList) end),
            AvailList = lists:map(fun({DeviceSN, _Time}) -> DeviceSN end, AvailDeviceList),
            {ok, check_avail_device_list(AvailList)}
    end.

get_avail_device(User, Device) ->
    case get_avail_device_list(User) of
        {ok, AvailList} ->
            case lists:member(Device, AvailList) of
                true ->
                    Device;
                false ->
                    ?DEFAULT_DEVICE
            end;
        _ ->
            ?DEFAULT_DEVICE
    end.

get_default_device() ->
    ?DEFAULT_DEVICE.

get_device_sn(UserId, DeviceGUID) ->
    Key = device_guid_key(UserId, DeviceGUID),
    case redis_pool:q(device, [get, Key]) of
        {ok, undefined} ->
            not_found;
        {ok, DeviceSN} ->
            spawn(fun() ->
                          ExpireTime = device_guid_expire_time(),
                          redis_pool:q(device, [expire, Key, ExpireTime])
                  end),
            {ok, binary_to_integer(DeviceSN)};
        {error, Reason} ->
            {error, Reason}
    end.

set_device_sn(UserId, DeviceGUID, DeviceSN) ->
    ExpireTime = device_guid_expire_time(),
    case redis_pool:q(device, [setex, device_guid_key(UserId, DeviceGUID), ExpireTime, DeviceSN]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

device_guid_expire_time() ->
    application:get_env(message_store, device_guid_expire_time, 604800).

is_valid_device_sn(DeviceSN, OSType) ->
    try
        Platform = sn_to_platform(DeviceSN),
        Platform == OSType andalso DeviceSN > 0
    catch
        _:_ ->
            false
    end.

make_sn(OSType, Seq) ->
    OSInt = platform_to_int(OSType),
    (OSInt bsl 16) bxor Seq.

chose_sn(UserId, DeviceGUID, OSType) ->
    chose_sn(UserId, DeviceGUID, OSType, sets:new(), 1).

chose_sn(UserId, DeviceGUID, OSType, DeviceSet, Salt) when Salt < 16#ffff->
    Seq = erlang:phash2({UserId, DeviceGUID, Salt}, 16#ffff) + 1,
    DeviceSN = make_sn(OSType, Seq),
    case sets:is_element(DeviceSN, DeviceSet) of
        true ->
            chose_sn(UserId, DeviceGUID, OSType, DeviceSet, Salt+1);
        false ->
            DeviceSN
    end.

user_login(UserId, DeviceSN, DeviceToken) ->
    %% check device group allow this platform
    case check_platform_is_allowed(DeviceSN) of
        {error, Reason} -> {error, Reason};
        {ok, DeviceGroup,  Limit} ->
            Now = erlang:system_time(milli_seconds),
            %% device group not exceed num limit, when exceed it will replace old one
            case check_device_exceed_limit(UserId, DeviceSN, DeviceGroup, Limit, Now) of
                {error, Reason} ->
                    {error, Reason};
                {online, Session} ->
                    %% device is online, just replace it
                    SessionPid = msgst_session:get_session_pid(Session),
                    msgst_session:replace_session(SessionPid,UserId, DeviceSN,
                                                  'KICK_BY_SAME_DEVICE', DeviceSN, self(), DeviceToken),
                    update_user_device(UserId, DeviceSN, Now),
                    ok;
                {offline, IsNewDevice, KickedOnlineDevices, KickedOfflineDevices, NewDevices, Sessions} ->
                    %% clear expired and overflowed device
                    kick_online_devices(UserId, KickedOnlineDevices, Sessions, DeviceSN, self()),
                    kick_offline_devices(UserId, KickedOfflineDevices),
                    %% update now device login time
                    update_user_device(UserId, DeviceSN, Now),
                    %% maybe init offline by device num(1->2, init all device offline , 2-N -> init new device offline)
                    maybe_clone_offline(UserId, DeviceSN, IsNewDevice, NewDevices),
                    ok
            end
    end.

maybe_clone_offline(UserId, _DeviceSN, true, Devices) when length(Devices) == 2 ->
    lists:foreach(
      fun({DSN, _}) ->
              msgst_message_index:clone_offline(UserId, ?DEFAULT_DEVICE, DSN)
      end, Devices);
maybe_clone_offline(UserId, DeviceSN, true, Devices) when length(Devices) > 2 ->
    msgst_message_index:clone_offline(UserId, ?DEFAULT_DEVICE, DeviceSN);
maybe_clone_offline(_,_,_,_) ->
    skip.


kick_online_devices(UserId, Devices, Sessions, InvokerDeviceSN, InvokerPid) ->
    lists:foreach(
      fun({DeviceSN, _}) ->
              Session = get_device_session(DeviceSN, Sessions),
              SessionPid = msgst_session:get_session_pid(Session),
              msgst_session:replace_session(SessionPid, UserId, DeviceSN,
                                            'KICKED_BY_OTHER_DEVICE', InvokerDeviceSN, InvokerPid, <<>>),
              msgst_session:close_session(UserId, DeviceSN, SessionPid),
              remove_user_device(UserId, DeviceSN),
              msgst_message_index:remove_offline(UserId, DeviceSN)
      end, Devices).

kick_offline_devices(UserId, Devices) ->
    lists:foreach(
      fun({DeviceSN, _}) ->
              remove_user_device(UserId, DeviceSN),
              msgst_message_index:remove_offline(UserId, DeviceSN)
      end, Devices).

check_platform_is_allowed(DeviceSN) ->
    Platform = sn_to_platform(DeviceSN),
    DeviceGroup = platform_to_device_group(Platform),
    Limit = get_device_group_limit(DeviceGroup),
    case Limit > 0 of
        true ->
            {ok, DeviceGroup, Limit};
        false ->
            {error, platform_not_allowed}
    end.

check_device_exceed_limit(UserId, DeviceSN, DeviceGroup, Limit, Now) ->
    case msgst_session:get_sessions(UserId) of
        {error, Reason} ->
            {error, Reason};
        {ok, Sessions} ->
            case is_device_online(DeviceSN, Sessions) of
                true ->
                    Session = get_device_session(DeviceSN, Sessions),
                    {online, Session};
                false ->
                    case get_user_all_devices(UserId) of
                        {error, Reason} ->
                            {error, Reason};
                        {ok, Devices} ->
                            {ValidDevices, ExpiredDevices} =
                                split_devices_by_valid(Devices, Sessions, Now),
                            case is_device_new(DeviceSN, ValidDevices) of
                                false ->
                                    NewDevices = lists:keyreplace(DeviceSN, 1,  ValidDevices, {DeviceSN, Now}),
                                    {offline, false, [], ExpiredDevices, NewDevices, Sessions};
                                true ->
                                    {OnlineDevices, OfflineDevices}
                                        = trunc_devices(ValidDevices, Sessions, DeviceGroup, Limit),
                                    KickedOfflineDevices = OfflineDevices ++ ExpiredDevices,
                                    NewDevices =([{DeviceSN, Now}|Devices] -- (OnlineDevices)) -- KickedOfflineDevices,
                                    {offline, true, OnlineDevices, KickedOfflineDevices, NewDevices, Sessions}
                            end
                    end
            end
    end.

trunc_devices(ValidDevices, Sessions, DeviceGroup, Limit) ->
    {DeviceGroupDevices,_} = split_devices_by_group(ValidDevices, DeviceGroup),
    case length(DeviceGroupDevices) < Limit of
        true ->
            {[], []};
        false ->
            {OnlineDevices, OfflineDevices} = split_devices_by_online(DeviceGroupDevices, Sessions),
            case length(OnlineDevices) < Limit of
                true ->
                    SortedOfflineDevices = sort_devices(OfflineDevices),
                    RemovedOfflineDevices = lists:sublist(SortedOfflineDevices, length(DeviceGroupDevices) + 1 - Limit),
                    {[], RemovedOfflineDevices};
                false ->
                    SortedOnlineDevices = sort_devices(OnlineDevices),
                    RemovedOnlineDevices = lists:sublist(SortedOnlineDevices, length(OnlineDevices) + 1 - Limit),
                    {RemovedOnlineDevices, OfflineDevices}
            end
    end.

split_devices_by_valid(Devices, Sessions, Now) ->
    lists:partition(
      fun({DeviceSN, Time}) ->
              is_device_online(DeviceSN, Sessions)
                  orelse (not is_device_expired(DeviceSN, Time, Now))
      end, Devices).

sort_devices(Devices) ->
    lists:sort(
      fun({_, Time1}, {_, Time2}) ->
              Time1 < Time2
      end, Devices).

split_devices_by_group(Devices, DeviceGroup) ->
    lists:partition(
      fun({DeviceSN, _Time}) ->
              sn_to_device_group(DeviceSN) == DeviceGroup
      end, Devices).
split_devices_by_online(Devices, Sessions) ->
    lists:partition(
      fun({DeviceSN, _Time}) ->
              is_device_online(DeviceSN, Sessions)
      end, Devices).

is_device_online(DeviceSN, Sessions) ->
    lists:keyfind(DeviceSN, 1, Sessions) /= false.

get_device_session(DeviceSN, Sessions) ->
    {_, Session} = lists:keyfind(DeviceSN, 1, Sessions),
    Session.

is_device_new(DeviceSN, Devices) ->
    lists:keyfind(DeviceSN, 1, Devices) == false.

is_device_expired(DeviceSN, Time, Now) ->
    DeviceGroup = sn_to_device_group(DeviceSN),
    ExpireTime = get_device_expire_time(DeviceGroup),
    Now > Time + ExpireTime.

check_and_maybe_reset_expired_time(UserId, DeviceSN, Time, Now) ->
    case is_device_expired(DeviceSN, Time, Now) of
        false ->
            false;
        true ->
            case msgst_session:get_sessions(UserId, DeviceSN) of
                {ok, []} ->
                    true;
                {ok, [_]} ->
                    update_user_device(UserId, DeviceSN, Time),
                    false;
                {error, _} ->
                    false
            end
    end.

get_user_all_devices(UserId) ->
    case get_users_all_devices([UserId]) of
        {ok,[{error, Reason}]} ->
            {error, Reason};
        {ok,[DeviceList]} ->
            {ok,DeviceList};
        {error, Reason} ->
            {error, Reason}
    end.

get_users_all_devices(UserIdList) ->
    Commands = [[hgetall, device_key(UserId)]||UserId<-UserIdList],
    case redis_pool:qp(device, Commands) of
        {error, Reason} ->
            {error, Reason};
        List ->
            Devices = lists:map(
                        fun({ok, DeviceList}) ->
                                list_to_devices(DeviceList, []);
                           ({error, Reason}) ->
                                {error, Reason}
                        end, List),
            {ok, Devices}
    end.


remove_user_device(_UserId, []) ->
    ok;
remove_user_device(UserId, DeviceList) when is_list(DeviceList) ->
    Queries = lists:map(fun(DeviceSN) -> [hdel, device_key(UserId), DeviceSN] end, DeviceList),
    case redis_pool:qp(device, Queries) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            spawn(fun() ->
                          lists:foreach(
                            fun(DeviceSN) ->
                                    remove_user_device_from_db(UserId, DeviceSN)
                            end, DeviceList)
                  end),
            ok
    end;
remove_user_device(UserId, DeviceSN) ->
    case redis_pool:q(device, [hdel, device_key(UserId), DeviceSN]) of
        {ok, _} ->
            spawn(fun() ->
                          remove_user_device_from_db(UserId, DeviceSN)
                  end),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

remove_user_device_from_db(UserId, DeviceSN) ->
    DeviceUpdateMethod = application:get_env(xsync, device_update_method, thrift),
    remove_user_device_from_db(DeviceUpdateMethod, UserId, DeviceSN).

remove_user_device_from_db(thrift, UserId, DeviceSN) ->
    case thrift_pool:thrift_call(user_service_thrift, deleteDevice, [UserId, DeviceSN]) of
        {ok, true} ->
            ok;
        Reason ->
            ?ERROR_MSG("fail to update device: user=~p, deviceSN=~p, reason=~p",
                       [UserId, DeviceSN, Reason])
    end;
remove_user_device_from_db(none, _, _) ->
    ok.

update_user_device(UserId, DeviceSN, LoginTime) ->
    redis_pool:q(device, [hset, device_key(UserId), DeviceSN, LoginTime]).

list_to_devices([DeviceSN, Time | List], Acc) ->
    list_to_devices(List, [{binary_to_integer(DeviceSN), binary_to_integer(Time)}|Acc]);
list_to_devices([], Acc) ->
    lists:reverse(Acc).

platform_to_device_group(Platform) ->
    GroupList = application:get_env(message_store, device_group, []),
    {_, Group} = lists:keyfind(Platform, 1, GroupList),
    Group.

get_device_group_limit(DeviceGroup) ->
    LimitList = application:get_env(message_store, device_group_limit, []),
    {_, Limit} = lists:keyfind(DeviceGroup, 1, LimitList),
    Limit.

get_device_expire_time(DeviceGroup) ->
    ExpireTimeList = application:get_env(message_store, device_expire_time, []),
    {_, ExpireTime} = lists:keyfind(DeviceGroup, 1, ExpireTimeList),
    ExpireTime.

platform_to_int(OSType) ->
    xsync_proto:os_type_to_int(OSType).

int_to_platform(OSTypeInt) ->
    xsync_proto:int_to_os_type(OSTypeInt).

sn_to_platform(DeviceSN) ->
    PlatformInt = DeviceSN bsr 16,
    int_to_platform(PlatformInt).

sn_to_device_group(DeviceSN) ->
    platform_to_device_group(sn_to_platform(DeviceSN)).

device_key(UserId) ->
    <<"dv:", (integer_to_binary(UserId))/binary>>.

device_guid_key(UserId, GUID) ->
    <<"dvm:",(integer_to_binary(UserId))/binary, ":", GUID/binary>>.

check_avail_device_list(AvailDeviceList) when erlang:length(AvailDeviceList) > 1 ->
    [?DEFAULT_DEVICE | AvailDeviceList];
check_avail_device_list(_AvailDeviceList) ->
    [?DEFAULT_DEVICE].
