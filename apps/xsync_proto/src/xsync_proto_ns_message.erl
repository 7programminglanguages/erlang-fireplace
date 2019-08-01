%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_ns_message.erl
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
-module(xsync_proto_ns_message).

-export([encode/1, decode/1, get_maps/1]).

-include("messagebody_pb.hrl").

encode(#'MessageBody'{} = MessageBody) ->
    messagebody_pb:encode_msg(MessageBody).

decode(Payload)
  when is_binary(Payload) ->
    messagebody_pb:decode_msg(Payload, 'MessageBody').

get_maps(#'MessageBody'{type = Type,
                          from = From,
                          to = To,
                          content = Content,
                          ctype = CType,
                          operation = Operation,
                          config = Config,
                          attachment = Attachment,
                          ext = Ext,
                          qos = QoS}) ->
    OperationMap = case Operation of
                       #'MessageOperation'{type = OperType,
                                           mid = MID,
                                           xid = XID
                                          } ->
                           #{type => OperType,
                             mid => MID,
                             xid => XID};
                       _ ->
                           #{}
                   end,
    #{type => Type,
      from => From,
      to => To,
      content => Content,
      ctype => CType,
      operation => OperationMap,
      config => Config,
      attachment => Attachment,
      ext => Ext,
      qos => QoS
     }.
