%%%-------------------------------------------------------------------------------------------------
%%% File    :  user_default.erl
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
-module(user_default).
-export([
         status/0, status/1, status/2,
         info/1, info/2,
         unread_msgs/1,
         node_info/0,
         watch/2, stop_watch/0,
         tee/3, stop_tee/0,
         to_datestr/1, to_datetime/1, to_datetimestr/1, to_datetimemsstr/1,
         to_timestamp/1, to_binary/1,
         map_pal/2, map_pal/3, foreach_pal/3,
         rpc/2, rpc_pal/2,
         rpc_process_info/2, rpc_is_process_alive/1,
         get_state/1, proc_count/3, proc_window/4, proc_tree/0,
         config_check/1, config_now/0, config_version/0, config_diff/1, config_diff/2,
         version/1, node_list/1, safe_do/2,
         eval_str/2, make_exprs/1,
         gen_code/1, sync_code/2, source/1, unload/2, check_code/1,
         trace_pid/1, trace_pid/2, trace_pids/1, trace_pids/2,
         trace_user/1, trace_user/2,
         count/2, pick/2, pick_all/2,
         ensure_integer/1, ensure_binary/1, ensure_list/1, ensure_atom/1,
         ensure_pid/1, ensure_port/1,
         string_to_term/1, machine_ids/1,
         kafka_search/4, kafka_search/5, kafka_search/7,
         kafka_range/3, kafka_range/4,
         lager_record_to_map/1,
         history_msgs/4, history_msgs/2, history_msgs/1,
         check_session/1,
         metrics/0, metrics/1, reset_metrics/0,
         gc/0
        ]).
-export([change_priority/0]).
%% internal export
-export([
         watch1/2,
         tee1/3,
         code_diff/2,
         kafka_search1/9
        ]).

-compile([{parse_transform, lager_transform}]).
-include_lib("kernel/include/file.hrl").

-define(make_bindings(B1),
        [{list_to_atom(??B1), B1}]).
-define(make_bindings(B1, B2),
        [{list_to_atom(??B1), B1},
         {list_to_atom(??B2), B2}]).
-define(make_bindings(B1, B2, B3),
        [{list_to_atom(??B1), B1},
         {list_to_atom(??B2), B2},
         {list_to_atom(??B3), B3}]).
-define(make_bindings(B1, B2, B3, B4),
        [{list_to_atom(??B1), B1},
         {list_to_atom(??B2), B2},
         {list_to_atom(??B3), B3},
         {list_to_atom(??B4), B4}]).
-define(make_bindings(B1, B2, B3, B4,B5),
        [{list_to_atom(??B1), B1},
         {list_to_atom(??B2), B2},
         {list_to_atom(??B3), B3},
         {list_to_atom(??B4), B4},
         {list_to_atom(??B5), B5}]).

-define(INFO_MSG(Format, Args), begin io:format("~s:~p: "++Format++"~n",[?MODULE, ?LINE]++Args),
                                      case whereis(lager_event) of
                                          undefined ->
                                              error_logger:info_msg("~s:~p: "++Format++"~n",[?MODULE, ?LINE]++Args);

                                          _ ->
                                              lager:info(Format, Args)
                                      end
                                end).

status() ->
    status("").
status(Map) when is_map(Map) ->
    status("", Map);
status(NodeFilter) ->
    status(NodeFilter, #{}).
status(NodeFilter, Map) ->
    Key = maps:get(key, Map, message_queue_len),
    Count = maps:get(count, Map, 20),
    Trace = maps:get(trace, Map, false),
    ProcInfos = proc_count(Key, Count, NodeFilter),
    ProcInfosView = [binary_to_list(iolist_to_binary(io_lib:format("[ ~p ] ~s",[Num,Path])))
                     ||{_,Num,Path}<-ProcInfos, Num > 0],
    case Trace of
        true ->
            TraceNum = maps:get(trace_num, Map, 100),
            TracePids = [Pid||{Pid, Num, _}<-ProcInfos, Num >= TraceNum],
            TraceInfos = map_pal(
                           fun(Pid) ->
                                   {Pid, info(Pid, trace)}
                           end, TracePids, length(TracePids));
        false ->
            TraceInfos = none
    end,
    Uptime = uptime(),
    #{memory => maps:from_list(erlang:memory()),
      proc_list => ProcInfosView,
      trace_infos => TraceInfos,
      uptime => Uptime}.


info_keys() ->
    [trace, msg_id, group, pid, machine_id, message_body, session,
     user_unread, port, node, proc_path].

info(Who) ->
    info(Who, info_keys()).

info(Who, WhatList) when is_list(WhatList) ->
    L = map_pal(
          fun(What) ->
                  try
                      {What, info(Who, What)}
                  catch
                      _:_ ->
                          {What, skip}
                  end
          end, WhatList, length(WhatList)),
    maps:from_list([{What, Value}||{What, Value}<-L, Value /= skip]);
info(Pid, trace) ->
    trace_messages(ensure_pid(Pid), 2, 1000);
info(MsgId, msg_id) ->
    MsgId1 = ensure_integer(MsgId),
    IDS = ticktick_id:explain(binary:encode_unsigned(MsgId1)),
    Timestamp = proplists:get_value(seconds, IDS) + 1417564800,
    IDS ++ [{datetime, to_datetimestr(Timestamp)}];
info(GroupId, group) ->
    {ok, Members} = msgst_group:get_group_members(ensure_group(GroupId)),
    case Members of
        [] ->
            skip;
        _ ->
            #{member_count => length(Members),
              members => Members}
    end;
info(Pid, pid) ->
    PidReal = ensure_pid(Pid),
    rpc_internal(node(PidReal), recon, info, [PidReal]);
info(MachineId, machine_id) ->
    MachineIdReal = ensure_integer(MachineId),
    case MachineId >=0 andalso MachineId < 1024 of
        true ->
            case machine_id(MachineIdReal, "") of
                [] ->
                    skip;
                L ->
                    L
            end;
        false ->
            skip
    end;
info(MsgId, message_body) ->
    {ok, Body} = message_store:read(ensure_integer(MsgId)),
    xsync_proto:get_meta_maps(xsync_proto:decode_meta(Body));
info(UserId, session) ->
    {ok, Sessions} = msgst_session:get_sessions(ensure_user(UserId)),
    case Sessions of
        [] ->
            skip;
        _ ->
            SortedSessions = lists:sort(
                             fun({_,S1}, {_,S2}) ->
                                     msgst_session:get_session_timestamp(S1)
                                         < msgst_session:get_session_timestamp(S2)
                             end, Sessions),
            [#{deviceSN=>Device,
               platform => msgst_device:int_to_platform(Device  bsr 16),
               pid=>msgst_session:get_session_pid(Session),
               is_alive=>rpc_is_process_alive(msgst_session:get_session_pid(Session)),
               time=>to_datetimemsstr(msgst_session:get_session_timestamp(Session)),
               node=>(catch node(msgst_session:get_session_pid(Session)))
              }||{Device, Session}<-SortedSessions]
    end;
