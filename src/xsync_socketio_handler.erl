%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_socketio_handler.erl
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
-module(xsync_socketio_handler).

-export([open/2, recv/3, handle_info/3, close/2]).

-export([messages/0, send/2, setopts/2, peername/1]).
-include("logger.hrl").


open(Pid, _Opts) ->
    NewState = #{socket => Pid,
                 transport => ?MODULE,
                 encrypt_method => 'ENCRYPT_NONE',
                 encrypt_key => none},
    ?DEBUG("init socket.io client:state=~p", [NewState]),
    {ok, NewState}.

recv(_Pid, {json, Event, Json}, State) ->
    ?DEBUG("recv json:event=~p,json=~p", [Event, Json]),
    {ok, State};

recv(Pid, {message, Event, Message}, State) ->
    ?DEBUG("recv msg:msg=~p, event=~p, pid=~p, State=~p", [Message, Event, Pid, State]),
    do_handle_msg({socketio_ok, Pid, Message}, State);

recv(_Pid, Message, State) ->
    ?DEBUG("recv unknown:msg=~p", [Message]),
    {ok, State}.

handle_info(_Pid, tick, State) ->
    ?DEBUG("Tick...", []),
    {ok, State};
handle_info(_Pid, {?MODULE, stop, _Reason}, State) ->
    {disconnect, State};
handle_info(_Pid, Info, State) ->
    ?DEBUG("socketio_info: info=~p, state=~p", [Info, State]),
    do_handle_msg(Info, State).

close(Pid, State) ->
    ?DEBUG("terminate: pid=~p, state=~p",
              [Pid, State]),
    RealReason = maps:get(stop_reason, State, unknown),
    xsync_c2s_handler:handle_terminate(RealReason, State),
    ok.

do_handle_msg(Msg, State) ->
    try xsync_c2s_handler:handle_msg(Msg, State) of
        NewState = #{} ->
            {ok, NewState};
        {stop, Reason} ->
            Delay = application:get_env(xsync, socketio_stop_delay_time, 1000),
            erlang:send_after(Delay, self(), {?MODULE, stop, Reason}),
            {ok, State#{stop_reason => Reason}};
        _ ->
            {ok, State}
    catch
        throw: {stop, Reason} ->
            {disconnect, State#{stop_reason => Reason}};
        Class:Reason ->
            ?ERROR_MSG("Failed to handler ws msg:~p, state:~p, Error:~p",
                       [Msg, State, {Class,{Reason, erlang:get_stacktrace()}}]),
            {disconnect, State#{stop_reason => Reason}}
    end.


%%%===================================================================
%%% ranch_transport callbacks
%%%===================================================================

messages() ->
    {socketio_ok, socketio_closed, socketio_error}.

setopts(_Pid, _Opts) ->
    ok.

send(Pid, Data) ->
    socketio_session:send_message(Pid, <<"frame">>, Data),
    ok.

peername(Pid) ->
    {error, not_implement}.
