%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_ns_group_notice.erl
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
-module(xsync_proto_ns_group_notice).

-export([encode/1, decode/1]).

-include("groupnotice_pb.hrl").

encode(#'GroupNotice'{} = GroupNotice) ->
    groupnotice_pb:encode_msg(GroupNotice).

decode(Payload)
  when is_binary(Payload) ->
    groupnotice_pb:decode_msg(Payload, 'GroupNotice').
