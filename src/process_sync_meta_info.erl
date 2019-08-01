%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta_info.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  10 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_sync_meta_info).

-export([handle/2]).
-include("logger.hrl").
-include("xsync_pb.hrl").
-include("info_pb.hrl").

handle(#'Meta'{payload =
              #'Info'{
                 sdk_vsn = <<>>
                }} = _Meta, _XID) ->
    {error,{'INVALID_PARAMETER', <<"no client version">>}};
handle(#'Meta'{payload =
              #'Info'{
                 sdk_vsn = SdkVsn,
                 network = Network,
                 content = Content
                }} = _Meta, XID) ->
    ?DEBUG("client info: sdk_vsn=~p, network=~p, content=~p",
              [SdkVsn, Network, Content]),
    kafka_log:log_user_info(XID, SdkVsn, Content),
    ok.
