%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_ns_roster_notice.erl
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
-module(xsync_proto_ns_roster_notice).

-export([encode/1, decode/1]).

-include("rosternotice_pb.hrl").

encode(#'RosterNotice'{} = MessageBody) ->
    rosternotice_pb:encode_msg(MessageBody).

decode(Payload)
  when is_binary(Payload) ->
    rosternotice_pb:decode_msg(Payload, 'RosterNotice').
