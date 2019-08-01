%%%-------------------------------------------------------------------------------------------------
%%% File    :  kafka_log.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  18 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(kafka_log).

-export([init/0,
         log_message_up/3,
         log_message_offline/3,
         log_message_down/3,
         log_message_ack/3,
         log_user_status/5,
         log_user_info/3,
         get_topic_by_client/1]).
-include("logger.hrl").
-include("kafka_log_pb.hrl").
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").
-include("groupnotice_pb.hrl").
-include("rosternotice_pb.hrl").
-include("usernotice_pb.hrl").

init() ->
    Topics = get_kafka_log_topics(),
    spawn(fun()->
                  init_kafka_topics(Topics)
          end),
    ok.

init_kafka_topics(Topics) ->
    lists:foreach(
      fun({TopicKey, Topic}) ->
              Client = get_client_by_key(TopicKey),
              kafka_pool:init_service_topic(Client, Topic),
              ?INFO_MSG("init kafka topic: topic=~s", [Topic])
      end, Topics).

log_message_up(From , To, Meta) ->
    spawn(fun() ->
                  enabled() andalso do_log_message(kafka_message_up, up, From, To, Meta)
          end).

log_message_offline(From, To, Meta) ->
   spawn(fun() ->
                 enabled() andalso do_log_message(kafka_message_offline, offline, From, To, Meta)
         end).

log_message_down(From, To, Meta) ->
    spawn(fun()->
                  enabled() andalso do_log_message(kafka_message_down, down, From, To, Meta)
          end).

log_message_ack(From, To, MsgId) ->
    spawn(fun() ->
                  enabled() andalso do_log_message(kafka_message_ack, ack, From, To, MsgId)
          end).

log_user_status(XID, Event, Reason, Ip, Version) ->
    spawn(fun()->
                  enabled() andalso do_log_user_status(kafka_user_status,XID, Event, Reason, Ip, Version)
          end),
    ok.

log_user_info(XID, SdkVsn, Content) ->
    spawn(fun() ->
                  enabled() andalso do_log_user_info(kafka_user_info, XID, SdkVsn, Content)
          end),
    ok.

do_log_user_info(PoolName, XID, SdkVsn, Content) ->
    case get_topic_by_client(PoolName) of
        undefined -> skip;
        Topic ->
            try
                TS = erlang:system_time(milli_seconds),
                Msg = make_user_info_pb(XID, SdkVsn, Content, TS),
                Data = kafka_log_pb:encode_msg(Msg),
                produce(PoolName, Topic, fun partition_fun/5, <<>>, Data, TS)
            catch
                C:E ->
                    ?ERROR_MSG("fail to log user info :Topic=~p, XID=~p,"
                               "SdkVsn=~p, Content=~p,  Error=~p",
                               [ Topic, XID, SdkVsn, Content, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C,E}}
            end
    end.

do_log_user_status(PoolName, XID, Event, Reason, Ip, SdkVsn) ->
    case get_topic_by_client(PoolName) of
        undefined -> skip;
        Topic ->
            try
                TS = erlang:system_time(milli_seconds),
                Msg = make_user_status_pb(XID, Event, Reason, Ip, SdkVsn, TS),
                Data = kafka_log_pb:encode_msg(Msg),
                produce(PoolName, Topic, fun partition_fun/5, <<>>, Data, TS)
            catch
                C:E ->
                    ?ERROR_MSG("fail to log user status:Topic=~p, XID=~p,"
                               "Event=~p, Reason=~p, ip=~p, sdkvsn=~p, Error=~p",
                               [ Topic, XID, Event, Reason, Ip, SdkVsn, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C,E}}
            end
    end.

do_log_message(PoolName, Direction, From, To, Meta) ->
    case get_topic_by_client(PoolName) of
        undefined -> skip;
        Topic ->
            try
                TS = erlang:system_time(milli_seconds),
                Msg = make_message_pb(Direction, From, To, Meta, TS),
                Data = kafka_log_pb:encode_msg(Msg),
                produce(PoolName, Topic, fun partition_fun/5, <<>>, Data, TS)
            catch
                C:E ->
                    ?ERROR_MSG("fail to log message:Topic=~p, Direction=~p, "
                               "From=~p, To=~p, Meta=~p, Error=~p",
                               [ Topic, Direction, From, To, Meta, {C,{E,erlang:get_stacktrace()}}]),
                    {error, {C,E}}
            end
    end.

partition_fun(_Topic, PartitionCount, _Key, _Value, ClientCount) ->
    {ok, rand:uniform(PartitionCount) -1, rand:uniform(ClientCount)}.

get_kafka_log_topics() ->
    application:get_env(message_store, kafka_log_topics, []).

produce(PoolName, Topic, Fun, Key, Data, TS) ->
    case application:get_env(message_store, kafka_log_method, collector_async) of
        collector_async ->
            kafka_pool_produce_collector:produce_async(PoolName, Topic, Key, Data, TS, random);
        collector_sync ->
            kafka_pool_produce_collector:produce_sync(PoolName, Topic, Key, Data, TS, random);
        async ->
            kafka_pool:produce_async(PoolName, Topic, Fun, Key, {TS, Data});
        async_no_ack ->
            kafka_pool:produce_no_ack(PoolName, Topic, Fun, Key, {TS, Data})
    end.

