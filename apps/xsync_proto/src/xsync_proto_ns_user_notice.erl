%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_proto_ns_user_notice.erl
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
-module(xsync_proto_ns_user_notice).

-export([encode/1, decode/1, new/2]).

-include("usernotice_pb.hrl").

encode(#'UserNotice'{} = UserNotice) ->
    usernotice_pb:encode_msg(UserNotice).

decode(Payload)
  when is_binary(Payload) ->
    usernotice_pb:decode_msg(Payload, 'UserNotice').

new(Type, Content) ->
    #'UserNotice'{type = Type,
                  content = Content}.
