%%%-------------------------------------------------------------------------------------------------
%%% File    :  kafka_pool.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  17 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(kafka_pool).

-include("logger.hrl").
-include_lib("brod.hrl").
-export([start_service/1, stop_service/1, init_service_topic/2]).
-export([produce_sync/5, produce_sync/6, produce_async/5, produce_no_ack/5, fetch/1, ack/2]).
-define(SYNC_TIMEOUT, 5000).

start_service(PoolName) ->
    kafka_pool_sup:start_service(PoolName).

stop_service(PoolName) ->
    kafka_pool_sup:stop_service(PoolName).

init_service_topic(PoolName, Topic) ->
    PoolSize = kafka_pool_sup:get_pool_size(PoolName),
    lists:foreach(
      fun(Idx) ->
              Client = kafka_pool_sup:get_client_id(PoolName, Idx),
              brod:get_producer(Client, Topic, 0)
      end, lists:seq(1, PoolSize)).

produce_sync(PoolName, Topic, Partition, Key, Value) ->
    produce_sync(PoolName, Topic, Partition, Key, Value, ?SYNC_TIMEOUT).

produce_sync(PoolName, Topic, Partition, Key, Value, Timeout) when is_integer(Timeout) ->
    try choose_partition(PoolName, Topic, Partition, Key, Value) of
        {ok, ClientId, PartitionId} ->
            try brod:produce(ClientId, Topic, PartitionId, Key, Value) of
                {ok, CallRef} ->
                    receive
                        #brod_produce_reply{ call_ref = CallRef
                                           , result = brod_produce_req_acked
                                           } ->
                            ok
                    after Timeout ->
                            ?ERROR_MSG("fail to produce sync:topic=~s,partition=~p,key=~p,value=~p,error=~p",
                                       [Topic, Partition, Key, Value, timeout]),
                            {error, timeout}
                    end;
                {error, Reason} ->
                    ?ERROR_MSG("fail to produce sync:topic=~s,partition=~p,key=~p,value=~p,error=~p",
                               [Topic, Partition, Key, Value,Reason]),
                    {error, Reason}
            catch
                C:E ->
                    ?ERROR_MSG("fail to produce sync:topic=~s,partition=~p,key=~p,value=~p,error=~p",
                               [Topic, Partition, Key, Value, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C, E}}
            end;
        {error, Reason} ->
            ?ERROR_MSG("fail to produce sync:topic=~s,partition=~p,key=~p,value=~p,error=~p",
                       [Topic, Partition, Key, Value,Reason])
    catch
        C:E ->
            ?ERROR_MSG("fail to produce sync:topic=~s,partition=~p,key=~p,value=~p,error=~p",
                       [Topic, Partition, Key, Value, {C,{E,erlang:get_stacktrace()}}]),
            {error, {C, E}}
    end.

produce_async(PoolName, Topic, Partition, Key, Value) ->
    try choose_partition(PoolName, Topic, Partition, Key, Value) of
        {ok, ClientId, PartitionId} ->
            try brod:produce(ClientId, Topic, PartitionId, Key, Value) of
                {ok, _} ->
                    ok;
                {error, Reason} ->
                    ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                               [Topic, Value, Reason]),
                    {error, Reason}
            catch
                C:E ->
                    ?ERROR_MSG("fail, to produce: topic=~s, value=~p, error=~p",
                               [Topic, Value, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C,E}}
            end;
        {error, Reason} ->
            ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                       [Topic, Value, Reason]),
            {error, Reason}
    catch
        C:E ->
            ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                       [Topic, Value, {C,{E,erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

produce_no_ack(PoolName, Topic, Partition, Key, Value) ->
    try choose_partition(PoolName, Topic, Partition, Key, Value) of
        {ok, ClientId, PartitionId} ->
            try brod:produce_no_ack(ClientId, Topic, PartitionId, Key, Value) of
                ok ->
                    ok;
                {error, Reason} ->
                    ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                               [Topic, Value, Reason]),
                    {error, Reason}
            catch
                C:E ->
                    ?ERROR_MSG("fail, to produce: topic=~s, value=~p, error=~p",
                               [Topic, Value, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C,E}}
            end;
        {error, Reason} ->
            ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                       [Topic, Value, Reason]),
            {error, Reason}
    catch
        C:E ->
            ?ERROR_MSG("fail to produce: topic=~s, value=~p, error=~p",
                       [Topic, Value, {C,{E,erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

choose_partition(PoolName, _Topic, Partition, _Key, _Value) when is_integer(Partition)  ->
    ClientId = kafka_pool_sup:get_client_id(PoolName, 1),
    {ok, ClientId, Partition};
choose_partition(PoolName, Topic, PartitionFun, Key, Value) ->
    case brod:get_partitions_count(PoolName, Topic) of
        {ok, PartitionCount} ->
            PoolSize = kafka_pool_sup:get_pool_size(PoolName),
            {ok, Partition, ClientSeq} = PartitionFun(Topic, PartitionCount, Key, Value, PoolSize),
            ClientId = kafka_pool_sup:get_client_id(PoolName, ClientSeq),
            {ok, ClientId, Partition};
        {error, Reason} ->
            {error, Reason}
    end.


fetch(PoolName) ->
    try
        Reader = kafka_pool_sup:get_reader_name(PoolName),
        case kafka_pool_reader:fetch(Reader) of
            {ok, {Value, Ack}} ->
                {ok, Value, Ack};
            empty ->
                empty
        end
    catch
        C:E ->
            ?ERROR_MSG("fail to fetch:service=~p, error=~p",
                       [PoolName, {C,{E, erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

ack(PoolName, Ack) ->
    try
        Reader = kafka_pool_sup:get_reader_name(PoolName),
        kafka_pool_reader:ack(Reader, Ack),
        ok
    catch
        C:E ->
            ?ERROR_MSG("fail to ack:service=~p, error=~p",
                       [PoolName, {C,{E, erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.
