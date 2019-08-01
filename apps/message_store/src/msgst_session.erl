%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_session.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  14 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_session).

-export([get_sessions/1, get_sessions/2]).

-export([open_session/3, close_session/3, replace_session/7, kick_sessions/2, kick_sessions/3]).

-export([get_session_timestamp/1, get_session_pid/1]).

-type session() ::
        {MicroSeconds::integer(), Pid::pid(), Cluster::atom(), Info::map()}.
-spec get_sessions(UserId::integer()) ->
                          {error, Reason::any()}
                              | {ok, [{DeviceSN::integer(), Session::session()}]}.
get_sessions(UserId) when is_integer(UserId) ->
    case redis_pool:q(session, [hgetall, session_key(UserId)]) of
        {ok, List} ->
            {ok,list_to_sessions(List, [])};
        {error, Reason} ->
            {error, Reason}
    end;
get_sessions(UserIdList) when is_list(UserIdList) ->
    Commands = [[hgetall, session_key(UserId)]||UserId<-UserIdList],
    case redis_pool:qp(session, Commands) of
        {error, Reason} ->
            {error, Reason};
        RetList  ->
            {ok,lists:map(
                  fun({ok, List}) ->
                          list_to_sessions(List, []);
                     ({error, _Reason}) ->
                          []
                  end, RetList)}
    end.

get_sessions(UserId, DeviceSN) ->
    case redis_pool:q(session, [hget, session_key(UserId), DeviceSN]) of
        {ok, undefined} ->
            {ok,[]};
        {ok, Value} ->
            {ok,[{DeviceSN, binary_to_term(Value)}]};
        {error, Reason} ->
            {error, Reason}
    end.

set_session(UserId, DeviceSN, Session) ->
    case redis_pool:q(session, [hset, session_key(UserId), DeviceSN, Session]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

open_session(UserId, DeviceSN, Info = #{}) ->
    Time = erlang:system_time(micro_seconds),
    Pid = self(),
    Cluster = application:get_env(xsync, cluster, none),
    SessionInfo = {Time, Pid, Cluster, Info},
    set_session(UserId, DeviceSN, SessionInfo).

close_session(UserId, DeviceSN, SessionPid) ->
    case get_sessions(UserId, DeviceSN) of
        {ok, [{DeviceSN, Session}]} ->
            case get_session_pid(Session) of
                SessionPid ->
                    redis_pool:q(session, [hdel, session_key(UserId), DeviceSN]),
                    ok;
                _ ->
                    skip
            end;
        {ok, []} ->
            skip;
        {error, Reason} ->
            {error, Reason}
    end.

replace_session(SessionPid, UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, DeviceToken) ->
    SessionPid ! {replaced, UserId, DeviceSN, Reason, InvokerDeviceSN, InvokerPid, DeviceToken}.

kick_sessions(UserId, KickReason) ->
    case get_sessions(UserId) of
        {error, Reason} ->
            {error, Reason};
        {ok, Sessions} ->
            kick_sessions_1(UserId, Sessions, KickReason)
    end.

kick_sessions(UserId, DeviceSN, KickReason) ->
    case get_sessions(UserId, DeviceSN) of
        {error, Reason} ->
            {error, Reason};
        {ok, Sessions} ->
            kick_sessions_1(UserId, Sessions, KickReason)
    end.

kick_sessions_1(UserId, Sessions, KickReason) ->
    L = lists:map(
          fun({DeviceSN, Session}) ->
                  Pid = get_session_pid(Session),
                  Result = close_session(UserId, DeviceSN, Pid),
                  replace_session(Pid, UserId, DeviceSN, KickReason, 0, self(), <<>>),
                  {DeviceSN, Result}
          end, Sessions),
    {ok, L}.

get_session_timestamp({Timestamp, _, _, _}) ->
    Timestamp.

get_session_pid({_, Pid, _, _}) ->
    Pid.

list_to_sessions([DeviceSN, Session|List], Acc) ->
    list_to_sessions(List, [{binary_to_integer(DeviceSN),
                             binary_to_term(Session)} | Acc]);
list_to_sessions([], Acc) ->
    lists:reverse(Acc).

session_key(UserId) ->
    <<"sn:", (integer_to_binary(UserId))/binary>>.
