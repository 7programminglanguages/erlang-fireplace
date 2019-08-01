%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_client.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  8 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_client).

-behaviour(gen_server).

%% API
-export([start/1, stop/1, chat/3, chat_online/3, get_unread/1, sync_unread/3,
         groupchat/3, groupchat_online/3,
         recall/3, full_sync/4]).

-export([test_1/0, test_2/0, test_prepare/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-include("logger.hrl").
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").
-include("groupnotice_pb.hrl").
-include("rosternotice_pb.hrl").
-include("info_pb.hrl").
-inclide("usernotice_pb.hrl").

%%%===================================================================
%%% API
%%%===================================================================

start(Config) ->
    Config0 = maps:merge(#{host=> "127.0.0.1",
                             port=> 1729,
                             user_id => 8,
                             token => <<"dummytoken">>,
                             os_type => 'WEB',
                             device_guid => <<"deviceguid">>,
                             encrypt_method => 'ENCRYPT_NONE',
                             encrypt_key => <<>>}, Config),

    NewConfig = maybe_generate_encrypt_key(Config0),
    {ok, Pid} = gen_server:start(?MODULE, [NewConfig], []),
    {ok, Pid}.

stop(Pid) ->
    gen_server:stop(Pid).

chat(Pid, ToUserId, Msg) ->
    gen_server:call(Pid, {chat, ToUserId, Msg}).

chat_online(Pid, ToUserId, Msg) ->
    gen_server:call(Pid, {chat_online, ToUserId, Msg}).

groupchat(Pid, GroupId, Msg) ->
    gen_server:call(Pid, {groupchat, GroupId, Msg}).

groupchat_online(Pid, GroupId, Msg) ->
    gen_server:call(Pid, {groupchat_online, GroupId, Msg}).

get_unread(Pid) ->
    gen_server:call(Pid, get_unread).

sync_unread(Pid, CID, Key) when is_integer(CID) ->
    gen_server:call(Pid, {sync_unread, CID, Key}).

full_sync(Pid, CID, Key, Num) ->
    gen_server:call(Pid, {full_sync, CID, Key, Num}).

recall(Pid, CID, MsgId) when is_integer(CID) ->
    gen_server:call(Pid, {recall, CID, MsgId}).

test_prepare() ->
    make_group(10009,[10008,10016,10024]).

test_1() ->
    {ok, P11} = xsync_client:start(#{user_id=>10008, device_guid=><<"guid1">>}),
    {ok, P21} = xsync_client:start(#{user_id=>10016, device_guid=><<"guid1">>}),
    timer:sleep(3000),
    xsync_client:chat(P11, 10016, <<"p1 to p2 chat">>),
    xsync_client:chat(P11, 10024, <<"p1 to p2 chat">>),
    xsync_client:chat(P21, 10016, <<"p2 to p1 chat">>),
    timer:sleep(3000),
    xsync_client:groupchat(P11, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P11, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P21, 10009, <<"p2 to p1 gchat">>),
    timer:sleep(3000),
    xsync_client:get_unread(P11),
    xsync_client:get_unread(P21),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 0),
    xsync_client:sync_unread(P21, 10008, 0),
    xsync_client:sync_unread(P11, 10009, 0),
    xsync_client:sync_unread(P21, 10009, 0),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 16#ffffffff),
    xsync_client:sync_unread(P21, 10008, 16#ffffffff),
    xsync_client:sync_unread(P11, 10009, 16#ffffffff),
    xsync_client:sync_unread(P21, 10009, 16#ffffffff),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 0),
    xsync_client:sync_unread(P21, 10008, 0),
    xsync_client:sync_unread(P11, 10009, 0),
    xsync_client:sync_unread(P21, 10009, 0),
    ok.

test_2() ->
    {ok, P11} = xsync_client:start(#{user_id=>10008, device_guid=><<"guid1">>}),
    {ok, P12} = xsync_client:start(#{user_id=>10008, device_guid=><<"guid2">>}),
    {ok, P21} = xsync_client:start(#{user_id=>10016, device_guid=><<"guid1">>}),
    {ok, P22} = xsync_client:start(#{user_id=>10016, device_guid=><<"guid2">>}),
    timer:sleep(3000),
    xsync_client:chat(P11, 10016, <<"p1 to p2 chat">>),
    xsync_client:chat(P12, 10016, <<"p1 to p2 chat">>),
    xsync_client:chat(P11, 10024, <<"p1 to p2 chat">>),
    xsync_client:chat(P12, 10024, <<"p1 to p2 chat">>),
    xsync_client:chat(P21, 10016, <<"p2 to p1 chat">>),
    xsync_client:chat(P22, 10016, <<"p2 to p1 chat">>),
    timer:sleep(3000),
    xsync_client:groupchat(P11, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P12, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P11, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P12, 10009, <<"p1 to p2 gchat">>),
    xsync_client:groupchat(P21, 10009, <<"p2 to p1 gchat">>),
    xsync_client:groupchat(P22, 10009, <<"p2 to p1 gchat">>),
    timer:sleep(3000),
    xsync_client:get_unread(P11),
    xsync_client:get_unread(P21),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 0),
    xsync_client:sync_unread(P12, 10016, 0),
    xsync_client:sync_unread(P21, 10008, 0),
    xsync_client:sync_unread(P22, 10008, 0),
    xsync_client:sync_unread(P11, 10009, 0),
    xsync_client:sync_unread(P21, 10009, 0),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 16#ffffffff),
    xsync_client:sync_unread(P12, 10016, 16#ffffffff),
    xsync_client:sync_unread(P21, 10008, 16#ffffffff),
    xsync_client:sync_unread(P22, 10008, 16#ffffffff),
    xsync_client:sync_unread(P11, 10009, 16#ffffffff),
    xsync_client:sync_unread(P21, 10009, 16#ffffffff),
    timer:sleep(3000),
    xsync_client:sync_unread(P11, 10016, 0),
    xsync_client:sync_unread(P12, 10016, 0),
    xsync_client:sync_unread(P21, 10008, 0),
    xsync_client:sync_unread(P22, 10008, 0),
    xsync_client:sync_unread(P11, 10009, 0),
    xsync_client:sync_unread(P21, 10009, 0),
    ok.


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Config]) ->
    process_flag(trap_exit, true),
    self() ! connect,
    maps:get(encrypt_method,Config) /= 'ENCRYPT_NONE'
        andalso io:format("Use encrypt: Config=~p~n", [Config]),
    {ok, Config}.

handle_call({chat, ToUserId, Msg}, _From, State) ->
    ToXID = xsync_proto:make_xid(ToUserId, 0),
    send(State, make_chat_pb(ToXID, Msg, State)),
    {reply, ok, State};
handle_call({chat_online, ToUserId, Msg}, _From, State) ->
    ToXID = xsync_proto:make_xid(ToUserId, 0),
    send(State, make_chat_online_pb(ToXID, Msg, State)),
    {reply, ok, State};
handle_call({groupchat, GroupId, Msg}, _From, State) ->
    GroupXID = xsync_proto:make_xid(GroupId, 0),
    send(State, make_groupchat_pb(GroupXID, Msg, State)),
    {reply, ok, State};
handle_call({groupchat_online, GroupId, Msg}, _From, State) ->
    GroupXID = xsync_proto:make_xid(GroupId, 0),
    send(State, make_groupchat_online_pb(GroupXID, Msg, State)),
    {reply, ok, State};
handle_call(get_unread, _From, State) ->
    send(State, make_unread_pb()),
    {reply, ok, State};
handle_call({sync_unread, CID, Key}, _From, State) ->
    send(State, make_sync_unread_pb(CID, Key)),
    {reply, ok, State};
handle_call({recall, CID, MsgId}, _From, State) ->
    send(State, make_recall_pb(CID, MsgId, State)),
    {reply, ok, State};
handle_call({full_sync, CID, Key, Num}, _From, State) ->
    send(State, make_full_sync(CID, Key, Num)),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(connect, #{host:=Host, port:=Port} = State) ->
    SockOpts = [{packet, 4},
                {active, true},
                binary],
    case gen_tcp:connect(Host, Port, SockOpts) of
        {ok, Socket} ->
            self() ! auth,
            {noreply, State#{socket=>Socket}};
        {error, Reason} ->
            {stop, Reason}
    end;
handle_info(auth, State) ->
    case send(State, make_provision_pb(State)) of
        ok ->
            {noreply, State};
        {error, Reason} ->
            {stop, Reason, State}
    end;
handle_info({tcp, Socket, Data}, #{socket:=Socket} = State) ->
    Packet = decode(State, Data),
    io:format("Recv packet: ~p,~nstate: ~p~n", [pr(Packet), State]),
    handle_packet(Packet, State),
    {noreply, State};
handle_info({tcp_closed, _Socket}, State) ->
    io:format("tcp closed:~p~n", [State]),
    {stop, normal, State};
handle_info(Info, State) ->
    io:format("Recv info:~ninfo=~p,~nstate=~p~n", [Info, State]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================

send(#{socket:=Socket, encrypt_method:=EncryptMethod, encrypt_key:=EncryptKey} = _State,
     #'Frame'{} = Frame) ->
    Data = xsync_proto:encode(Frame, undefined, EncryptMethod, EncryptKey, ul),
    io:format("Send packet: ~p~n", [pr(Frame)]),
    gen_tcp:send(Socket, Data).

decode(#{encrypt_method:=EncryptMethod, encrypt_key:=EncryptKey} = _State, Data) ->
    xsync_proto:decode(Data, EncryptMethod, EncryptKey, dl).

make_provision_pb(#{encrypt_method:=EncryptMethod,
                    encrypt_key:=EncryptKey}=State) ->
    #'Frame'{
       command = 'PROVISION',
       encrypt_method = EncryptMethod,
       encrypt_key = EncryptKey,
       payload = #'Provision'{
                    xid = make_xid(State),
                    token = make_token(State),
                    os_type = make_os_type(State),
                    device_guid = make_device_guid(State)
                   }
      }.

make_chat_pb(ToXID, Msg, _State) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    meta = #'Meta'{
                              ns = 'MESSAGE',
                              id = make_unique_msg_id(),
                              to = ToXID,
                              payload = #'MessageBody'{
                                           type = 'CHAT',
                                           ctype = 'TEXT',
                                           content = Msg
                                          }
                             }
                   }
      }.

make_chat_online_pb(ToXID, Msg, _State) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    meta = #'Meta'{
                              ns = 'MESSAGE',
                              id = make_unique_msg_id(),
                              to = ToXID,
                              payload = #'MessageBody'{
                                           type = 'CHAT',
                                           ctype = 'TEXT',
                                           content = Msg,
                                           qos = 'AT_MOST_ONCE'
                                          }
                             }
                   }
      }.

make_groupchat_pb(GroupXID, Msg, _State) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    meta = #'Meta'{
                              ns = 'MESSAGE',
                              id = make_unique_msg_id(),
                              to = GroupXID,
                              payload = #'MessageBody'{
                                           type = 'GROUPCHAT',
                                           ctype = 'TEXT',
                                           content = Msg
                                          }
                             }
                   }
      }.

make_groupchat_online_pb(GroupXID, Msg, _State) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    meta = #'Meta'{
                              ns = 'MESSAGE',
                              id = make_unique_msg_id(),
                              to = GroupXID,
                              payload = #'MessageBody'{
                                           type = 'GROUPCHAT',
                                           ctype = 'TEXT',
                                           content = Msg,
                                           qos = 'AT_MOST_ONCE'
                                          }
                             }
                   }
      }.

