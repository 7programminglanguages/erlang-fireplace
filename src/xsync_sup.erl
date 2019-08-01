%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_sup.erl
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
-module(xsync_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: #{id => Id, start => {M, F, A}}
%% Optional keys are restart, shutdown, type, modules.
%% Before OTP 18 tuples must be used to specify a child. e.g.
%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    Children = [xsync_send_msg_sup:init_spec(),
                xsync_group_notice_sup:init_spec(),
                xsync_roster_notice_sup:init_spec(),
                xsync_user_notice_sup:init_spec(),
                xsync_message_history_sup:init_spec(),
                xsync_thrift_server:init_spec(),
                xsync_status_serial:init_spec()],
    {ok, { {one_for_one, 100, 10}, Children} }.

%%====================================================================
%% Internal functions
%%====================================================================
