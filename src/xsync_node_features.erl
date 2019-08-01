%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_node_features.erl
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
-module(xsync_node_features).

-export([get_features/1]).

get_features(FeatureKey) ->
    case application:get_env(xsync, FeatureKey, []) of
        [] ->
            [];
        Features ->
            {ok, NodeType} = application:get_env(xsync, node_type),
            NodeFeatures = application:get_env(xsync, NodeType, []),
            lists:filter(
              fun(Feature) ->
                      lists:member(Feature, NodeFeatures)
              end, Features)
    end.