make_unread_pb() ->
    #'Frame'{
       command = 'UNREAD',
       payload = #'UnreadUL'{
                   }
      }.

make_sync_unread_pb(CID, Key) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    xid = #'XID'{uid = CID},
                    key = Key
                   }
      }.

make_full_sync(CID, Key, Num) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    xid = #'XID'{uid = CID},
                    key = Key,
                    is_full_sync = true,
                    full_sync_num = Num
                   }
      }.

make_recall_pb(CID, MsgId, _State) ->
    #'Frame'{
       command = 'SYNC',
       payload = #'SyncUL'{
                    meta = #'Meta'{
                              to = #'XID'{uid = CID},
                              id = make_unique_msg_id(),
                              ns = 'MESSAGE',
                              payload = #'MessageBody'{
                                           type = 'OPER',
                                           operation = #'MessageOperation'{
                                                          type = 'RECALL',
                                                          mid = MsgId
                                                         }
                                          }
                             }
                   }
      }.

make_xid(#{user_id:=UserId}=State) ->
    DeviceSN = maps:get(deviceSN, State, 0),
    #'XID'{uid = UserId, deviceSN = DeviceSN}.

make_token(#{token:=Token}) ->
    Token.

make_os_type(#{os_type:=OSType}) ->
    OSType.

make_device_guid(#{device_guid:=DeviceGUID}) ->
    DeviceGUID.

pr(Record) ->
    to_map(lager:pr(Record, ?MODULE)).
to_map({'$lager_record', Name, KVs}) ->
    maps:from_list([{'__name__',Name}]++[{K, to_map(V)}||{K,V}<-KVs]);
to_map(L) when is_list(L) ->
    [to_map(E)||E<-L];
to_map(Tuple) when is_tuple(Tuple) ->
    list_to_tuple(to_map(tuple_to_list(Tuple)));
to_map(O) ->
    O.

make_unique_msg_id() ->
    erlang:system_time(milli_seconds) * 1000000 + rand:uniform(1000000).

handle_packet(_Packet, _State) ->
    ok.

make_group(GroupId, UserIdList) ->
    [begin
         redis_pool:q(group, [zadd, <<"g:users:",(integer_to_binary(GroupId))/binary>>,
                          erlang:system_time(milli_seconds), UserId]),
         message_store:init_group_index(GroupId, UserId)
     end
     || UserId <- UserIdList].

maybe_generate_encrypt_key(#{encrypt_method:='ENCRYPT_NONE'}=Config) ->
    Config;
maybe_generate_encrypt_key(#{encrypt_method:='AES_CBC_128', encrypt_key:=<<>>}=Config) ->
    Key = crypto:strong_rand_bytes(16),
    Config#{encrypt_key:=Key};
maybe_generate_encrypt_key(#{encrypt_method:='AES_CBC_256', encrypt_key:=<<>>}=Config) ->
    Key = crypto:strong_rand_bytes(32),
    Config#{encrypt_key:=Key};
maybe_generate_encrypt_key(Config) ->
    Config.
