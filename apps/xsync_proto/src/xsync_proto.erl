%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_proto).

-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").
-include("groupnotice_pb.hrl").
-include("rosternotice_pb.hrl").
-include("info_pb.hrl").
-include("usernotice_pb.hrl").
-include("kafka_log_pb.hrl").
-include("kafka_notice_pb.hrl").
-include("kafka_send_msg_pb.hrl").
-include("kafka_message_history_pb.hrl").

-include("logger.hrl").
-export([encode/4, encode/5, decode/3, decode/4]).
-export([new_meta/4, encode_meta/1, decode_meta/1]).

-export([generate_msg_id/0]).

-export([set_command/3, set_full_sync/1]).
-export([set_status/3, get_status/1]).
-export([set_provision_xid/2]).

-export([set_sync_server_time/3, set_sync_ack_id/3,
         set_unread_conversations/2, set_unread_messages/4]).

-export([generate_meta_id/1, generate_meta_timestamp/1,
        set_meta_from/2, set_meta_to/2]).

-export([get_meta_id/1, set_meta_id/2, get_meta_from/1, get_meta_to/1, get_meta_maps/1]).

-export([os_type_to_int/1, int_to_os_type/1]).

-export([system_conversation/0, make_xid/1, make_xid/2, new_user_notice/3]).
-export([new_message_notice/1]).

-export([pr/1]).

new_meta(From, To, NS, Payload) ->
    #'Meta'{
       from = From,
       to = To,
       ns = NS,
       payload = Payload,
       id = generate_msg_id(),
       timestamp = erlang:system_time(milli_seconds)
      }.

system_conversation() ->
    make_xid(0, 0).

make_xid(UserId) ->
    #'XID'{uid = UserId}.

make_xid(UserId, DeviceSN) when is_integer(UserId) andalso is_integer(DeviceSN) ->
    #'XID'{uid = UserId,
           deviceSN = DeviceSN}.

new_user_notice(XID, Type, Content) ->
    UserNotice = xsync_proto_ns_user_notice:new(Type, Content),
    Conversation = system_conversation(),
    Meta = new_meta(Conversation, XID, 'USER_NOTICE', UserNotice),
    #'Frame'{
       command = 'SYNC',
       payload =
           #'SyncDL'{
              metas = [Meta],
              xid = Conversation
             }
      }.

new_message_notice(XID) ->
    #'Frame'{
       command = 'NOTICE',
       payload = #'Notice'{
                    xid = XID
                   }
      }.

set_command(#'Frame'{} = Frame, dl, 'SYNC') ->
    Frame#'Frame'{command = 'SYNC', payload = #'SyncDL'{}};
set_command(#'Frame'{} = Frame, ul, 'SYNC') ->
    Frame#'Frame'{command = 'SYNC', payload = #'SyncUL'{}};
set_command(#'Frame'{} = Frame, ul, 'UNREAD') ->
    Frame#'Frame'{command = 'UNREAD', payload = #'UnreadUL'{}};
set_command(#'Frame'{} = Frame, dl, 'UNREAD') ->
    Frame#'Frame'{command = 'UNREAD', payload = #'UnreadDL'{}};
set_command(#'Frame'{} = Frame, _, 'PROVISION') ->
    Frame#'Frame'{command = 'PROVISION', payload = #'Provision'{}};
set_command(#'Frame'{} = Frame, dl, 'NOTICE') ->
    Frame#'Frame'{command = 'NOTICE', payload = #'Notice'{}}.

set_status(#'Frame'{ payload = #'SyncDL'{} = SyncDL} = Frame, ErrorCode , Reason)
  when (is_binary(Reason) orelse Reason =:= undefined) ->
    Status = #'Status'{
                code = ErrorCode,
                reason = Reason },
    Frame#'Frame'{
      payload = SyncDL#'SyncDL'{ status = Status}};
set_status(#'Frame'{ payload = #'UnreadDL'{} = UnreadDL} = Frame, ErrorCode , Reason)
  when (is_binary(Reason) orelse Reason =:= undefined) ->
    Status = #'Status'{
                code = ErrorCode,
                reason = Reason },
    Frame#'Frame'{
      payload = UnreadDL#'UnreadDL'{ status = Status}};
set_status(#'Frame'{ payload = #'Provision'{} = Auth} = Frame, ErrorCode , Reason)
  when (is_binary(Reason) orelse Reason =:= undefined) ->
    Status = #'Status'{
                code = ErrorCode,
                reason = Reason },
    Frame#'Frame'{
      payload = Auth#'Provision'{ status = Status}}.

get_status(#'Frame'{payload = #'SyncDL'{status = #'Status'{
                                                   code = Code,
                                                   reason = Reason}}}) ->
    {Code, Reason};
get_status(#'Frame'{payload = #'UnreadDL'{status = #'Status'{
                                                   code = Code,
                                                   reason = Reason}}}) ->
    {Code, Reason};
