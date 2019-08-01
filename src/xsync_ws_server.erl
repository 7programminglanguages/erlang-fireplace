%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_ws_server.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  19 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_ws_server).

-export([init/0]).
-include("logger.hrl").
init() ->
    Opts = application:get_env(xsync, websocket_opts,[]),
    Port = proplists:get_value(port, Opts, 1730),
    WSPath = application:get_env(xsync, websocket_path, "/"),
    SocketIOOpts = application:get_env(xsync, socketio_opts, [{heartbeat, 25000},
                                                              {heartbeat_timeout, 60000},
                                                              {session_timeout, 60000}]),
    SocketIOSession = socketio_session:configure(SocketIOOpts ++
                                                     [{callback, xsync_socketio_handler},
                                                      {protocol, socketio_data_protocol_v3}]),
    Dispatch = cowboy_router:compile(
                 [
                  {'_', [
                         {"/socket.io/[...]", socketio_handler, [SocketIOSession]},
                         {WSPath, xsync_ws_handler, []}
                        ]}
                 ]),
    {ok, _} = cowboy:start_clear(?MODULE, [{port, Port}],
                                 #{
                                   env => #{dispatch => Dispatch}
                                  }),
    ?INFO_MSG("websocket server is started on ~p", [Port]),
    ok.
