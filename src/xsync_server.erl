%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_server.erl
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
-module(xsync_server).

-export([
         start/0
]).
-define(SERVER, ?MODULE).

start() ->
    {ok, TransportOpts} = application:get_env(xsync, tcp_opts),
    TransportMapOpts = maps:from_list(TransportOpts),
    ranch:start_listener(?SERVER,
                         ranch_tcp, TransportMapOpts,
                         xsync_c2s, []
                        ).