get_status(#'Frame'{payload = #'Provision'{status = #'Status'{
                                                       code = Code,
                                                       reason = Reason}}}) ->
    {Code, Reason};
get_status(_) ->
    {undefined, undefined}.

set_sync_server_time(#'Frame'{payload = #'SyncDL'{} = SyncDL} = Frame, ReceiveTime, FinishTime) ->
    ResponseTime = (ReceiveTime +  FinishTime) div 2,
    Frame#'Frame'{
      payload = SyncDL#'SyncDL'{server_time = ResponseTime}
     }.

set_unread_conversations(#'Frame'{payload = #'UnreadDL'{} = UnreadDL} = Frame,
                         UnreadConversations) ->
    Unreads = lists:map(
                fun({XID, Num}) ->
                        #'ConversationUnread'{
                           xid = XID,
                           n = Num,
                           type = conv_type(XID)
                          }
                end, UnreadConversations),
    Frame#'Frame'{
      payload = UnreadDL#'UnreadDL'{
                  unread = Unreads
                 }
     }.

conv_type(XID) ->
    Uid = XID#'XID'.uid,
    case misc:is_group(Uid) of
        true ->
            'GROUPCHAT';
        false ->
            case misc:is_user(Uid) of
                true ->
                    'CHAT';
                false ->
                    'UNKNOWN'
            end
    end.

set_unread_messages(#'Frame'{payload = #'SyncDL'{} = Payload} = Frame, Metas, CID, NextKey) ->
    Frame#'Frame'{
      payload = Payload#'SyncDL'{
                  metas = Metas,
                  xid = CID,
                  next_key = NextKey
                 }
     }.

set_full_sync(#'Frame'{payload = #'SyncDL'{} = Payload} = Frame) ->
    Frame#'Frame'{
      payload = Payload#'SyncDL'{
                  is_full_sync = true
                 }
     }.

set_provision_xid(#'Frame'{ payload = #'Provision'{} = Provision} = Frame, XID) ->
    Frame#'Frame'{
      payload = Provision#'Provision'{xid=XID}
     }.

set_sync_ack_id(#'Frame'{payload = #'SyncDL'{} = SyncDL} = Frame, ClientMID, ServerMID) ->
    Frame#'Frame'{
      payload = SyncDL#'SyncDL'{
                  client_mid = ClientMID,
                  server_mid = ServerMID
                 }
     }.

generate_msg_id() ->
    {ok, Bin} = ticktick_id:id(),
    binary:decode_unsigned(Bin).

