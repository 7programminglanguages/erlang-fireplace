%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_apns.erl
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


-module(msgst_apns).

-export([
         incr/2,
         delete/1,
         get/1
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

incr(UserList, Num) when is_list(UserList) ->
    Queries = lists:map(fun(User) -> make_incr_query(User, Num) end, UserList),
    case redis_pool:qp(?REDIS_APNS_SERVICE, Queries) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end;
incr(User, Num) ->
    Query = make_incr_query(User, Num),
    case redis_pool:q(?REDIS_APNS_SERVICE, Query) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end.

delete(User) ->
    Query = make_delete_query(User),
    case redis_pool:q(?REDIS_APNS_SERVICE, Query) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            ok
    end.

get(User) ->
    Query = make_get_query(User),
    case redis_pool:q(?REDIS_APNS_SERVICE, Query) of
        {error, Reason} ->
            {error, Reason};
        {ok, undefined} ->
            {ok, 0};
        {ok, Num} ->
            {ok, binary_to_integer(Num)}
    end.

%%****************************************************************************
%% internal functions
%%****************************************************************************

make_incr_query(User, Num) ->
    Key = redis_key(User),
    ["INCRBY", Key, Num].

make_delete_query(User) ->
    Key = redis_key(User),
    ["DEL", Key].

make_get_query(User) ->
    Key = redis_key(User),
    ["GET", Key].

redis_key(User) ->
    <<?REDIS_APNS_KEY_PREFIX/binary, (integer_to_binary(User))/binary>>.


