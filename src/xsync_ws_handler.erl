%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_ws_handler.erl
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
-module(xsync_ws_handler).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).
-export([terminate/3]).

-export([messages/0, send/2, setopts/2, peername/1]).
-include("logger.hrl").

init(Req, State) ->
    Opts = application:get_env(xsync, websocket_opts,[]),
    OptsMap = maps:from_list(lists:keydelete(port, 1, Opts)),
    {cowboy_websocket, Req, State, OptsMap}.

websocket_init(State) ->
    NewState = #{socket => self(),
                 transport => ?MODULE,
                 encrypt_method => 'ENCRYPT_NONE',
                 encrypt_key => none},
    ?DEBUG("init ws client:state=~p", [NewState]),
    {ok, NewState}.

websocket_handle({binary, Binary}, State) ->
    ?DEBUG("recv binary:binary=~p,state=~p", [Binary,State]),
    do_handle_msg({ws_ok, self(), Binary}, State);
websocket_handle({text, Text}, State) ->
    ?DEBUG("ws_handle:skip text=~p,size=~p, state=~p", [Text, iolist_size(Text), State]),
    {ok, State};
websocket_handle(Data, State) ->
    ?DEBUG("ws_handle:skip data=~p,state=~p", [Data, State]),
    {ok, State}.

websocket_info({?MODULE, ws_send, Data}, State) ->
    ?DEBUG("send to client: data=~p, state=~p",
              [Data, State]),
    {reply, {binary, Data}, State};
websocket_info({?MODULE, stop, _Reason}, State) ->
    {stop, State};
websocket_info(Info, State) ->
    ?DEBUG("ws_info: info=~p, state=~p", [Info,State]),
    do_handle_msg(Info, State).

terminate(Reason,  Req, State) ->
    ?DEBUG("terminate: reason=~p, req=~p, state=~p",
              [Reason, Req, State]),
    RealReason = maps:get(stop_reason, State, Reason),
    xsync_c2s_handler:handle_terminate(RealReason, State),
    ok.

do_handle_msg(Msg, State) ->
    try xsync_c2s_handler:handle_msg(Msg, State) of
        NewState = #{} ->
            {ok, NewState};
        {stop, Reason} ->
            self() ! {?MODULE, stop, Reason},
            {ok, State#{stop_reason => Reason}};
        _ ->
            {ok, State}
    catch
        throw: {stop, Reason} ->
            {stop, State#{stop_reason => Reason}};
        Class:Reason ->
            ?ERROR_MSG("Failed to handler ws msg:~p, state:~p, Error:~p",
                       [Msg, State, {Class,{Reason, erlang:get_stacktrace()}}]),
            {stop, State#{stop_reason => Reason}}
    end.


%%%===================================================================
%%% ranch_transport callbacks
%%%===================================================================

messages() ->
    {ws_ok, ws_closed, ws_error}.

setopts(_Pid, _Opts) ->
    ok.

send(Pid, Data) ->
    Pid ! {?MODULE, ws_send, Data},
    ok.

peername(Pid) ->
    {error, not_implement}.