info(UserId, user_unread) ->
    UserIdReal = ensure_user(UserId),
    {ok, DeviceList} = msgst_device:get_avail_device_list(UserIdReal),
    case DeviceList of
        [] ->
            skip;
        _ ->
            [#{deviceSN=>Device,
               platform => msgst_device:int_to_platform(Device bsr 16),
               unread_conversations => [#{cid=>CID, num=>Num}||{CID, Num}<-Convs, Num >0]
              }||Device<-DeviceList, {ok,Convs}<-[message_store:get_unread_conversations(UserIdReal, Device)]]
    end;
info(Port, port) ->
    PortReal = ensure_port(Port),
    rpc:call(node(PortReal), recon, port_info, [PortReal]);
info(Node, node) ->
    NodeReal = ensure_node(Node),
    rpc_internal(NodeReal, ?MODULE, node_info, []);
info(Pid, proc_path) ->
    PidReal = ensure_pid(Pid),
    proc_path_str(PidReal);
info(_Who, _What) ->
    skip.

metrics() ->
    xsync_metrics:status().

metrics(Str) ->
    xsync_metrics:status(Str).

reset_metrics() ->
    xsync_metrics:reset().

unread_msgs(UserId) ->
    UserIdReal = ensure_user(UserId),
    {ok, DeviceList} = msgst_device:get_avail_device_list(UserIdReal),
    Msgs = fun(Convs, Device) ->
                   [#{cid=>CID,
                      num=>length(Bodys),
                      total=>N,
                      msgs=>[catch xsync_proto:get_meta_maps(xsync_proto:decode_meta(Body))||Body<-Bodys]}||
                       {CID, N}<-Convs,N>0,
                       {ok,{Bodys, _}}<-[message_store:get_unread_messages(UserIdReal, Device, CID, 0)]]
           end,
    [#{device=>Device,
       unread_msgs => Msgs(Convs, Device)}
     || Device <- DeviceList, {ok, Convs}<-[message_store:get_unread_conversations(UserIdReal, Device)]].

history_msgs(UserId, CID, MsgId, Num) ->
    UserIdReal = ensure_user(UserId),
    case message_store:read_roam_message(UserIdReal, CID, MsgId, Num) of
        {error, Reason} ->
            {error, Reason};
        {ok, {Bodys,_}} ->
            {ok, [catch xsync_proto:get_meta_maps(xsync_proto:decode_meta(Body))||Body<-Bodys]}
    end.

history_msgs(UserId) ->
    history_msgs(UserId, 200).

history_msgs(UserId, Num) ->
    UserIdReal = ensure_user(UserId),
    Device = 0,
    {ok, Convs} = message_store:get_unread_conversations(UserIdReal, Device),
    {ok,[#{cid=>CID,
       num=>length(Bodys),
       total=>N,
       msgs=>[catch xsync_proto:get_meta_maps(xsync_proto:decode_meta(Body))||Body<-Bodys]}||
        {CID, N}<-Convs,
        {ok,{Bodys, _}}<-[message_store:read_roam_message(UserIdReal, CID, 0, Num)]]}.

node_info() ->
    #{node => node(),
      port_num => length(erlang:ports()),
      process_num => length(erlang:processes()),
      status => status()}.

watch(F, Sleep) ->
    Pid = spawn(fun() ->
                        watch1(F,Sleep)
                end),
    put(watching_pid, Pid),
    Pid.

watch1(F, Sleep) ->
    TimerRef = erlang:start_timer(Sleep, self(), watch_timer),
    Now = erlang:localtime(),
    TimeStr = to_datetimestr(Now),
    {Time, Value} = timer:tc(fun() -> catch F() end),
    io:format("~n============~s=====[delay:~.3fms]===============~n~p~n",
              [TimeStr, Time/1000.0, Value]),
    receive
        {timeout, TimerRef, watch_timer} ->
            ok
    end,
    ?MODULE:watch1(F, Sleep).

stop_watch() ->
    case get(watching_pid) of
        undefined ->
            skip;
        Pid ->
            exit(Pid, kill),
            erase(watching_pid)
    end.

tee(F, Sleep, FileName) ->
    Pid = spawn(fun() ->
                        tee1(F,Sleep,FileName)
                end),
    put(teeing_pid, Pid),
    Pid.

tee1(F, Sleep, FileName) ->
    TimerRef = erlang:start_timer(Sleep, self(), tee_timer),
    Now = erlang:localtime(),
    {Time, Value} = timer:tc(fun() -> catch F() end),
    NowTime = to_datetimestr(Now),
    Msg = io_lib:format("~n============~s=====[delay:~.3fms]===============~n~p~n",
                        [NowTime,Time/1000.0, Value]),
    io:format("~s~n",[Msg]),
    FileNameReal = lists:concat([FileName,".",binary_to_list(to_datestr(Now))]),
    file:write_file(FileNameReal, Msg, [append]),
    receive
        {timeout, TimerRef, tee_timer} ->
            ok
    end,
    ?MODULE:tee1(F, Sleep, FileName).

stop_tee() ->
    case get(teeing_pid) of
        undefined ->
            skip;
        Pid ->
            exit(Pid, kill),
            erase(teeing_pid)
    end.

to_integer(X) ->
    binary_to_integer(to_binary(X)).

to_binary(Atom) when is_atom(Atom) ->
    atom_to_binary(Atom, utf8);
to_binary(List) when is_list(List) ->
    try unicode:characters_to_binary(List) of
        V -> V
    catch
        _:_ ->
            list_to_binary(List)
    end;
to_binary(Binary) when is_binary(Binary) ->
    Binary.

to_datetime(Timestamp) ->
    TS = to_timestamp(Timestamp),
    GS = TS + calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    UniversalDateTime = calendar:gregorian_seconds_to_datetime(GS),
    calendar:universal_time_to_local_time(UniversalDateTime).

to_datetimestr(Timestamp) ->
    {{Year,Month,Day},{Hour,Minute,Second}} = to_datetime(Timestamp),
    iolist_to_binary(
      io_lib:format("~p-~2.2.0w-~2.2.0w ~2.2.0w:~2.2.0w:~2.2.0w",
                    [Year,Month,Day,Hour,Minute,Second])).

to_datetimemsstr(TimeStampMs) ->
    DateTimeStr = to_datetimestr(TimeStampMs div 1000),
    Ms = TimeStampMs rem 1000,
    MsStr = iolist_to_binary(io_lib:format(".~3.3.0w",[Ms])),
    <<DateTimeStr/binary,MsStr/binary>>.

