%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_app.erl
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
-module(xsync_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, prep_stop/1]).
-include("logger.hrl").

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    Res = xsync_sup:start_link(),
    kafka_log:init(),
    xsync_server:start(),
    xsync_ws_server:init(),
    xsync_cluster:register_node(),
    ?INFO_MSG("Xsync app started", []),
    post_start(),
    Res.

prep_stop(State) ->
    Actions = [
               {suspend_tcp_listener,
                fun() ->
                        ranch:suspend_listener(xsync_server)
                end
               },
               {suspend_socketio_listener,
                fun() ->
                        ranch:suspend_listener(xsync_ws_server)
                end
               },
               {kick_tcp_connections,
                fun() ->
                        Connections = supervisor:which_children(ranch_server:get_connections_sup(xsync_server)),
                        kick_connections(Connections)
                end
               },
               {kick_socketio_connections,
                fun() ->
                        Connections = supervisor:which_children(socketio_session_sup),
                        kick_connections(Connections)
                end
               }
              ],
    lists:foreach(
      fun({Action, Fun}) ->
              ?INFO_MSG("PreStop Action=~p",
                        [Action]),
              Result = try
                           Fun()
                       catch
                           C:E ->
                               {error, {C,E}}
                       end,
              ?INFO_MSG("Result=~p", [Result])
      end, Actions),
    State.

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

kick_connections(Connections) ->
    Timeout = application:get_env(xsync, c2s_kick_timeout, 2000),
    Sleep = application:get_env(xsync, c2s_kick_sleep, 100),
    PalNum = application:get_env(xsync, c2s_kick_pal_num, 2000),
    misc:foreach_pal(
      fun({_,Pid,_,_}) ->
              try
                  gen_server:stop(Pid, normal, Timeout)
              catch
                  _:_ ->
                      ok
              end,
              timer:sleep(Sleep)
      end, Connections, PalNum).

post_start() ->
    Actions = [
               {change_xsync_server_priority,
                fun() ->
                        change_priority(ranch_server:get_connections_sup(xsync_server), high),
                        ok
                end
               },
               {change_ticktick_priority,
                fun() ->
                        change_priority(ticktick_id, high),
                        ok
                end
               }
              ],
    lists:foreach(
      fun({Action, Fun}) ->
              ?INFO_MSG("PostStart Action=~p",
                        [Action]),
              Result = try
                           Fun()
                       catch
                           C:E ->
                               {error, {C,E}}
                       end,
              ?INFO_MSG("Result=~p", [Result])
      end, Actions).

change_priority(Pid, Priority) ->
    sys:replace_state(Pid,
                      fun(S) ->
                              process_flag(priority, Priority),
                              S
                      end).
