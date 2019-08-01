%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_node_mgr.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 26 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(fireplace_config_node_mgr).

-behaviour(gen_server).

%% API
-export([start_link/0, register/2,
         monitor_node_register/3,
         monitor_node_list_change/2,
         get_random_node/1,
         get_node_role/0,
         get_node_list/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).
-include("fireplace_config.hrl").
-define(SERVER, ?MODULE).
-define(NODE_TAB, ?MODULE).
-record(state, {
                node,
                type_list = [],
                ref
}).

register(Node, TypeList) ->
    gen_server:call(?SERVER, {register, Node, TypeList}).

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

enabled() ->
    fireplace_config_mgr:enabled()
        andalso application:get_env(fireplace_config, enable_zookeeper_config_node_register, true).


get_node_role() ->
    application:get_env(fireplace_config, node_role, normal).

get_random_node(Type) ->
    try
        case get_node_role() of
            gray ->
                node();
            _ ->
                case ets:lookup(?NODE_TAB, {Type, size}) of
                    [{_, Size}] when Size > 0 ->
                        Idx = rand:uniform(Size),
                        case ets:lookup(?NODE_TAB, {Type, Idx}) of
                            [{_, Node}] ->
                                Node;
                            [] ->
                                node()
                        end;
                    _ ->
                        node()
                end
        end
    catch
        error:badarg ->
            node()
    end.

monitor_node_register(ZK, Node, TypeList) ->
    case enabled() of
        true ->
            L = lists:map(
                  fun(Type) ->
                          Path = path_key(Node, Type),
                          case erlzk:exists(ZK, Path, self()) of
                              {ok, _} ->
                                  {ok, Path};
                              {error, no_node} ->
                                  case erlzk:create(ZK, Path, ephemeral) of
                                      {ok, _} ->
                                          {ok, _} = erlzk:exists(ZK, Path, self()),
                                          {ok, Path};
                                      {error, Reason} ->
                                          {error, Reason}
                                  end;
                              {error, Reason} ->
                                  {error, Reason}
                          end
                  end, TypeList),
            case [{error, Reason}||{error, Reason}<-L] of
                [{error, Reason}|_] ->
                    {error, Reason};
                [] ->
                    {ok, [Path||{ok, Path}<-L]}
            end;
        false ->
            {ok, []}
    end.

monitor_node_list_change(ZK, TypeList) ->
    case enabled() of
        true ->
            L = lists:map(
                  fun(Type) ->
                          Path = path_key(Type),
                          case erlzk:get_children(ZK, Path, self()) of
                              {ok, NodeStrList} ->
                                  NodeList = [list_to_atom(NodeStr)||NodeStr<-NodeStrList],
                                  OldNodeList = get_node_list(Type),
                                  DelNodeList = calc_del_node_list(OldNodeList, NodeList),
                                  lists:foreach(
                                    fun(Node) ->
                                            add_node(Type, Node)
                                    end, NodeList),
                                  lists:foreach(
                                    fun(Node) ->
                                            del_node(Type, Node)
                                    end, DelNodeList),
                                  {ok, Path};
                              {error, Reason} ->
                                  {error, Reason}
                          end
                  end, TypeList),
            case [{error, Reason}||{error, Reason}<-L] of
                [{error, Reason}|_] ->
                    {error, Reason};
                [] ->
                    {ok, [Path||{ok, Path}<-L]}
            end;
        false ->
            {ok, []}
    end.

add_node(Type, Node) ->
    case ets:lookup(?NODE_TAB, {Type, Node}) of
        [_] ->
            skip;
        [] ->
            ?INFO_MSG("Add Node: node=~p, type=~p", [Node, Type]),
            case ets:lookup(?NODE_TAB, {Type, size}) of
                [{_, Size}] ->
                    ok;
                [] ->
                    Size = 0
            end,
            ets:insert(?NODE_TAB, [{{Type, Size+1}, Node},
                                {{Type, Node}, Size+1},
                                {{Type, size}, Size+1}])
    end.

del_node(Type, Node) ->
    case ets:lookup(?NODE_TAB, {Type, Node}) of
        [{_, Idx}] ->
            ?INFO_MSG("Del Node: node=~p, type=~p", [Node, Type]),
            [{_, Size}] = ets:lookup(?NODE_TAB, {Type, size}),
            [{_, TNode}] = ets:lookup(?NODE_TAB, {Type, Size}),
            ets:insert(?NODE_TAB, [{{Type, size}, Size-1},
                                 {{Type, Idx}, TNode},
                                 {{Type, TNode}, Idx}]),
            ets:delete(?NODE_TAB, {Type, Size}),
            ets:delete(?NODE_TAB, {Type, Node}),
            ok;
        [] ->
            skip
    end.

get_node_list(Type) ->
    case ets:lookup(?NODE_TAB, {Type, size}) of
        [{_, Size}] ->
            [Node||Idx<-lists:seq(1,Size), {_, Node}<-ets:lookup(?NODE_TAB, {Type, Idx})];
        [] ->
            []
    end.

calc_del_node_list(OldNodeList, NodeList) ->
    sets:to_list(sets:subtract(sets:from_list(OldNodeList), sets:from_list(NodeList))).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    erlang:process_flag(trap_exit, true),
    ets:new(?NODE_TAB, [named_table, public, set, {read_concurrency, true}]),
    {ok, #state{}}.

handle_call({register, Node, TypeList}, _From, State) ->
    self() ! refresh,
    {reply, ok, State#state{node=Node, type_list=TypeList}};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(refresh, #state{node=Node, type_list=TypeList}=State) ->
    try
        case fireplace_config_mgr:register(Node, TypeList) of
            ok ->
                Ref = erlang:monitor(process, fireplace_config_mgr),
                ?INFO_MSG("node register refresh ok: node=~p, type_list=~p", [Node, TypeList]),
                {noreply, State#state{ref = Ref}};
            {error, Reason} ->
                throw({error, Reason})
        end
    catch
        _:Error ->
            RetryDelay = application:get_env(fireplace_config, node_register_delay, 2000),
            ?INFO_MSG("node register refresh fail: node=~p, type_list=~p, Error=~p", [Node, TypeList, Error]),
            erlang:send_after(RetryDelay, self(), refresh),
            {noreply, State}
    end;
handle_info({'DOWN', Ref, process, _, Reason}, #state{ref=Ref}=State) ->
    ?INFO_MSG("fireplace_config_mgr stopped: Reason=~p", [Reason]),
    self() ! refresh,
    {noreply, State#state{ref = undefined}};
handle_info(_Info, State) ->
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

path_key(Node, Type) ->
    <<"/nodes/",(atom_to_binary(Type, utf8))/binary, "/",(atom_to_binary(Node, utf8))/binary>>.

path_key(Type) ->
    <<"/nodes/",(atom_to_binary(Type, utf8))/binary >>.