to_datestr(Timestamp) ->
    {{Year,Month,Day},_} = to_datetime(Timestamp),
    iolist_to_binary(
      io_lib:format("~p-~2.2.0w-~2.2.0w",
                    [Year,Month,Day])).

to_timestamp(Bin)  when is_binary(Bin) ->
    to_timestamp(binary_to_list(Bin));
to_timestamp(Integer)  when is_integer(Integer), Integer > 2100000000 ->
    Integer div 1000;
to_timestamp(Integer) when Integer < 365 * 5 * 86400 ->
    erlang:system_time(seconds) + Integer;
to_timestamp(Integer)  when is_integer(Integer) ->
    Integer;
to_timestamp({{_,_,_},{_,_,_}}=LocalTime) ->
    [DateTime] = calendar:local_time_to_universal_time_dst(LocalTime),
    calendar:datetime_to_gregorian_seconds(DateTime)
        - calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}});
to_timestamp({_,_,_}=Date) ->
    to_timestamp(Date);
to_timestamp(List) when is_list(List) ->
    case catch list_to_integer(List) of
        Integer when is_integer(Integer) ->
            to_timestamp(Integer);
        {'EXIT',_} ->
            case string:tokens(List, ":- /._#|") of
                [Year, Month, Day, Hour, Minute, Second|_] ->
                    to_timestamp({{to_integer(Year),to_integer(Month),to_integer(Day)},
                                  {to_integer(Hour), to_integer(Minute),to_integer(Second)}});
                [Year, Month, Day] ->
                    to_timestamp({{to_integer(Year),to_integer(Month),to_integer(Day)},
                                  {0,0,0}});
                _ ->
                    throw({bad_time, List})
            end
    end.

map_pal(F, L) ->
    map_pal(F, L, 1000).
map_pal(F, L, Pal) ->
    map_pal(F, L, Pal, 1, dict:new(), []).

map_pal(F, [I|L], Pal, Idx, Dict, Values) when Pal > 0 ->
    {_,Ref} = spawn_monitor(
                fun() ->
                        exit({map_pal_result, F(I)})
                end),
    Dict1 = dict:store(Ref, Idx, Dict),
    map_pal(F, L, Pal-1, Idx+1, Dict1, Values);
map_pal(F, L, Pal, Idx, Dict, Values) ->
    case dict:is_empty(Dict) of
        true ->
            [Value||{_,Value}<-lists:sort(Values)];
        false ->
            receive
                {'DOWN', Ref, process, _, {map_pal_result, Res}} ->
                    case dict:find(Ref, Dict) of
                        error ->
                            map_pal(F, L, Pal, Idx, Dict, Values);
                        {ok, RefIdx} ->
                            Dict1 = dict:erase(Ref, Dict),
                            map_pal(F, L, Pal+1, Idx, Dict1, [{RefIdx,Res}|Values])
                    end;
                {'DOWN', _Ref, process, _, Error} ->
                    erlang:error(Error)
            end
    end.

foreach_pal(F, L, Pal) ->
    foreach_pal(F, L, Pal, 0).

foreach_pal(F, [I|L], Pal, Wait) when Pal > 0 ->
    {_,_Ref} = spawn_monitor(
                 fun() ->
                         exit({foreach_pal_result, F(I)})
                 end),
    foreach_pal(F, L, Pal-1, Wait+1);
foreach_pal(F, L, Pal, Wait)  when Wait > 0 ->
    receive
        {'DOWN', _Ref, process, _Pid, {foreach_pal_result, _Res}} ->
            foreach_pal(F, L, Pal+1, Wait-1);
        {'DOWN', _Ref, process, _Pid, Error} ->
            erlang:error(Error)
    end;
foreach_pal(_F, _L, _Pal, _Wait) ->
    ok.

version(NodeFilter) ->
    Exprs = "[{App,Release}||
                   {App,_,Release}<-application:which_applications(),
    App == xsync]",
    rpc_pal({Exprs, []},NodeFilter).

rpc(Func, NodeFilter) ->
    [{N,rpc_internal(N, Func)}||
        N<-node_list(NodeFilter)].

rpc_pal(Func, NodeFilter) ->
    NodeList = node_list(NodeFilter),
    map_pal(
      fun(N) ->
              {N,rpc_internal(N,Func)}
      end, NodeList, 20000).

node_list([Node|_]=NodeList) when is_atom(Node) ->
    NodeList;
node_list(NodeFilter) ->
    [N||N<-lists:sort(fun sort_node/2,[node()|nodes()]),
        re:run(atom_to_binary(N,utf8),to_binary(NodeFilter))/= nomatch].

rpc_internal(N, {M,F,A}) ->
    rpc_internal(N, M, F, A);
rpc_internal(N, Func) when is_function(Func) ->
    rpc_internal(N, erlang, apply, [Func, []]);
rpc_internal(N, {Str, Bindings}) ->
    Exprs = make_exprs(Str),
    rpc_internal(N, ?MODULE, eval_str, [{exprs,Exprs}, Bindings]);
rpc_internal(N, Str) ->
    Exprs = make_exprs(Str),
    rpc_internal(N, ?MODULE, eval_str, [{exprs,Exprs}, []]).

rpc_internal(Node, M, F, A) ->
    case remote_load(Node, ?MODULE) of
        ok ->
            rpc:call(Node, M, F, A);
        {badrpc, nodedown} ->
            {badrpc, nodedown}
    end.

remote_load(_Node, user_default) ->
    ok;
remote_load(Node, Module) ->
    Attrs = Module:module_info(attributes),
    case rpc:call(Node, Module, module_info, [attributes]) of
        {badrpc,nodedown} ->
            {badrpc, nodedown};
        Attrs ->
            ok;
        _ ->
            remote_load1(Node, Module)
    end.

remote_load1(Node, Module) ->
    try
        Attrs = Module:module_info(compile),
        Binary = proplists:get_value(binary_object_code, Attrs),
        NewBinary = fill_chunks_compile_info(Binary, [{binary_object_code, Binary}]),
        {module,Module} = rpc:call(Node,code,load_binary,
                                   [Module, lists:concat(["remote load from:",Module,node()]), NewBinary])
    catch
        C:E ->
            io:format("remote_load fail:Error=~p~n", [{C,E,erlang:get_stacktrace()}])
    end,
    ok.

gen_code(Module) ->
    {Module, Binary, FileName} = code:get_object_code(Module),
    NewBinary = fill_chunks_compile_info(Binary, [{binary_object_code, Binary}]),
    Data = io_lib:format("{module,~p} = code:load_binary(~p,\"load_from:~s\","
                         "zlib:uncompress(base64:decode(\"~s\"))).~n",
                             [Module, Module, FileName, base64:encode(zlib:compress(NewBinary))]),
    file:write_file(lists:concat(["/tmp/",Module,".code"]), Data).