generate_meta_id(#'Meta'{} = Meta) ->
    Meta#'Meta'{id = generate_msg_id()}.

set_meta_id(#'Meta'{} = Meta, Id) ->
    Meta#'Meta'{id = Id}.

get_meta_id(#'Meta'{id = ID}) ->
    ID.

get_meta_maps(#'Meta'{id = MsgId,
                        from = From,
                        to = To,
                        timestamp = Timestamp,
                        ns = NS,
                        payload = Payload}) ->
    PayloadFields =
        case NS of
            'MESSAGE' ->
                xsync_proto_ns_message:get_maps(Payload);
            _ ->
                #{}
        end,
    #{id => MsgId,
      from => From,
      to => To,
      timestamp => Timestamp,
      ns => NS,
      payload => PayloadFields
     }.

set_meta_from(#'Meta'{} = Meta, #'XID'{} = XID) ->
    Meta#'Meta'{from = XID}.

set_meta_to(#'Meta'{} = Meta, #'XID'{} = XID) ->
    Meta#'Meta'{to = XID}.

get_meta_from(#'Meta'{from = From}) ->
    From.

get_meta_to(#'Meta'{to = To}) ->
    To.

generate_meta_timestamp(#'Meta'{} = Meta) ->
    Meta#'Meta'{timestamp = erlang:system_time(milli_seconds)}.

encode(Frame, CompressMethod, EncryptMethod, EncryptKey) ->
    encode(Frame, CompressMethod, EncryptMethod, EncryptKey, dl).
encode(#'Frame'{payload = undefined}=Frame, _CompressMethod, _EncryptMethod, _EncryptKey, _Direction) ->
    xsync_pb:encode_msg(Frame);
encode(#'Frame'{payload = Payload} = Frame, CompressMethod, EncryptMethod, EncryptKey, Direction) ->
    NewFrame = maybe_encrypt_symmetry_key(Frame#'Frame'{encrypt_method = EncryptMethod}, Direction),
    Payload1 = encode_payload(Payload),
    Payload2 = maybe_encrypt_payload(Payload1, EncryptMethod, EncryptKey),
    maybe_compress_payload(NewFrame, Payload2, CompressMethod).

decode(Data, EncryptMethod, EncryptKey) ->
    decode(Data, EncryptMethod, EncryptKey, ul).
decode(Data, EncryptMethod, EncryptKey, Direction) ->
    #'Frame'{command = Command} =
        Frame0 = xsync_pb:decode_msg(Data, 'Frame'),
    case maybe_decrypt_symmetry_key(Frame0, EncryptMethod, EncryptKey, Direction) of
        error ->
            {error, {fail_decrypt,Frame0}};
        {ok, Frame, NewEncryptMethod, NewEncryptKey} ->
            Payload = maybe_uncompress_payload(Frame),
            case xsync_proto_encrypt:decrypt(Payload, NewEncryptMethod, NewEncryptKey) of
                error ->
                    {error, {fail_decrypt,Frame}};
                Payload1 ->
                    try decode_payload(Payload1, Command, Direction) of
                        Payload2 ->
                            Frame#'Frame'{
                              payload = Payload2
                             }
                    catch
                        _:_ ->
                            {error, {fail_decode, Frame}}
                    end
            end
    end.

maybe_decrypt_symmetry_key(#'Frame'{command ='PROVISION',
                                    encrypt_method = EncryptMethod,
                                    encrypt_key = EncryptKey
                                   }=Frame, _, _, ul) ->
    case encrypt_method_enabled(EncryptMethod) of
        false ->
            {error, encrypt_method_unsupported};
        true ->
            case EncryptMethod of
                'ENCRYPT_NONE' ->
                    {ok, Frame, 'ENCRYPT_NONE', <<>>};
                _ ->
                    PrivateKeys = xsync_proto_encrypt:get_rsa_private_keys(),
                    case try_rsa_decrypt(PrivateKeys, EncryptKey) of
                        error ->
                            error;
                        NewEncryptKey ->
                            NewFrame = Frame#'Frame'{encrypt_method = EncryptMethod,
                                                     encrypt_key = NewEncryptKey},
                            {ok, NewFrame, EncryptMethod, NewEncryptKey}
                    end
            end
    end;
maybe_decrypt_symmetry_key(Frame, EncryptMethod, EncryptKey, _) ->
    {ok, Frame, EncryptMethod, EncryptKey}.

encrypt_method_enabled(EncryptMethod) ->
    Methods = application:get_env(xsync_proto, encrypt_methods, ['ENCRYPT_NONE',
                                                                 'AES_CBC_128',
                                                                 'AES_CBC_256']),
    lists:member(EncryptMethod, Methods).

maybe_encrypt_symmetry_key(#'Frame'{command ='PROVISION',
                                    encrypt_method = 'ENCRYPT_NONE'
                                   }=Frame, ul) ->
    Frame;
maybe_encrypt_symmetry_key(#'Frame'{command ='PROVISION',
                                    encrypt_key = EncryptKey
                                   }=Frame, ul) ->
    [PublicKey|_] = xsync_proto_encrypt:get_rsa_public_keys(),
    NewEncryptKey = xsync_proto_encrypt:encrypt_public(EncryptKey, PublicKey),
    Frame#'Frame'{encrypt_key = NewEncryptKey};
maybe_encrypt_symmetry_key(Frame, _Direction) ->
    Frame.

maybe_compress_payload(Frame, Payload, 'NONE'  = CompressMethod) ->
    xsync_pb:encode_msg(Frame#'Frame'{
                      compress_method = CompressMethod,
                      payload = Payload});
maybe_compress_payload(Frame, Payload, undefined  = CompressMethod) ->
    xsync_pb:encode_msg(Frame#'Frame'{
                      compress_method = CompressMethod,
                      payload = Payload});
maybe_compress_payload(Frame, Payload, 'ZLIB'  = CompressMethod) ->
    xsync_pb:encode_msg(Frame#'Frame'{
                     compress_method = CompressMethod,
                     payload = zlib:compress(Payload)}).

maybe_uncompress_payload(#'Frame'{ compress_method = 'NONE', payload = Payload}) ->
    Payload;
maybe_uncompress_payload(#'Frame'{ compress_method = undefined, payload = Payload}) ->
    Payload;
maybe_uncompress_payload(#'Frame'{ compress_method = 'ZLIB', payload = Payload}) ->
    zlib:uncompress(Payload).

maybe_encrypt_payload(Payload, EncryptMethod, EncryptKey) ->
    xsync_proto_encrypt:encrypt(Payload, EncryptMethod, EncryptKey).

try_rsa_decrypt([Key|Rest], Data) ->
    case xsync_proto_encrypt:decrypt_private(Data, Key) of
        error ->
            try_rsa_decrypt(Rest, Data);
        PlainText ->
            PlainText
    end;
try_rsa_decrypt([], _Data) ->
    error.

encode_payload(#'SyncDL'{metas = Metas} = Payload) ->
    NewMetas = lists:filtermap(
                 fun(Meta) ->
                         try
                             {true, maybe_encode_meta_payload(Meta)}
                         catch
                             Class:Reason ->
                                 ?ERROR_MSG("encode_meta error, Meta:~p, Error:~p",
                                            [Meta, {Class, Reason, erlang:get_stacktrace()}]),
                                 false
                         end
                 end, Metas),
    NewPayload = Payload#'SyncDL'{ metas = NewMetas},
    xsync_pb:encode_msg(NewPayload);
encode_payload(#'SyncUL'{meta = Meta} = Payload) ->
    NewMeta = maybe_encode_meta_payload(Meta),
    NewPayload = Payload#'SyncUL'{meta = NewMeta},
    xsync_pb:encode_msg(NewPayload);
encode_payload(Payload) when is_binary(Payload) ->
    Payload;
encode_payload(Payload) ->
    xsync_pb:encode_msg(Payload).

decode_payload(Data, 'SYNC', ul) ->
    #'SyncUL'{meta = Meta} =
        SyncUL = xsync_pb:decode_msg(Data, 'SyncUL'),
    SyncUL#'SyncUL'{
      meta = maybe_decode_meta_payload(Meta)
     };
decode_payload(Data, 'UNREAD', ul) ->
    xsync_pb:decode_msg(Data, 'UnreadUL');
decode_payload(Data, 'PROVISION', _) ->
    xsync_pb:decode_msg(Data, 'Provision');
decode_payload(Data, 'SYNC', dl) ->
    #'SyncDL'{metas = Metas} =
        SyncDL = xsync_pb:decode_msg(Data, 'SyncDL'),
    SyncDL#'SyncDL'{
      metas = lists:filtermap(
                fun(Meta) ->
                        try
                            {true, maybe_decode_meta_payload(Meta)}
                        catch
                            _:_ ->
                                false
                        end
                end, Metas)
     };
decode_payload(Data, 'UNREAD', dl) ->
    xsync_pb:decode_msg(Data, 'UnreadDL');
decode_payload(Data, 'NOTICE', _) ->
    xsync_pb:decode_msg(Data, 'Notice').

encode_meta(Meta) ->
    xsync_pb:encode_msg(maybe_encode_meta_payload(Meta)).

decode_meta(Body) ->
    Meta = xsync_pb:decode_msg(Body, 'Meta'),
    maybe_decode_meta_payload(Meta).

maybe_encode_meta_payload(undefined) ->
    undefined;
maybe_encode_meta_payload(#'Meta'{ns = 'MESSAGE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_message:encode(Payload)};
maybe_encode_meta_payload(#'Meta'{ns = 'GROUP_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_group_notice:encode(Payload)};
maybe_encode_meta_payload(#'Meta'{ns = 'ROSTER_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_roster_notice:encode(Payload)};
maybe_encode_meta_payload(#'Meta'{ns = 'USER_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_user_notice:encode(Payload)};
maybe_encode_meta_payload(#'Meta'{ns = 'INFO', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_info:encode(Payload)}.


maybe_decode_meta_payload(undefined) ->
    undefined;
maybe_decode_meta_payload(#'Meta'{ns = 'MESSAGE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_message:decode(Payload)};
maybe_decode_meta_payload(#'Meta'{ns = 'GROUP_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_group_notice:decode(Payload)};
maybe_decode_meta_payload(#'Meta'{ns = 'USER_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_user_notice:decode(Payload)};
maybe_decode_meta_payload(#'Meta'{ns = 'ROSTER_NOTICE', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_roster_notice:decode(Payload)};
maybe_decode_meta_payload(#'Meta'{ns = 'INFO', payload = Payload} = Meta) ->
    Meta#'Meta'{payload = xsync_proto_ns_info:decode(Payload)}.


os_type_to_int(OSType) ->
    xsync_pb:enum_value_by_symbol('Provision.OsType', OSType).

int_to_os_type(Int) ->
    xsync_pb:enum_symbol_by_value('Provision.OsType', Int).

pr(Frame) ->
    lager:pr(Frame, ?MODULE).