get_client_by_key(message_up) ->
    kafka_message_up;
get_client_by_key(message_down) ->
    kafka_message_down;
get_client_by_key(message_offline) ->
    kafka_message_offline;
get_client_by_key(message_ack) ->
    kafka_message_ack;
get_client_by_key(user_status) ->
    kafka_user_status;
get_client_by_key(user_info) ->
    kafka_user_info.

get_topic_by_client(kafka_message_up) ->
    proplists:get_value(message_up, get_kafka_log_topics());
get_topic_by_client(kafka_message_down) ->
    proplists:get_value(message_down, get_kafka_log_topics());
get_topic_by_client(kafka_message_offline) ->
    proplists:get_value(message_offline, get_kafka_log_topics());
get_topic_by_client(kafka_message_ack) ->
    proplists:get_value(message_ack, get_kafka_log_topics());
get_topic_by_client(kafka_user_status) ->
    proplists:get_value(user_status, get_kafka_log_topics());
get_topic_by_client(kafka_user_info) ->
    proplists:get_value(user_info, get_kafka_log_topics()).

make_message_pb(ack, From, To, MsgId, TS) when is_integer(MsgId) ->
    #'KafkaMessageLog'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       from = From,
       to = To,
       msg_id = MsgId
      };
make_message_pb(_, From, To, #'Meta'{ns = 'MESSAGE'} = Meta, TS) ->
    #'Meta'{id = MsgId,
            payload = #'MessageBody'{type = BodyType,
                                     operation = MsgOp,
                                     from = InnerFrom,
                                     to = InnerTo,
                                     content = Content,
                                     ctype = CType,
                                     config = Config,
                                     attachment = Attachment,
                                     ext = Ext,
                                     qos = QoS}} = Meta,
    case BodyType of
        'OPER' ->
            case MsgOp of
                #'MessageOperation'{type = MsgOpType, mid = RelatedMid} ->
                    MetaType = MsgOpType;
                _ ->
                    MetaType = 'UNKNOWN',
                    RelatedMid = undefined
            end;
        _ ->
            MetaType = BodyType,
            RelatedMid = undefined
    end,
    #'KafkaMessageLog'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       from = From,
       to = To,
       type = MetaType,
       msg_id = MsgId,
       inner_from = InnerFrom,
       inner_to = InnerTo,
       content = Content,
       ctype = CType,
       config = Config,
       attachment = Attachment,
       ext = Ext,
       related_mid = RelatedMid,
       notice_type =undefined,
       qos = QoS
      };
make_message_pb(_, From, To, #'Meta'{ns = 'GROUP_NOTICE' = MetaType} = Meta, TS) ->
    #'Meta'{id = MsgId,
            payload = #'GroupNotice'{
                         type = NoticeType,
                         from = InnerFrom,
                         to = InnerTos,
                         content = Content
                        }} = Meta,
    case InnerTos of
        [InnerTo|_] -> ok;
        _ ->
           InnerTo = undefined
    end,
    #'KafkaMessageLog'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       from = From,
       to = To,
       type = MetaType,
       msg_id = MsgId,
       inner_from = InnerFrom,
       inner_to = InnerTo,
       content = Content,
       notice_type = atom_to_binary(NoticeType, utf8)
      };
make_message_pb(_, From, To, #'Meta'{ns = 'ROSTER_NOTICE' = MetaType} = Meta, TS) ->
    #'Meta'{id = MsgId,
            payload = #'RosterNotice'{
                         type = NoticeType,
                         from = InnerFrom,
                         to = InnerTos,
                         content = Content
                        }} = Meta,
    case InnerTos of
        [InnerTo|_] -> ok;
        _ ->
           InnerTo = undefined
    end,
    #'KafkaMessageLog'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       from = From,
       to = To,
       type = MetaType,
       msg_id = MsgId,
       inner_from = InnerFrom,
       inner_to = InnerTo,
       content = Content,
       notice_type = atom_to_binary(NoticeType, utf8)
      };
make_message_pb(_, From, To, #'Meta'{ns = 'USER_NOTICE' = MetaType} = Meta, TS) ->
    #'Meta'{id = MsgId,
            payload = #'UserNotice'{
                         type = NoticeType,
                         content = Content
                        }} = Meta,
    #'KafkaMessageLog'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       from = From,
       to = To,
       type = MetaType,
       msg_id = MsgId,
       inner_from = undefined,
       inner_to = undefined,
       content = Content,
       notice_type = atom_to_binary(NoticeType, utf8)
      }.

make_user_status_pb(XID, Event, Reason, Ip, SdkVsn, TS) ->
    #'KafkaUserStatus'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       xid = XID,
       status = case Event of
                    online ->
                        'ONLINE';
                    offline ->
                        'OFFLINE'
                end,
       reason = Reason,
       ip = Ip,
       version = SdkVsn
      }.

make_user_info_pb(XID, SdkVsn, Content, TS) ->
    #'KafkaUserInfo'{
       timestamp = TS,
       node = atom_to_binary(node(), utf8),
       xid = XID,
       sdk_vsn = SdkVsn,
       content = Content
      }.

enabled() ->
    application:get_env(message_store, enable_kafka_log_write, true).
