%%%-------------------------------------------------------------------------------------------------
%%% File    :  xsync_thrift_server.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  27 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(xsync_thrift_server).

-behaviour(gen_server).

%% API
-export([start_link/0, init_spec/0]).
-export([handle_function/2, handle_error/2]).
-export([getUserMessageCount/1,
         getUserMessagesByConversation/4,
         getUserUnreadList/1,
         ackMessage/3,
         kickSessions/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).
-define(SERVICE, xsync_service_thrift).

-record(state, {server_pid}).
-include("logger.hrl").
-include("xsync_service_types.hrl").

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init_spec() ->
    {?MODULE,
    {?MODULE, start_link, []},
     permanent,
     5000,
     worker,
     [?MODULE]}.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([]) ->
    Opts = application:get_env(xsync, thrift_service, []),
    Port = proplists:get_value(port, Opts, 1731),
    SocketOpts = proplists:get_value(socket_opts, Opts, [{recv_timeout, infinity}]),
    Pid = thrift_socket_server:start([{handler, ?MODULE},
                                      {service, ?SERVICE},
                                      {port, Port},
                                      {socket_opts, SocketOpts},
                                      {framed, true}]),
    {ok, #state{server_pid = Pid}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #'state'{server_pid = Pid} =_State) ->
    thrift_socket_server:stop(Pid),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

handle_function(Function, Args) when is_atom(Function), is_tuple(Args) ->
    apply(?MODULE, Function, tuple_to_list(Args)).

handle_error(undefined, closed) ->
    ok;
handle_error(Function, Reason) ->
    ?ERROR_MSG("xsync thrift server error:function=~p,reason=~p, stacktrace=~p",
               [Function, Reason, erlang:get_stacktrace()]),
    ok.


%%%===================================================================
%%% Internal functions
%%%===================================================================

getUserMessageCount(UserId) ->
    case message_store:get_apns(UserId) of
        {error, _} ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_DB_ERROR, reason = <<"db error">>});
        {ok, Num} ->
            {reply, Num}
    end.

getUserMessagesByConversation(UserId, OppositeId, MsgIdStart, Num) ->
    MaxLen = application:get_env(xsync, message_history_max_query_len, 200),
    QueryNum = case Num >= 0 of
                   true ->
                       min(Num, MaxLen);
                   false ->
                       max(Num, -MaxLen)
               end,
    case message_store:read_roam_message(UserId, OppositeId, MsgIdStart, QueryNum) of
        {error, _Reason} ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_DB_ERROR, reason = <<"db error">>});
        {ok, {Bodys, NextMID}} ->
            IsLast = (NextMID == undefined),
            Messages = lists:filtermap(
                         fun(Body) ->
                                 try xsync_proto:decode_meta(Body) of
                                     Meta ->
                                         {true, meta_to_message(Meta)}
                                 catch
                                     _:_ ->
                                         false
                                 end
                         end, Bodys),
            {reply, #'ConversationMessages'{messages = Messages, is_last = IsLast}}
    end.

getUserUnreadList(XID) ->
    NewXID = normalize_unread_xid(XID),
    case message_store:get_unread_conversations(NewXID#'XID'.uid, NewXID#'XID'.deviceSN) of
        {error, _} ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_DB_ERROR, reason = <<"db error">>});
        {ok, ConvList} ->
            UnreadList = lists:map(
                           fun({CID, Num}) ->
                                   #'Unread'{
                                      conversationId = #'XID'{uid = CID},
                                      num = Num
                                     }
                           end, ConvList),
            {reply, UnreadList}
    end.

ackMessage(XID, CID, MsgId) ->
    check_ack_xid(XID),
    case message_store:ack_messages(XID#'XID'.uid, XID#'XID'.deviceSN, CID#'XID'.uid, MsgId) of
        {error, _} ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_DB_ERROR, reason = <<"db error">>});
        {ok, _AckMIDs} ->
            {reply, true}
    end.

kickSessions(XID) ->
    {ok, #'XID'{uid=UserId, deviceSN = DeviceSN}} = check_kick_xid(XID),
    case DeviceSN of
        0 ->
            case msgst_session:kick_sessions(UserId, 'REMOVED') of
                {error, _} ->
                    {reply, false};
                {ok, _} ->
                    {reply, true}
            end;
        _ ->
            case msgst_session:kick_sessions(UserId, DeviceSN, 'REMOVED') of
                {error, _} ->
                    {reply, false};
                {ok, _} ->
                    {reply, true}
            end
    end.

normalize_unread_xid(#'XID'{uid = UserId, deviceSN = DeviceSN} = XID) ->
    case UserId of
        undefined ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"no user id">>});
        _ ->
            case misc:is_user(UserId) of
                false ->
                    throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"bad user id">>});
                _ ->
                    NewDeviceSN = case DeviceSN of
                                      undefined ->
                                          0;
                                      _ ->
                                          DeviceSN
                                  end,
                    XID#'XID'{deviceSN = NewDeviceSN}
            end
    end.

check_ack_xid(#'XID'{uid = UserId, deviceSN = DeviceSN}) ->
    case UserId of
        undefined ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"no user id">>});
        _ ->
            case misc:is_user(UserId) of
                false ->
                    throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"bad user id">>});
                _ ->
                    case DeviceSN of
                        undefined ->
                            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                                    reason = <<"no deviceSN">>});
                        0 ->
                            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                                    reason = <<"bad deviceSN">>});
                        _ ->
                            ok
                    end
            end
    end.

check_kick_xid(#'XID'{uid = UserId, deviceSN = DeviceSN}=XID) ->
    case UserId of
        undefined ->
            throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"no user id">>});
        _ ->
            case misc:is_user(UserId) of
                false ->
                    throw(#'XSyncException'{errorCode = ?XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER,
                                    reason = <<"bad user id">>});
                _ ->
                    case DeviceSN of
                        undefined ->
                            {ok, XID#'XID'{uid=0}};
                        _ ->
                            {ok, XID}
                    end
            end
    end.

meta_to_message(Meta) ->
    #{id := MsgId,
      from := From,
      to := To,
      timestamp := Timestamp,
      payload := Payload} = xsync_proto:get_meta_maps(Meta),
    case Payload of
        #{ctype := CType0,
          content := Content,
          config := Config,
          attachment := Attachment,
          ext := Ext} ->
            CType = atom_to_binary(CType0, utf8);
        #{} ->
            CType = Content = Config = Attachment = Ext = <<>>
    end,
    #'Message'{
       from_xid = From,
       to_xid = To,
       msgId = MsgId,
       timestamp = Timestamp,
       ctype = CType,
       content = Content,
       config = Config,
       attachment = Attachment,
       ext = Ext
      }.

