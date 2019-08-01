%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_c2s_handler.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  6 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_c2s_handler).
-export([handle_msg/2, handle_terminate/2]).
-export([send_pb_message/2]).
-include("logger.hrl").
-include("xsync_pb.hrl").

handle_msg({route, From, To, MsgInfo, Opts}, State) ->
    handle_route(From, To, MsgInfo, Opts, State);
handle_msg({SocketEvent, Socket, Data}, #{socket:=Socket,
                                          transport:=Transport,
                                          encrypt_method:=EncryptMethod,
                                          encrypt_key:=EncryptKey
                                         } = State) ->
    ?DEBUG("Recv Packet:~p", [{SocketEvent, Socket, Data}]),
    {_, _, SocketError} = Transport:messages(),
    case SocketEvent of
        SocketError ->
            {stop, SocketError};
        _ ->
            try xsync_proto:decode(Data, EncryptMethod, EncryptKey) of
                {error, {fail_encrypt, Frame}} ->
                    handle_decrypt_fail(Frame, State);
                {error, Reason} ->
                    {stop, Reason};
                Frame ->
                    ?DEBUG("Handler Frame:xid=~p, Frame=~p", [maps:get(xid, State, undefined), xsync_proto:pr(Frame)]),
                    DataSize = byte_size(Data),
                    handle_frame(Frame, DataSize, State)
            catch
                Class:Reason ->
                    ?ERROR_MSG("Failed to decode packet: xid=~p, Error:~p, packet=~p",
                               [maps:get(xid,State, undefined), {Class, Reason, erlang:get_stacktrace()}, Data]),
                    {stop, decode_error}
            end
    end;
handle_msg({replaced, UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, DeviceToken}, State) ->
    handle_session_replaced(UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, DeviceToken, State);
