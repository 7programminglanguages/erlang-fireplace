%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_send_msg_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  23 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_send_msg_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1, init_spec/0]).

-define(SERVER, ?MODULE).
-include("logger.hrl").

%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init_spec() ->
    {?SERVER,
    {?MODULE, start_link, []},
     permanent,
     infinity,
     supervisor,
     [?MODULE]}.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    ChildSpecs = send_msg_specs(),
    {ok, {{one_for_one, 100, 10}, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

send_msg_specs() ->
    Features = xsync_node_features:get_features(send_msg_features),
    lists:append([send_msg_spec(Feature)||Feature<-Features]).

send_msg_spec(Feature) ->
    case application:get_env(xsync, Feature, []) of
        [] ->
            ?WARNING_MSG("send msg skip feature: feature=~p", [Feature]),
            [];
        Opts ->
            NewOpts = [{name, Feature}|Opts],
            [{Feature,
             {xsync_send_msg_worker, start_link, [NewOpts]},
              permanent,
              5000,
              worker,
             [xsync_send_msg_worker]}
            ]
    end.
