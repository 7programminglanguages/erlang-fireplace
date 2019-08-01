%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_ns_info.erl
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
-module(xsync_proto_ns_info).

-export([encode/1, decode/1]).

-include("info_pb.hrl").

encode(#'Info'{} = Info) ->
    info_pb:encode_msg(Info).

decode(Payload)
  when is_binary(Payload) ->
    info_pb:decode_msg(Payload, 'Info').