handle_msg({Error, Socket}, #{socket:=Socket}) ->
    {stop, Error};
handle_msg({Ref, _}, _State) when is_reference(Ref) ->
    ok;
handle_msg(UnknownMsg, State) ->
    ?WARNING_MSG("UnknownMsg:Msg=~p, State=~p", [UnknownMsg, State]).

handle_terminate(replaced, #{xid:=#'XID'{uid=UserId, deviceSN = DeviceSN}} = State) ->
    do_user_logout(UserId, DeviceSN, replaced, State),
    ok;
handle_terminate(Reason, #{xid:=#'XID'{uid=UserId, deviceSN = DeviceSN}} = State) ->
    Self = self(),
    spawn(fun() ->
                  ?INFO_MSG("C2s terminate: Reason=~p, State=~p", [Reason, State]),
                  msgst_session:close_session(UserId, DeviceSN, Self),
                  do_user_logout(UserId, DeviceSN, Reason, State)
          end),
    ok;
handle_terminate(_, #{}) ->
    ok.

do_user_logout(_UserId, _DeviceSN, Reason, #{xid:=XID}=_State) ->
    LogoutReason = case Reason of
                       replaced ->
                           <<"replaced">>;
                       _ ->
                           spawn(fun()->xsync_device_notice:device_logout(XID) end),
                           <<>>
                   end,
    kafka_log:log_user_status(XID, offline, LogoutReason, undefined, undefined),
    ok.

handle_frame(Frame, DataSize, State) ->
    case handle_frame_dispatch(Frame, State) of
        {stop, Reason, Response} ->
            send_pb_message(Response, State),
            {stop, Reason};
        #'Frame'{} = Response ->
            send_pb_message(Response, State),
            NewState = maybe_traffic_limit(DataSize, State),
            receive_next_packet(NewState);
        {#'Frame'{} = Response, State1 = #{}} ->
            send_pb_message(Response, State1),
            NewState = maybe_traffic_limit(DataSize, State1),
            receive_next_packet(NewState)
    end.

maybe_traffic_limit(DataSize,#{shaper:=Shaper} = State) ->
    Size = DataSize + 4,
    {NewShaper, Pause} = msgst_shaper:update(Shaper, Size),
    ?DEBUG("Pause Time:~p", [Pause]),
    case Pause > 0 of
        true ->
            timer:sleep(Pause);
        false ->
            ok
    end,
    State#{shaper:=NewShaper};
maybe_traffic_limit(_, State) ->
    State.

handle_frame_dispatch(#'Frame'{command = Command, payload=Payload,
                               encrypt_method = EncryptMethod,
                               encrypt_key = EncryptKey}, State) ->
    Response = stream:apply(#'Frame'{},
                           [{xsync_proto,set_command, [dl, Command]},
                            {xsync_proto,set_status, ['OK', <<>>]}]),
    XID = maps:get(xid, State, undefined),
    case Command of
        'PROVISION' ->
            case process_provision:handle(Payload, Response, State) of
                {#'Frame'{} = NewResponse, NewState = #{}} ->
                    {NewResponse, NewState#{encrypt_method:= EncryptMethod,
                                         encrypt_key:=EncryptKey}};
                #'Frame'{} = NewResponse ->
                    NewResponse
            end;
        _ when XID == undefined ->
            Response2 = xsync_proto:set_status(Response, 'UNAUTHORIZED', <<"you must login first">>),
            {stop, not_authorized, Response2};
        'SYNC' ->
            process_sync:handle(Payload, Response, XID);
        'UNREAD' ->
            process_unread:handle(Payload, Response, State)
    end.

handle_decrypt_fail(Frame, State) ->
    Response = stream:apply(Frame,
                           [{xsync_proto, set_command, [dl, Frame#'Frame'.command]},
                            {xsync_proto, set_status, ['DECRYPT_FAILURE', <<"failed to decrypt your packet">>]}]),
    send_pb_message(Response, State),
    receive_next_packet(State).

receive_next_packet(#{socket:=Socket, transport:=Transport} = State) ->
    Transport:setopts(Socket, [{active, once}]),
    State.

send_pb_message(#'Frame'{} = Frame, #{encrypt_method:=EncryptMethod,
                                      encrypt_key:= EncryptKey,
                                      socket:=Socket,
                                      transport:=Transport} = State) ->
    ?DEBUG("Send frame to client:xid=~p, Msg=~p", [maps:get(xid,State,undefined),xsync_proto:pr(Frame)]),
    CompressMethod = maps:get(compress_method, State, undefined),
    Data = xsync_proto:encode(Frame, CompressMethod, EncryptMethod, EncryptKey),
    case Transport:send(Socket, Data) of
        ok ->
            ?DEBUG("Send binary to client:xid=~p, Data=~p", [maps:get(xid,State,undefined),Data]),
            ok;
        {error, Reason} ->
            throw({stop,{send_fail,Reason}})
    end.

handle_session_replaced(UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, DeviceToken,
                        #{xid:=#'XID'{uid = UserId, deviceSN = DeviceSN} = XID} = State) ->
    ?INFO_MSG("session replaced: UserId=~p, DeviceSN=~p, Reason=~p, InvokerDeviceSN=~p, InvokerPid=~p",
              [UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid]),
    Content = jsx:encode(#{device_token=>DeviceToken}),
    UserNotice = xsync_proto:new_user_notice(XID, Reason, Content),
    try
        send_pb_message(UserNotice, State)

    catch
        throw:_ ->
            ok
    end,
    {stop, replaced};
handle_session_replaced(UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, _DeviceToken, _State) ->
    ?WARNING_MSG("session replace skipped:UserId=~p, DeviceSN=~p, Reason=~p, InvokerDeviceSN=~p, InvokerPid=~p",
                  [UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid]),
    ok.

handle_route(From, To, MsgId, _Opts, #{xid:=To} = State) when is_integer(MsgId) ->
    MessageNotice = xsync_proto:new_message_notice(From),
    send_pb_message(MessageNotice, State);
handle_route(From, To, Metas, _Opts, #{xid:=To} = State) when is_list(Metas) ->
    Frame = xsync_proto:set_command(#'Frame'{}, dl, 'SYNC'),
    PushMeta =
        stream:apply(Frame,
                     [{xsync_proto, set_status, ['OK', undefined]},
                      {xsync_proto, set_unread_messages, [Metas, From, undefined]}]),
    send_pb_message(PushMeta, State);
handle_route(_From, _To, _MsgId, _Opts, _State) ->
    %% receive a dirty session message
    skip.
