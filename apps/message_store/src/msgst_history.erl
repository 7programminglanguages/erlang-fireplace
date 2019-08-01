%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_history.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 21 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_history).
-include("kafka_message_history_pb.hrl").
-include("logger.hrl").
-export([add_body/2,
         add_chat_index/3,
         add_group_index/3,
         add_event/4,
         delete_body/1,
         delete_index/3
        ]).

add_body(MID, Body) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'ADD_BODY',
                                  mid = MID,
                                  body = Body}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

add_chat_index(From, To, MID) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'ADD_CHAT_INDEX',
                                  from = From,
                                  to = To,
                                  mid = MID}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

add_group_index(From, To, MID) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'ADD_GROUP_INDEX',
                                  from = From,
                                  to = To,
                                  mid = MID}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

add_event(From, To, Event, MID) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'ADD_EVENT',
                                  from = From,
                                  to = To,
                                  event = Event,
                                  mid = MID}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

delete_body(MID) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'DELETE_BODY',
                                  mid = MID}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

delete_index(From, To, MID) ->
    case write_to_kafka(
           #'KafkaMessageHistory'{action = 'DELETE_INDEX',
                                  from = From,
                                  to = To,
                                  mid = MID}) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

write_to_kafka(#'KafkaMessageHistory'{mid = MID}=KafkaMessageHistory) ->
    case enabled() of
        true ->
            case get_topic() of
                undefined ->
                    ok;
                Topic ->
                    try
                        TS = erlang:system_time(milli_seconds),
                        Data = kafka_message_history_pb:encode_msg(KafkaMessageHistory),
                        MIDBin = integer_to_binary(MID),
                        produce(kafka_message_history, Topic, fun partition_fun/5, MIDBin, Data, TS)
                    catch
                        C:E ->
                            ?ERROR_MSG("fail to write history to kafka:msg=~p, reason=~p",
                                       [KafkaMessageHistory, {C,{E, erlang:get_stacktrace()}}]),
                            {error, {C,E}}
                    end
            end;
        false ->
            ok
    end.

produce(PoolName, Topic, Fun, Key, Data, TS) ->
    case application:get_env(message_store, kafka_log_method, collector_async) of
        collector_async ->
            kafka_pool_produce_collector:produce_async(PoolName, Topic, Key, Data, TS, hash);
        collector_sync ->
            kafka_pool_produce_collector:produce_sync(PoolName, Topic, Key, Data, TS, hash);
        async ->
            kafka_pool:produce_async(PoolName, Topic, Fun, Key, {TS, Data});
        async_no_ack ->
            kafka_pool:produce_no_ack(PoolName, Topic, Fun, Key, {TS, Data})
    end.

get_topic() ->
    application:get_env(message_store, kafka_message_history_topic, undefined).

partition_fun(_Topic, PartitionCount, Key, _Value, ClientCount) ->
    {ok, erlang:phash2(Key, PartitionCount), rand:uniform(ClientCount)}.

enabled() ->
    application:get_env(message_store, enable_kafka_message_history_write, true).
