%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_message_history_handler.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  20 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_message_history_handler).

-export([handle/1]).
-include("logger.hrl").
-include("kafka_message_history_pb.hrl").

handle(#'KafkaMessageHistory'{action = Action, from = From, to = To, mid = Mid,
                              event = Event, body = Body} = KafkaMessageHistory) ->
    ?INFO_MSG("HandleMessageHistory:~p", [xsync_proto:pr(KafkaMessageHistory)]),
    try
        handle_history(Action, From, To, Mid, Event, Body)
    catch
        C:E ->
            ?ERROR_MSG("fail to write message history: history=~p, error=~p",
                       [KafkaMessageHistory, {C,{E, erlang:get_stacktrace()}}]),
            ok
    end.

handle_history('ADD_BODY', _From, _To, Mid, _Event, Body) ->
    message_store:add_history_body(Mid, Body),
    ok;
handle_history('ADD_CHAT_INDEX', From, To, Mid, _Event, _Body) ->
    message_store:add_history_index(From, To, Mid),
    ok;
handle_history('ADD_GROUP_INDEX', From, To, Mid, _Event, _Body) ->
    message_store:add_history_index(From, To, Mid),
    ok;
handle_history('ADD_EVENT', From, To, Mid, Event, _Body) ->
    message_store:add_history_event(From, To, Event, Mid),
    ok;
handle_history('DELETE_BODY', _From, _To, Mid, _Event, _Body) ->
    message_store:delete_history_body(Mid),
    ok;
handle_history('DELETE_INDEX', From, To, Mid, _Event, _Body) ->
    message_store:delete_history_index(From, To, Mid),
    ok;
handle_history(Type, From, To, Mid, Event, Body) ->
    ?ERROR_MSG("unknown msg: type=~p, from=~p, to=~p, mid=~p,event=~p,body=~p",
               [Type, From, To, Mid, Event, Body]),
    ok.
