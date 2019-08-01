%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 23 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(fireplace_config_sup).

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
    ConfigMgr = {fireplace_config_mgr,
                 {fireplace_config_mgr, start_link, []},
                 permanent,
                 1000,
                 worker,
                 [fireplace_config_mgr]},
    NodeRegister = {fireplace_config_node_mgr,
                    {fireplace_config_node_mgr, start_link, []},
                    permanent,
                   1000,
                   worker,
                   [fireplace_config_node_mgr]},

    {ok, { {one_for_one, 100, 10}, [ConfigMgr, NodeRegister]} }.

%%====================================================================
%% Internal functions
%%====================================================================
