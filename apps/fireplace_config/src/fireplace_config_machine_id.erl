%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_machine_id.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 24 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(fireplace_config_machine_id).
-export([register_machine_id/1,
         register_machine_id/2,
         change_machine_id/1,
         monitor_machine_id/2,
         all_ids/0]).
-include("fireplace_config.hrl").

register_machine_id(ZK) ->
    case enabled() of
        true ->
            case register_machine_id(ZK, node()) of
                {ok, MachineId} ->
                    change_machine_id(MachineId),
                    {ok, MachineId};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, disabled}
    end.

change_machine_id(MachineId) ->
    application:load(ticktick),
    OldMachineId = application:get_env(ticktick, machine_id, undefined),
    application:set_env(ticktick, machine_id, MachineId),
    case whereis(ticktick_id) of
        Pid when is_pid(Pid) ->
            case OldMachineId /= MachineId of
                true ->
                    ?INFO_MSG("ticktick restart:OldMachineId=~p, NewMachineId=~p",
                              [OldMachineId, MachineId]),
                    application:stop(ticktick),
                    application:start(ticktick);
                false ->
                    skip
            end;
        _ ->
            skip
    end.

monitor_machine_id(ZK, MachineId) ->
    Path = ids_key(MachineId),
    case erlzk:get_data(ZK, Path, self()) of
        {ok, {NodeBin,_}} ->
            Node = binary_to_atom(NodeBin, utf8),
            case Node == node() of
                true ->
                    {ok, Path};
                false ->
                    {error, machine_id_changed}
            end;
        {error, no_node} ->
            NodeBin = atom_to_binary(node(), utf8),
            {ok, _} = erlzk:create(ZK, Path, NodeBin, ephemeral),
            {ok, _} = erlzk:get_data(ZK, Path, self()),
            {ok, Path};
        {error, Reason} ->
            {error, Reason}
    end.

enabled() ->
    fireplace_config_mgr:enabled()
        andalso application:get_env(fireplace_config, enable_zookeeper_config_machine_id, true).

all_ids() ->
    ZK = fireplace_config_mgr:get_client(),
    case erlzk:get_children(ZK, ids_key()) of
        {ok, IdStrs} ->
            L = lists:map(
                  fun(IdStr) ->
                          Id = list_to_integer(IdStr),
                          case erlzk:get_data(ZK, ids_key(Id)) of
                              {ok, {NodeBin,_}} ->
                                  {Id, binary_to_atom(NodeBin, utf8)};
                              {error, Reason} ->
                                  {Id, Reason}
                          end
                  end, IdStrs),
            lists:sort(L);
        {error, Reason} ->
            {error, Reason}
    end.

register_machine_id(ZK, Node) ->
    try
        case maybe_register_advise_machine_id(ZK, Node) of
            {ok, MachineId} ->
                ?INFO_MSG("use advise id:machine_id=~p", [MachineId]),
                {ok, MachineId};
            {error, _} ->
                case maybe_register_unused_machine_id(ZK, Node) of
                    {ok, MachineId} ->
                        {ok, MachineId};
                    {error, Reason} ->
                        {error, Reason}
                end
        end
    catch
        Class:Exception ->
            ?ERROR_MSG("fail to register machine id:reason = ~p",
                       [{Class, {Exception, erlang:get_stacktrace()}}]),
            {error, {Class, Exception}}
    end.

maybe_register_unused_machine_id(ZK, Node) ->
    case get_used_ids(ZK) of
        {ok, Ids} ->
            Min = machine_id_min(),
            Max = machine_id_max(),
            StartId = get_start_id(Node, Min, Max),
            maybe_register_unused_machine_id(ZK, Node, StartId, Min, Max, Ids, Max - Min + 1);
        {error, Reason} ->
            {error, Reason}
    end.

