%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_c2s.erl
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
-module(xsync_c2s).

-behaviour(gen_server).
-behaviour(ranch_protocol).
-include("logger.hrl").

%% API
-export([start_link/4, get_state/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-define(HIBERNATE_TIMEOUT, application:get_env(xsync, c2s_hibernate_timeout, infinity)).

%% optional field in state is after %
-type state() :: #{
                   socket => port()
                   ,transprot => atom()
                   ,encrypt_method => atom()
                   ,encrypt_key => atom() | binary()
                   % ,is_first_unread => boolean()
                   % ,xid => #'XID'{}
                   % ,compress_method => integer()
                   % ,shaper => msgst_shaper:shaper()
                  }.

%%%===================================================================
%%% API
%%%===================================================================


start_link(Ref, Socket, Transport, Opts) ->
    proc_lib:start_link(?MODULE, init, [[Ref, Socket, Transport, Opts]]).

-spec get_state(pid()) -> state().
get_state(Pid) ->
    sys:get_state(Pid).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Ref, Socket, Transport, _Opts]) ->
    ok = proc_lib:init_ack({ok, self()}),
    ok = ranch:accept_ack(Ref),
    SocketOpts = application:get_env(xsync, socket_init_opts, [{packet_size, 65536}]),
    ok = Transport:setopts(Socket, [{active, once}, {mode, binary}, {packet,4}|SocketOpts]),
    State = #{
              socket => Socket,
              transport => Transport,
              encrypt_method => 'ENCRYPT_NONE',
              encrypt_key => none
             },
    gen_server:enter_loop(?MODULE, [{hibernate_after, ?HIBERNATE_TIMEOUT}], State).

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(Info, State) ->
    try xsync_c2s_handler:handle_msg(Info, State) of
        NewState = #{} ->
            {noreply, NewState};
        {stop, Reason} ->
            {stop, normal, State#{stop_reason => Reason}};
        _ ->
            {noreply, State}
    catch
        throw: {stop, Reason} ->
            {stop, normal, State#{stop_reason => Reason}};
        Class:Reason ->
            ?ERROR_MSG("Failed to handler msg:~p, state:~p, Error:~p",
                       [Info, State, {Class, Reason, erlang:get_stacktrace()}]),
            {stop, normal, State#{stop_reason => Reason}}
    end.

terminate(Reason, State) ->
    RealReason = maps:get(stop_reason, State, Reason),
    xsync_c2s_handler:handle_terminate(RealReason, State),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