sync_code(Module, NodeFilter) ->
    map_pal(
      fun(Node) ->
              {Node,remote_load(Node, Module)}
      end, node_list(NodeFilter),1000).

source(Module) ->
    Path = code:which(Module),
    case beam_lib:chunks(Path, [abstract_code]) of
        {ok,{_,[{abstract_code,{_,AC}}]}} ->
            ok;
        _ ->
            Attrs = Module:module_info(compile),
            Binary = proplists:get_value(binary_object_code, Attrs),
            {ok,{_,[{abstract_code,{_,AC}}]}} = beam_lib:chunks(Binary, [abstract_code])
    end,
    io:format("~ts~n",[erl_prettypr:format(erl_syntax:form_list(AC))]).

unload(Module, NodeFilter) ->
    Exprs = io_lib:format("code:purge(~p),code:delete(~p)",
                           [Module, Module]),
    [{N,rpc:call(N, ?MODULE, eval_str, [Exprs,[]])}||N<-node_list(NodeFilter)].

fill_chunks_compile_info(Binary, Attrs) ->
    {ok, _Module, Chunks} = beam_lib:all_chunks(Binary),
    OldAttrs = binary_to_term(proplists:get_value("CInf",Chunks)),
    NewChunks = lists:keyreplace("CInf", 1, Chunks, {"CInf", term_to_binary(OldAttrs++Attrs)}),
    {ok, NewBinary} = beam_lib:build_module(NewChunks),
    NewBinary.

eval_str({exprs,Exprs}, Bindings) ->
    {value,Value,_} = erl_eval:exprs(Exprs, Bindings),
    Value;
eval_str(Str, Bindings) ->
    Exprs = make_exprs(Str),
    {value,Value,_} = erl_eval:exprs(Exprs, Bindings),
    Value.

make_exprs(Str) ->
    {ok, Tokens, _} = erl_scan:string(binary_to_list(iolist_to_binary(Str))++"."),
    {ok, Exprs} = erl_parse:parse_exprs(Tokens),
    Exprs.

sort_node(A,B) ->
    partition_suffix(atom_to_list(A)) < partition_suffix(atom_to_list(B)).

uptime() ->
    to_datetimestr(erlang:system_time(milli_seconds) - element(1,statistics(wall_clock))).

get_state(Pid) ->
    get_state(Pid, 5000).
get_state(Pid, Timeout) ->
    PidReal = ensure_pid(Pid),
    sys:get_state(PidReal, Timeout).

proc_count(Key, Count, NodeFilter) ->
    ResList =
        rpc_pal({recon,proc_count, [Key, Count]}, NodeFilter),
    All = lists:append([List||{_Node, List}<-ResList, is_list(List)]),
    SubList = lists:sublist(lists:reverse(lists:keysort(2, All)), min(length(All), Count)),
    [{Pid, Value, proc_path_str(Pid)}||{Pid, Value, _Metas}<-SubList].

proc_window(Key, Count, Interval, NodeFilter) ->
    ResList =
        rpc_pal({recon,proc_window,[Key, Count, Interval]}
               , NodeFilter),
    All = lists:append([List||{_Node, List}<-ResList, is_list(List)]),
    SubList = lists:sublist(lists:reverse(lists:keysort(2, All)), min(length(All), Count)),
    [{Pid, Value, proc_path_str(Pid)}||{Pid, Value, _Metas}<-SubList].

partition_suffix(Str) ->
    IsNumber = fun(N) -> N >= $0 andalso N =< $9 end,
    L1 = lists:dropwhile(fun(N) -> not IsNumber(N) end, lists:reverse(Str)),
    L2 = lists:takewhile(IsNumber,L1),
    case L2 of
        "" -> {Str,0};
        _ -> {lists:sublist(Str, length(L1) - length(L2)),
              list_to_integer(lists:reverse(L2))}
    end.

proc_tree() ->
    Pids = erlang:processes(),
    Paths =
        lists:foldl(
          fun(Pid, Acc) ->
                  Path = proc_path_str(Pid),
                  [Path|Acc]
          end, [], Pids),
    lists:sort(Paths).

proc_path(Pid) when node(Pid) == node() ->
    case erlang:process_info(Pid, [dictionary, registered_name]) of
        undefined ->
            [dead, Pid];
        [{dictionary, D},{registered_name,RegisteredName}] ->
            Ancestors = proplists:get_value('$ancestors',D,[]),
            Name = case is_atom(RegisteredName) of
                       true -> {RegisteredName,Pid};
                       false -> Pid
                   end,
            case application:get_application(Pid) of
                undefined ->
                    App = noapp;
                {ok,App} ->
                    ok
            end,
            [App] ++ lists:reverse([Name|Ancestors])
    end;
proc_path(Pid) ->
    rpc:call(node(Pid), ?MODULE, proc_path, [Pid]).

proc_path_str(Pid) ->
    join([node(Pid)]++proc_path(Pid),"/").


join(List, Sep) ->
    string:join([
                 case E of
                     {RegName, Pid} when is_atom(RegName), is_pid(Pid) ->
                         lists:concat([ensure_list(Pid),"|",RegName]);
                     _ ->
                         ensure_list(E)
                 end||E<-List], Sep).

config_check(NodeFilter) ->
    C = config_now(),
    Str = io_lib:format("~p:config_diff(C)", [?MODULE]),
    Bindings = [{'C', C}],
    rpc_pal({Str, Bindings}, NodeFilter).

config_now() ->
    lists:sort([{App, lists:sort(L)}||{App, L}<-application_controller:prep_config_change()]).

config_version() ->
    erlang:phash2(config_now(), 100000000).

config_diff(Envs) ->
    NowEnvs = config_now(),
    config_diff(Envs, NowEnvs).
config_diff(Envs, NowEnvs) ->
    config_diff(Envs, NowEnvs, []).

config_diff([{App1, Envs1}|Rest1], [{App2, Envs2}|Rest2], M) when App1 > App2->
    M1 = [{add_application, App2, Envs2}|M],
    config_diff([{App1, Envs1}|Rest1], Rest2, M1);
config_diff([{App1, Envs1}|Rest1], [{App2, Envs2}|Rest2], M) when App1 < App2 ->
    M1 = [{del_application, App1, Envs1}|M],
    config_diff(Rest1, [{App2, Envs2}|Rest2], M1);
config_diff([{App, Envs1}|Rest1], [{App, Envs2}|Rest2], M) ->
    case app_config_diff(Envs1, Envs2, []) of
        [] ->
            M1 = M;
        AppM ->
            M1 = [{change_application, App, AppM}|M]
    end,
    config_diff(Rest1, Rest2, M1);
