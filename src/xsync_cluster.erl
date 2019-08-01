%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_cluster.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 27 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_cluster).
-export([register_node/0,
         get_random_node/1,
         get_node_list/1,
         node_rpc/5,
         worker_rpc/4
]).
-include("logger.hrl").

register_node() ->
    NodeRoleList = xsync_node_features:get_features(node_role_features),
    fireplace_config_node_mgr:register(node(), NodeRoleList),
    ok.

get_random_node(NodeRole) ->
    fireplace_config_node_mgr:get_random_node(NodeRole).

get_node_list(NodeRole) ->
    fireplace_config_node_mgr:get_node_list(NodeRole).

worker_rpc(M, F, A, Default) ->
    node_rpc(worker, M, F, A, Default).

node_rpc(NodeRole, M, F, A, Default) ->
    node_rpc_attempt(NodeRole, M, F, A, Default, get_retry_times()).

node_rpc_attempt(NodeRole, M, F, A, Default, MaxRetry) ->
    Node = get_random_node(NodeRole),
    case rpc_internal(Node, M, F, A) of
        {badrpc, Reason} when MaxRetry > 0 ->
            ?INFO_MSG("rpc attempt fail: node=~p, Times = ~p, MFA=~p, Reason=~p",
                      [Node, MaxRetry, {M,F,A}, Reason]),
            timer:sleep(get_retry_delay()),
            node_rpc_attempt(NodeRole, M, F, A, Default, MaxRetry-1);
        {badrpc, Reason} ->
            ?ERROR_MSG("fail to rpc:node=~p, Times = ~p, MFA=~p, Reason=~p",
                       [Node, MaxRetry, {M,F,A}, Reason]),
            Default;
        Result ->
            Result
    end.

rpc_internal(Node, M, F, A) when Node == node()->
    rpc:call(Node, M, F, A, infinity);
rpc_internal(Node, M, F, A) ->
    rpc:call(Node, M, F, A, get_rpc_timeout()).

get_retry_times() ->
    application:get_env(xsync, node_rpc_retry_times, 2).

get_retry_delay() ->
    application:get_env(xsync, node_rpc_retry_delay, 500).

get_rpc_timeout() ->
    application:get_env(xsync, node_rpc_timeout, 6000).
