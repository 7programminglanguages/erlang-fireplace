%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_user_notice_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 23 Jan 2019 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_user_notice_sup).

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
    ChildSpecs = user_notice_specs(),
    {ok, {{one_for_one, 100, 10}, ChildSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

user_notice_specs() ->
    Features = xsync_node_features:get_features(user_notice_features),
    lists:append([user_notice_spec(Feature)||Feature<-Features]).

user_notice_spec(Feature) ->
    case application:get_env(xsync, Feature, []) of
        [] ->
            ?WARNING_MSG("user notice skip feature: feature=~p", [Feature]),
            [];
        Opts ->
            NewOpts = [{name, Feature}|Opts],
            [{Feature,
             {xsync_user_notice_worker, start_link, [NewOpts]},
              permanent,
              5000,
              worker,
             [xsync_user_notice_worker]}
            ]
    end.