config_diff([{App1, Envs1}|Rest1], [], M) ->
    M1 = [{del_application, App1, Envs1}|M],
    config_diff(Rest1, [], M1);
config_diff([], [{App2, Envs2}|Rest2], M) ->
    M1 = [{add_application, App2, Envs2}|M],
    config_diff([], Rest2, M1);
config_diff([],[], M) ->
    lists:sort(M).

app_config_diff([{K1, V1}|Rest1], [{K2,V2}|Rest2], M) when K1 < K2 ->
    M1 = [{del, K1, V1}|M],
    app_config_diff(Rest1, [{K2,V2}|Rest2], M1);
app_config_diff([{K1, V1}|Rest1], [{K2,V2}|Rest2], M) when K1 > K2 ->
    M1 = [{add, K2, V2}|M],
    app_config_diff([{K1, V1}|Rest1], Rest2, M1);
app_config_diff([{K, V}|Rest1], [{K, V}|Rest2], M) ->
    app_config_diff(Rest1, Rest2, M);
app_config_diff([{K, V1}|Rest1], [{K, V2}|Rest2], M) ->
    M1 = [{changed, K, V1, V2}|M],
    app_config_diff(Rest1, Rest2, M1);
app_config_diff([{K1,V1}|Rest1], [], M) ->
    M1 = [{del, K1, V1}|M],
    app_config_diff(Rest1, [], M1);
app_config_diff([], [{K2,V2}|Rest2], M) ->
    M1 = [{add, K2, V2}|M],
    app_config_diff([], Rest2, M1);
app_config_diff([], [], M) ->
    lists:sort(M).

safe_do(Fun, Timeout) ->
    {Pid, Ref} =
        spawn_monitor(
          fun()->
                  exit({safe_do_result,Fun()})
          end),
    receive
        {'DOWN', Ref, process, Pid, {safe_do_result, Res}} ->
            Res;
        {'DOWN', Ref, process, Pid, Error} ->
            {error, Error}
    after Timeout ->
            exit(Pid,kill),
            receive
                {'DOWN', Ref, process, Pid, _} ->
                    ok
            end,
            {error, timeout}
    end.

