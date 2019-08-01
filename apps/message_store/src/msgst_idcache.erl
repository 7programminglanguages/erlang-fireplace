%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_idcache.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :
%%% Created :  14 Nov 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(msgst_idcache).

-export([
         set/4,
         get/3
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

set(User, DeviceSN, ClientMID, ServerMID) ->
    Key = redis_key(User, DeviceSN, ClientMID),
    Ttl = redis_ttl(),
    Value = ServerMID,
    Query = ["SETEX", Key, Ttl, Value],
    case redis_pool:q(?ID_CACHE_SERVICE, Query) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

get(User, DeviceSN, ClientMID) ->
    Key = redis_key(User, DeviceSN, ClientMID),
    Query = ["GET", Key],
    case redis_pool:q(?ID_CACHE_SERVICE, Query) of
        {ok, undefined} ->
            {error, <<"not found">>};
        {ok, ServerMID} ->
            {ok, erlang:binary_to_integer(ServerMID)};
        {error, Reason} ->
            {error, Reason}
    end.


%%****************************************************************************
%% internal functions
%%****************************************************************************

redis_key(User, DeviceSN, ClientMID) ->
    <<?ID_CACHE_PREFIX/binary, (integer_to_binary(User))/binary, "/", (integer_to_binary(DeviceSN))/binary, ":", (integer_to_binary(ClientMID))/binary>>.

redis_ttl() ->
    application:get_env(message_store, id_cache_ttl, ?ID_CACHE_TTL).