maybe_register_unused_machine_id(ZK, Node, NowId, Min, Max, Ids, MaxRetry) when MaxRetry > 0 ->
    case lists:member(NowId, Ids) of
        true ->
            NextId = next_id(NowId, Min, Max),
            maybe_register_unused_machine_id(ZK, Node, NextId, Min, Max, Ids, MaxRetry-1);
        false ->
            NodeBin = atom_to_binary(Node, utf8),
            case can_register_id(ZK, NowId) of
                true ->
                    case erlzk:create(ZK, ids_key(NowId), NodeBin, ephemeral) of
                        {ok, _} ->
                            update_advise(ZK, Node, NowId),
                            {ok, NowId};
                        {error, node_exists} ->
                            NextId = next_id(NowId, Min, Max),
                            maybe_register_unused_machine_id(ZK, Node, NextId, Min, Max, Ids, MaxRetry-1)
                    end;
                false ->
                    NextId = next_id(NowId, Min, Max),
                    maybe_register_unused_machine_id(ZK, Node, NextId, Min, Max, Ids, MaxRetry-1)
            end
    end;
maybe_register_unused_machine_id(_,_,_,_,_,_,_) ->
    {error, no_id}.

next_id(NowId, _Min, Max) when NowId <  Max->
    NowId + 1;
next_id(_NowId, Min, _Max) ->
    Min.

can_register_id(ZK, Id) ->
    case erlzk:get_data(ZK, advise_node_key(Id)) of
        {ok, {TargetNodeBin, _}} ->
            TargetNode = binary_to_atom(TargetNodeBin, utf8),
            TargetNode == node() orelse net_adm:ping(TargetNode) /= pong;
        {error, no_node} ->
            true;
        {error, _Reason} ->
            false
    end.

update_advise(ZK, Node, Id) ->
    NodeBin = atom_to_binary(Node, utf8),
    case erlzk:create(ZK, advise_id_key(Node), integer_to_binary(Id)) of
        {ok, _} ->
            ok;
        {error, node_exists} ->
            {ok, _} = erlzk:set_data(ZK, advise_id_key(Node), integer_to_binary(Id))
    end,
    case erlzk:create(ZK, advise_node_key(Id), NodeBin) of
        {ok, _} ->
            ok;
        {error, node_exists} ->
            {ok, _} = erlzk:set_data(ZK, advise_node_key(Id), NodeBin)
    end.

maybe_register_advise_machine_id(ZK, Node) ->
    case erlzk:get_data(ZK, advise_id_key(Node)) of
        {ok, {IdBin, _}} ->
            AdviseId = binary_to_integer(IdBin),
            Min = machine_id_min(),
            Max = machine_id_max(),
            case AdviseId >= Min andalso AdviseId =< Max of
                true ->
                    case can_register_id(ZK, AdviseId) of
                        true ->
                            NodeBin = atom_to_binary(Node, utf8),
                            case erlzk:create(ZK, ids_key(AdviseId), NodeBin, ephemeral) of
                                {ok, _} ->
                                    update_advise(ZK, Node, AdviseId),
                                    {ok, AdviseId};
                                {error, node_exists} ->
                                    case erlzk:get_data(ZK, ids_key(AdviseId)) of
                                        {ok, {NowNodeBin,_}} ->
                                            case NowNodeBin == NodeBin of
                                                true ->
                                                    update_advise(ZK, Node, AdviseId),
                                                    {ok, AdviseId};
                                                false ->
                                                    {error, used}
                                            end;
                                        {error, Reason} ->
                                            {error, Reason}
                                    end;
                                {error, Reason} ->
                                    {error, Reason}
                            end;
                        false ->
                            {error, skip}
                    end;
                false ->
                    {error, no_id}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

get_used_ids(ZK) ->
    case erlzk:get_children(ZK, ids_key()) of
        {ok, IdBins} ->
            Ids = lists:map(
                    fun(IdBin) ->
                            list_to_integer(IdBin)
                    end, IdBins),
            {ok, Ids};
        {error, Reason} ->
            {error, Reason}
    end.

machine_id_min() ->
    application:get_env(fireplace_config, machine_id_min, 1).

machine_id_max() ->
    application:get_env(fireplace_config, machine_id_max, 1000).

get_start_id(Node, Min, Max) ->
    erlang:phash2(Node, Max-Min+1) + Min.

advise_id_key(Node) ->
    <<"/advise_ids/",(atom_to_binary(Node, utf8))/binary>>.

advise_node_key(Id) ->
    <<"/advise_nodes/", (integer_to_binary(Id))/binary>>.

ids_key() ->
    <<"/ids">>.

ids_key(Id) ->
    <<"/ids/", (integer_to_binary(Id))/binary>>.