check_code(NodeFilter) ->
    MyVsns = code_vsns(),
    Exprs = io_lib:format("
              NodeVsns = ~p:code_vsns(),
              ~p:code_diff(MyVsns, NodeVsns)",[?MODULE, ?MODULE]),
    Bindings = ?make_bindings(MyVsns),
    rpc({Exprs, Bindings}, NodeFilter).

code_vsns() ->
    lists:map(fun({Module,_}) ->
                      Attrs = Module:module_info(attributes),
                      {Module, proplists:get_value(vsn,Attrs)}
              end, lists:sort(code:all_loaded())).

code_diff(VsnList1, VsnList2) ->
    code_diff(VsnList1, VsnList2, []).

code_diff([{Module1, V1}|L1],[{Module2, V2}|L2], Acc) when Module1 < Module2 ->
    code_diff(L1, [{Module2,V2}|L2], [{Module1, V1, novsn}|Acc]);
code_diff([{Module1, V1}|L1],[{Module2,V2}|L2], Acc) when Module1 > Module2 ->
    code_diff([{Module1,V1}|L1], L2, [{Module2, novsn, V2}|Acc]);
code_diff([{Module,V}|L1], [{Module,V}|L2], Acc) ->
    code_diff(L1, L2, Acc);
code_diff([{Module,V1}|L1],[{Module,V2}|L2], Acc) ->
    code_diff(L1, L2, [{Module, V1, V2}|Acc]);
code_diff([], [], Acc) ->
    lists:reverse(Acc).

trace_user(UserAny) ->
    trace_user(UserAny, #{}).

trace_user(UserAny, Map) ->
    UserId = ensure_user(UserAny),
    {ok, Sessions} = msgst_session:get_sessions(UserId),
    Pids = [Pid||{_DeviceSN,Session}<-Sessions,
                 Pid<-[msgst_session:get_session_pid(Session)],
                 rpc_is_process_alive(Pid)],
    trace_pids(Pids, Map).

trace_pid(Pid) ->
    trace_pids([ensure_pid(Pid)]).
trace_pid(Pid, Map) ->
    trace_pids([ensure_pid(Pid)], Map).

trace_pids(Pids) ->
    trace_pids(Pids, #{}).
trace_pids(Pids, Map0) ->
    Map = maybe_file_pid(Map0),
    Master =
        proc_lib:spawn_link(
          fun() ->
                  trace_user_loop(queue:new(), Map)
          end),
    [proc_lib:spawn_link(node(Pid),
      fun() ->
              TraceFlags = maps:get(flags, Map, [send, 'receive', procs, set_on_spawn]),
              erlang:trace(Pid, true, TraceFlags),
              trace_user_redirect(Master)
      end)||Pid<-Pids].

trace_user_redirect(Master) ->
    receive
        Msg ->
            Now = erlang:system_time(milli_seconds),
            Master ! {self(), Now, Msg}
    end,
    trace_user_redirect(Master).

trace_user_loop(Q, Map) ->
    Timeout =
        case queue:is_empty(Q) of
            true ->
                infinity;
            false ->
                0
        end,
    receive
        {From, Time, Msg} = E->
            Q1 = queue:in(E, Q),
            trace_user_loop(Q1, Map)
    after Timeout ->
            {{value, {From, Time, Msg}}, Q1} = queue:out(Q),
            Msg1 = trace_format_msg(Msg),
            trace_show_msg(From, Time, Msg1, Map),
            trace_user_loop(Q1, Map)
    end.

maybe_file_pid(#{file:=FileName}=Map) ->
    Pid = proc_lib:spawn_link(
            fun() ->
                    trace_dump_file(FileName)
            end),
    Map#{dump_pid => Pid};
maybe_file_pid(Map) ->
    Map.

trace_dump_file(FileName) ->
    {ok, Fd} = file:open(FileName, [write, append]),
    trace_dump_file1(Fd).
trace_dump_file1(Fd) ->
    receive
        {dump, Str} ->
            ok = file:write(Fd, Str)
    end,
    trace_dump_file1(Fd).

trace_format_msg(Msg) ->
    try
        io_lib:print(Msg, 1, 80, 100)
    catch
        C:E ->
            io:format("Msg:~p~nError:~p~n",[Msg, {C,E,erlang:get_stacktrace()}])
    end.

trace_show_msg(From, Time, Msg, Map) ->
    Str = io_lib:format("~s ~p ======~n~s~n",[to_datetimemsstr(Time), From, Msg]),
    case Map of
        #{dump_pid:=Pid} ->
            Pid ! {dump, Str};
        _ ->
            io:format("~s",[Str])
    end.

gc() ->
    map_pal(
      fun(Pid) ->
              erlang:garbage_collect(Pid)
      end, erlang:processes(), 100).

rpc_process_info(Pid, Key) ->
    PidReal = ensure_pid(Pid),
    rpc:call(node(PidReal), erlang, process_info, [PidReal, Key]).

rpc_is_process_alive(Pid) ->
    PidReal = ensure_pid(Pid),
    rpc:call(node(PidReal), erlang, is_process_alive, [PidReal]) == true.

count(List, Fun) when is_function(Fun) ->
    Dict =
        lists:foldl(
          fun(Elem, Dict) ->
                  Key =
                      try pick(Fun, Elem) of
                          V -> V
                      catch
                          _:_ ->
                              exit
                      end,
                  case dict:find(Key, Dict) of
                      {ok, OldValue} ->
                          dict:store(Key, OldValue + 1, Dict);
                      error ->
                          dict:store(Key, 1, Dict)
                  end
          end, dict:new(), List),
    lists:reverse(lists:keysort(2,dict:to_list(Dict)));
count(List, Rule) when is_list(Rule) ->
    count(List, rule_to_function(Rule)).


rule_to_function(List) ->
    fun(Elem) ->
            lists:foldl(
              fun(Pos, L) when is_integer(Pos), is_list(L) ->
                      lists:nth(Pos, L);
                 (Pos, Tuple) when is_integer(Pos), is_tuple(Tuple) ->
                      element(Pos, Tuple);
                 ({Pos, Key}, L) when is_list(L) ->
                      lists:keyfind(Key, Pos, L)
              end, Elem, List)
    end.

pick(Fun, Term) ->
    pick(Fun, Term, 1).
pick(Fun, Term, Pos) ->
    lists:nth(Pos, pick_all(Fun, Term)).

pick_all(Fun, List) when is_list(List) ->
    case catch Fun(List) of
        true ->
            [List];
        {true, NewValue} ->
            [NewValue];
        _ ->
            lists:append([pick_all(Fun, Elem)||Elem<-List])
    end;
pick_all(Fun, Tuple) when is_tuple(Tuple) ->
    case catch Fun(Tuple) of
        true ->
            [Tuple];
        {true, NewValue} ->
            [NewValue];
        _ ->
            pick_all(Fun, tuple_to_list(Tuple))
    end;
pick_all(Fun, Map) when is_map(Map) ->
    case catch Fun(Map) of
        true ->
            [Map];
        {true, NewValue} ->
            [NewValue];
        _ ->
            pick_all(Fun, maps:to_list(Map))
    end;
pick_all(Fun, Term) ->
    case catch Fun(Term) of
        true ->
            [Term];
        {true, NewValue} ->
            [NewValue];
        _ ->
            []
    end.

ensure_integer(Int) when is_integer(Int) ->
    Int;
ensure_integer(Atom) when is_atom(Atom) ->
    list_to_integer(atom_to_list(Atom));
ensure_integer(Bin) when is_binary(Bin) ->
    binary_to_integer(Bin);
ensure_integer(List) when is_list(List) ->
    list_to_integer(List).

ensure_binary(Int) when is_integer(Int) ->
    integer_to_binary(Int);
ensure_binary(Atom) when is_atom(Atom) ->
    list_to_binary(atom_to_list(Atom));
ensure_binary(Bin) when is_binary(Bin) ->
    Bin;
ensure_binary(List) when is_list(List) ->
    list_to_binary(List);
ensure_binary(Pid) when is_pid(Pid) ->
    list_to_binary(pid_to_list(Pid)).

ensure_list(L) ->
    binary_to_list(ensure_binary(L)).

ensure_atom(Int) when is_integer(Int) ->
    list_to_atom(integer_to_list(Int));
ensure_atom(Atom) when is_atom(Atom) ->
    Atom;
ensure_atom(Bin) when is_binary(Bin) ->
    list_to_atom(binary_to_list(Bin));
ensure_atom(List) when is_list(List) ->
    list_to_atom(List).

ensure_user(Any) ->
    Int = ensure_integer(Any),
    case misc:is_user(Int) of
        true ->
            Int;
        _ ->
            throw(not_user)
    end.

ensure_group(Any) ->
    Int = ensure_integer(Any),
    case misc:is_group(Int) of
        true ->
            Int;
        _ ->
            throw(not_group)
    end.

ensure_pid(List) when is_list(List) ->
    list_to_pid(List);
ensure_pid(Pid) when is_pid(Pid) ->
    Pid;
ensure_pid(Bin) when is_binary(Bin) ->
    ensure_pid(binary_to_list(Bin)).

ensure_port(List) when is_list(List) ->
    ["#Port", NodeId, PortId] = string:tokens(List,"<>."),
    PidBin = term_to_binary(c:pid(list_to_integer(NodeId),0,0)),
    PortBin = <<131,102,(binary:part(PidBin,2,byte_size(PidBin) - 11))/binary
                ,(list_to_integer(PortId)):32,(binary:last(PidBin)):8>>,
    binary_to_term(PortBin);
ensure_port(Bin) when is_binary(Bin) ->
    ensure_port(binary_to_list(Bin));
ensure_port(Port) when is_port(Port) ->
    Port.

ensure_node(Node) ->
    NodeReal = ensure_atom(Node),
    true = lists:member(NodeReal, [node()|nodes()]),
    NodeReal.

string_to_term(String) ->
    case erl_scan:string(String++".") of
        {ok, Tokens, _} ->
            case erl_parse:parse_term(Tokens) of
                {ok, Term} -> Term;
                _Err -> undefined
            end;
        _Error ->
            undefined
    end.

flush_messages(N, Timeout) ->
    flush_messages(N, Timeout, []).
flush_messages(N, Timeout, Acc) when N > 0 ->
    receive
        Msg ->
            flush_messages(N-1, Timeout, [Msg|Acc])
    after Timeout ->
            lists:reverse(Acc)
    end;
flush_messages(_, _, Acc) ->
    lists:reverse(Acc).

trace_messages(Pid, N, Timeout) when not is_pid(Pid) ->
    trace_messages(ensure_pid(Pid), N, Timeout);
trace_messages(Pid, N, Timeout) when is_pid(Pid), node(Pid) == node() ->
    case is_process_alive(Pid) of
        true ->
            Flags = [send, 'receive', call, return_to],
            erlang:trace(Pid, true, Flags),
            Messages = flush_messages(N, Timeout),
            catch erlang:trace(Pid, false, Flags),
            Messages;
        false ->
            process_not_alive
    end;
trace_messages(Pid, N, Timeout) when is_pid(Pid) ->
    rpc_internal(node(Pid), ?MODULE, trace_messages, [Pid, N, Timeout]).

machine_id(MachineId, NodeFilter) ->
    Exprs = io_lib:format("
                S=sys:get_state(ticktick_id),element(3,S)",[]),
    [Node||{Node,MachineId1}<-rpc_pal({Exprs,[]}, NodeFilter), MachineId1 == MachineId].

machine_ids(NodeFilter) ->
    Exprs = io_lib:format("
                S=sys:get_state(ticktick_id),element(3,S)",[]),
    [#{node=>Node, machine_id=>MachineId}||
        {Node, MachineId}<-rpc_pal({Exprs,[]}, NodeFilter)].
%%========================================================
%% kafka
%%========================================================
-define(KAFKA_MAX_SEARCH, 200000000).
-define(KAFKA_MAX_SECONDS, (86400*90)).

kafka_search(Topic, TimeBase, Seconds, Str) ->
    Client = get_client_by_topic(Topic),
    {ok, PartitionCnt} = brod:get_partitions_count(Client, Topic),
    kafka_search(Topic, TimeBase, Seconds, Str, lists:seq(0,PartitionCnt-1)).
kafka_search(Topic, TimeBase, Seconds, Str, PartitionList) ->
    Client = get_client_by_topic(Topic),
    [kafka_search(Client, Topic, Partition, TimeBase, Seconds, ?KAFKA_MAX_SEARCH, Str)
     || Partition <- PartitionList].

kafka_search(Client, Topic, Partition, TimeBase, Seconds, MaxSearch, {Func, Acc}) ->
    kafka_search(Client, Topic, Partition, TimeBase, Seconds, MaxSearch, Func, Acc);
kafka_search(Client, Topic, Partition, TimeBase, Seconds, MaxSearch, Str) ->
    Func = fun(Value,Acc)->
                   ValueBin = iolist_to_binary(io_lib:format("~p",[Value])),
                   case re:run(ValueBin, to_binary(Str)) of
                       {match,_} ->
                           ?INFO_MSG("Found:msg=~p~n",[Value]),
                           [Value|Acc];
                       nomatch -> Acc
                   end
           end,
    kafka_search(Client, Topic, Partition, TimeBase, Seconds, MaxSearch, Func, []).

kafka_search(Client, Topic, Partition, TimeBase, Seconds, MaxSearch, Func, Acc)
  when Seconds =< ?KAFKA_MAX_SECONDS, MaxSearch =< ?KAFKA_MAX_SEARCH ->
    {TimeStart, TimeEnd} = timebase_to_range(TimeBase, Seconds),
    ?INFO_MSG("Search Partition: Partition=~p,TimeStart=~p,TimeEnd=~p,MaxSearch=~p",
              [Partition,to_datetimestr(TimeStart),to_datetimestr(TimeEnd), MaxSearch]),
    {StartOffset, EndOffset} = kafka_offset_range(Client, Topic, Partition, TimeStart, TimeEnd),
    kafka_search1(Client, Topic, Partition, StartOffset, EndOffset, MaxSearch, Func, Acc, 100).

kafka_search1(_Client, _Topic, _Partition, _StartOffset, _EndOffset, MaxSearch, _Func, Acc, _Sleep) when MaxSearch =< 0 ->
    {max_search_reach, lists:reverse(Acc)};
kafka_search1(_Client, _Topic, _Partition, StartOffset, EndOffset, _MaxSearch, _Func, Acc, _Sleep) when StartOffset > EndOffset ->
    {search_finish, lists:reverse(Acc)};
kafka_search1(Client, Topic, Partition, StartOffset, EndOffset, MaxSearch, Func, Acc, Sleep) ->
    {ok, Messages} = kafka_fetch(Client, Topic, Partition, StartOffset, 10000, 1, 64000),
    ?INFO_MSG("Got message:len=~p, Partition=~p, need_fetch=~p",
              [length(Messages), Partition, min(EndOffset-StartOffset,MaxSearch-length(Messages))]),
    timer:sleep(Sleep),
    {MaxOffset, Values} =
        lists:foldl(
          fun(Message, {MaxOffset, Values}) ->
                  try
                      Value = kafka_message_value(Client, Message),
                      ValueMap = lager_record_to_map(xsync_proto:pr(Value)),
                      Offset = kafka_message_offset(Message),
                      {max(MaxOffset, Offset),[ValueMap|Values]}
                  catch
                      _:_ ->
                          ?INFO_MSG("BadMsg:~p~n", [Message]),
                          {MaxOffset,Values}
                  end
          end,{StartOffset, []}, Messages),
    NewAcc = lists:foldl(Func, Acc, Values),
    ?MODULE:kafka_search1(Client, Topic, Partition, MaxOffset+1,EndOffset, MaxSearch-length(Values), Func, NewAcc, Sleep).


kafka_hosts(Client) ->
    {ok, Opts} = application:get_env(kafka_pool, Client),
    case proplists:get_value(server_list, Opts, []) of
        [] ->
            Host = proplists:get_value(host, Opts),
            Port = proplists:get_value(port, Opts, 9092),
            [{Host, Port}];
        ServerList ->
            ServerList
    end.

kafka_offset(Client, Topic, Partition, Time) ->
    Hosts = kafka_hosts(Client),
    brod:resolve_offset(Hosts,Topic,Partition,Time,[{query_api_versions,true}]).

kafka_fetch(Client, Topic, Partition, Offset) ->
    kafka_fetch(Client, Topic, Partition, Offset, 5000, 1, 4000).
kafka_fetch(Client, Topic, Partition, Offset, Timeout, MinBytes, MaxBytes) ->
    Hosts = kafka_hosts(Client),
    kafka_retry(
      fun() -> brod:fetch(Hosts,Topic, Partition, Offset, Timeout, MinBytes, MaxBytes, [{query_api_versions,true}]) end,
      1000,
      10).

kafka_retry(F, Sleep, Retry) ->
    case catch F() of
        {ok, Messages} ->
            {ok, Messages};
        Other when Retry > 1 ->
            timer:sleep(Sleep),
            ?INFO_MSG("Retry: Times=~p, reason=~p",[Retry, Other]),
            kafka_retry(F, Sleep, Retry - 1);
        Other ->
            Other
    end.

kafka_message_value(Client, Message) ->
    kafka_decode(Client, element(4,Message)).

kafka_message_offset(Message) ->
    element(2,Message).

kafka_decode(kafka_message_up, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaMessageLog');
kafka_decode(kafka_message_down, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaMessageLog');
kafka_decode(kafka_message_offline, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaMessageLog');
kafka_decode(kafka_message_ack, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaMessageLog');
kafka_decode(kafka_user_status, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaUserStatus');
kafka_decode(kafka_user_info, Bin) ->
    kafka_log_pb:decode_msg(Bin, 'KafkaUserInfo');
kafka_decode(kafka_roster_notice, Bin) ->
    kafka_notice_pb:decode_msg(Bin, 'KafkaRosterNotice');
kafka_decode(kafka_group_notice, Bin) ->
    kafka_notice_pb:decode_msg(Bin, 'KafkaGroupNotice');
kafka_decode(kafka_send_msg_chat, Bin) ->
    kafka_send_msg_pb:decode_msg(Bin, 'KafkaSendMsg');
kafka_decode(kafka_message_history, Bin) ->
    kafka_message_history_pb:decode_msg(Bin, 'KafkaMessageHistory');
kafka_decode(_, Bin) ->
    Bin.

kafka_message_time(Client, Message) ->
    case element(6, Message) of
        -1 ->
            Value = kafka_message_value(Client, Message),
            Map = lager_record_to_map(xsync_proto:pr(Value)),
            kafka_message_map_time(Map);
        Time ->
            Time div 1000
    end.

kafka_message_map_time(#{timestamp:=Timestamp}) ->
    Timestamp div 1000;
kafka_message_map_time(#{mid:=MsgId}) ->
    IDS = ticktick_id:explain(binary:encode_unsigned(MsgId)),
    proplists:get_value(seconds, IDS) + 1417564800;
kafka_message_map_time(_) ->
    -1.

kafka_offset_range(Client, Topic, Partition, TimeStart, TimeEnd) ->
    {ok, MinOffset} = kafka_offset(Client, Topic, Partition, earliest),
    {ok, MaxOffset} = kafka_offset(Client, Topic, Partition, latest),
    {StartOffset,_} = kafka_offset_range1(Client, Topic, Partition, to_timestamp(TimeStart), MinOffset, MaxOffset, 100, 100),
    {_,EndOffset} = kafka_offset_range1(Client, Topic, Partition, to_timestamp(TimeEnd), MinOffset, MaxOffset, 100, 100),
    ?INFO_MSG("Offset Range:StartOffset=~p, EndOffset=~p, Total=~p",[StartOffset, EndOffset, EndOffset-StartOffset]),
    {StartOffset, EndOffset}.

kafka_offset_range1(Client, Topic, Partition, Time, MinOffset, MaxOffset, EndSize, TryTimes) ->
    case kafka_offset(Client, Topic, Partition, Time * 1000) of
        {ok, Offset} when Offset > 0 ->
            {max(0,Offset - EndSize div 2), Offset + EndSize div 2};
        _ ->
            kafka_offset_range2(Client, Topic, Partition, Time, MinOffset, MaxOffset, EndSize, TryTimes)
    end.

kafka_offset_range2(_Client, _Topic, _Partition, _Time, MinOffset, MaxOffset, EndSize, TryTimes)
  when MaxOffset - MinOffset =< EndSize; TryTimes =< 0 ->
    {MinOffset, MaxOffset};
kafka_offset_range2(Client, Topic, Partition, Time, MinOffset, MaxOffset, EndSize, TryTimes) ->
    Offset = (MinOffset + MaxOffset) div 2,
    {ok, [Message|_]} = kafka_fetch(Client, Topic, Partition, Offset),
    Timestamp = kafka_message_time(Client, Message),
    ?INFO_MSG("Range calc: MinOffset=~p, MaxOffset=~p, Timestamp=~p, Time=~p, direction:~s",
              [MinOffset, MaxOffset, Timestamp, Time,
               case Timestamp < Time of
                   true -> "--------->>";
                   false -> "<<---------"
               end]),
    timer:sleep(100),
    case Timestamp < Time of
        true ->
            kafka_offset_range2(Client, Topic, Partition, Time, Offset, MaxOffset, EndSize, TryTimes -1);
        false ->
            kafka_offset_range2(Client, Topic, Partition, Time, MinOffset, Offset, EndSize, TryTimes -1)
    end.

kafka_range(Topic, TimeBase, Seconds) ->
    Client = get_client_by_topic(Topic),
    {ok, PartitionCnt} = brod:get_partitions_count(Client, Topic),
    kafka_range(Topic, TimeBase, Seconds, lists:seq(0,PartitionCnt-1)).
kafka_range(Topic, TimeBase, Seconds, PartitionList) ->
    Client = get_client_by_topic(Topic),
    {TimeStart, TimeEnd} = timebase_to_range(TimeBase, Seconds),
    OffsetList =
        lists:foldl(
          fun(Partition, Acc) ->
                  {StartOffset, EndOffset} = kafka_offset_range(Client, Topic, Partition, TimeStart, TimeEnd),
                  [{Partition, StartOffset, EndOffset, EndOffset-StartOffset}|Acc]
          end, [], PartitionList),
    Total = lists:sum([ED-ST||{_, ST, ED,_}<-OffsetList]),
    {Total, OffsetList}.

get_client_by_topic(Topic) ->
    Services = application:get_env(kafka_pool, services,[]),
    [Service|_] = lists:filter(
                    fun(Service) ->
                            case catch kafka_log:get_topic_by_client(Service) of
                                Topic ->
                                    true;
                                _ ->
                                    Opts = application:get_env(kafka_pool, Service, []),
                                    case proplists:get_value(topic, Opts) of
                                        Topic ->
                                            true;
                                        _ ->
                                            false
                                    end
                            end
                    end, Services),
    Service.

timebase_to_range({left, TimeBase}, Seconds) ->
    Time = to_timestamp(TimeBase),
    {Time, Time + Seconds};
timebase_to_range(TimeBase, Seconds) ->
    Time = to_timestamp(TimeBase),
    {Time - Seconds, Time + Seconds}.

lager_record_to_map({'$lager_record',Name, KVs}) ->
    maps:from_list([{'$record_name', Name}|[{K, lager_record_to_map(V)}||{K,V}<-KVs]]);
lager_record_to_map(L) when is_list(L) ->
    [lager_record_to_map(R)||R<-L];
lager_record_to_map(Tuple) when is_tuple(Tuple) ->
    list_to_tuple(lager_record_to_map(tuple_to_list(Tuple)));
lager_record_to_map(Other) ->
    Other.

change_priority(Pid, Priority) ->
    sys:replace_state(Pid,
                      fun(S) ->
                              process_flag(priority, Priority),
                              S
                      end).

change_priority() ->
    change_priority(ranch_server:get_connections_sup(xsync_server), high),
    change_priority(ticktick_id, high).

check_session(UserId) ->
    {ok, Sessions} = msgst_session:get_sessions(UserId),
    lists:map(
      fun({DeviceSN, Session}) ->
              Pid = msgst_session:get_session_pid(Session),
              case rpc_is_process_alive(Pid) of
                  false ->
                      msgst_session:close_session(UserId, DeviceSN, Pid),
                      {DeviceSN, dirty};
                  true ->
                      {DeviceSN, alive}
              end
      end, Sessions).
