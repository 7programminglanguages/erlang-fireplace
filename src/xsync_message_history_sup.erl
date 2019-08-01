%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_message_history_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :  Consume kafka and write message history to mysql
%%% Created :  20 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_message_history_sup).

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
    ChildSpecs = message_history_specs(),
    {ok, {{one_for_one, 100, 10}, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

message_history_specs() ->
    Features = xsync_node_features:get_features(message_history_features),
    lists:append([message_history_spec(Feature)||Feature<-Features]).

message_history_spec(Feature) ->
    case application:get_env(xsync, Feature, []) of
        [] ->
            ?WARNING_MSG("message history skip feature: feature=~p", [Feature]),
            [];
        Opts ->
            NewOpts = [{name, Feature}|Opts],
            [{Feature,
             {xsync_message_history_worker, start_link, [NewOpts]},
              permanent,
              5000,
              worker,
             [xsync_message_history_worker]}
            ]
    end.
