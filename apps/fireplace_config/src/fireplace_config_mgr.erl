%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_mgr.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created : 23 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(fireplace_config_mgr).

-behaviour(gen_server).

%% API
-export([start_link/0, get_client/0, wait_ready/0,
         enabled/0, write_config_to_zk/1,
         register/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-include("fireplace_config.hrl").

-define(SERVER, ?MODULE).

-record(state, {
                stage,
                type,
                zookeeper_list,
                zookeeper_root,
                zookeeper_timeout,
                retry_delay,
                client,
                client_ref,
                paths,
                machine_id,
                machine_id_path,
                config_path,
                monitor_node,
                monitor_node_type_list,
                monitor_node_paths = [],
                monitor_node_list_change_type_list = [],
                monitor_node_list_change_paths = [],
                wait_list = []
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

get_client() ->
    gen_server:call(?SERVER, get_client).

wait_ready() ->
    gen_server:call(?SERVER, wait_ready, infinity).

enabled() ->
    config_method() /= none.

config_method() ->
    application:get_env(fireplace_config, method, none).

write_config_to_zk(FileName) ->
    fireplace_config_load:write_config_to_zk(FileName).

register(Node, TypeList) ->
    gen_server:call(?SERVER, {register, Node, TypeList}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    erlang:process_flag(trap_exit, true),
    ZookeeperTimeout = application:get_env(fireplace_config, zookeeper_timeout, 30000),
    RetryDelay = application:get_env(fireplace_config, zookeeper_retry_delay, 1000),
    ZookeeperList = application:get_env(fireplace_config, zookeeper_list, []),
    ZookeeperRoot = application:get_env(fireplace_config, zookeeper_root, "/"),
    ZookeeperPaths = application:get_env(fireplace_config, zookeeper_paths,
                                         ["/config", "/ids", "/nodes", "/nodes/worker",
                                          "/advise_ids", "/advise_nodes"]),
    MonitorNodeListChangeTypeList = application:get_env(fireplace_config, monitor_node_list_change_type_list,
                                                        [worker]),
    State = #state{
               zookeeper_timeout = ZookeeperTimeout,
               zookeeper_list = ZookeeperList,
               zookeeper_root = ZookeeperRoot,
               retry_delay = RetryDelay,
               paths = ZookeeperPaths,
               monitor_node_list_change_type_list = MonitorNodeListChangeTypeList
              },
    case config_method() of
        zookeeper ->
            self() ! connect,
            {ok, State#state{stage = down}};
        none ->
            {ok, State#state{stage = disabled}}
    end.

handle_call(get_client, _From, State) ->
    {reply, State#state.client, State};
handle_call(wait_ready, _From, #state{stage = up}=State) ->
    {reply, ok, State};
handle_call(wait_ready, _From, #state{stage = disabled}=State) ->
    {reply, disabled, State};
handle_call(wait_ready, From, #state{wait_list=WaitList} = State) ->
    {noreply, State#state{wait_list = [From|WaitList]}};
handle_call({register, Node, TypeList}, _From, State) ->
    self() ! monitor_node_register,
    {reply, ok, State#state{monitor_node = Node,
                            monitor_node_type_list = TypeList}};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(connect, #state{stage = down,
                            client = undefined,
                            zookeeper_timeout = ZookeeperTimeout,
                            zookeeper_list = ZookeeperList,
                            zookeeper_root = ZookeeperRoot,
                            retry_delay = RetryDelay} = State) ->
    case erlzk:connect(ZookeeperList, ZookeeperTimeout,[{monitor, self()}, {chroot, ZookeeperRoot}]) of
        {ok, Client} ->
            Ref = erlang:monitor(process, Client),
            self() ! ensure_zookeeper_root,
            {noreply, State#state{client = Client, client_ref = Ref, stage = ensure_zookeeper_root}};
        {error, Reason} ->
            ?ERROR_MSG("fail to connect zookeeper: zk=~p, reason=~p",
                                   [ZookeeperList, Reason]),
            erlang:send_after(RetryDelay, self(), connect),
            {noreply, State}
    end;
handle_info(ensure_zookeeper_root, #state{stage = ensure_zookeeper_root,
                                          retry_delay = RetryDelay}=State) ->
    case maybe_create_root(State) of
        ok ->
            self() ! ensure_paths,
            {noreply, State#state{stage = ensure_paths}};
        {error, Reason} ->
            ?ERROR_MSG("ensure_zookeeper_root fail: reason=~p", [Reason]),
            erlang:send_after(RetryDelay, self(), ensure_zookeeper_root),
            {noreply, State}
    end;
handle_info(ensure_paths, #state{stage = ensure_paths,
                                client = Client,
                                retry_delay = RetryDelay,
                                paths = Paths} = State) ->
    case ensure_paths(Client, Paths) of
        ok ->
            self() ! ensure_load_config,
            {noreply, State#state{stage = ensure_load_config}};
        {error, Reason} ->
            ?ERROR_MSG("ensure_paths fail: reason=~p", [Reason]),
            erlang:send_after(RetryDelay, self(), ensure_paths),
            {noreply, State}
    end;

handle_info(ensure_load_config, #state{stage = ensure_load_config,
                                       client = ZK} = State) ->
    case fireplace_config_load:first_load_config(ZK) of
        {ok, Path} ->
            self() ! ensure_machine_id,
            {noreply, State#state{config_path = Path, stage = ensure_machine_id}};
        {error, disabled} ->
            self() ! ensure_machine_id,
            {noreply, State#state{stage = ensure_machine_id}}
    end;
handle_info(ensure_machine_id, #state{stage = ensure_machine_id,
                                      client = ZK,
                                      machine_id = MachineId}=State) ->
    case MachineId of
        undefined ->
            case fireplace_config_machine_id:register_machine_id(ZK) of
                {ok, NewMachineId} ->
                    ?INFO_MSG("machine id register ok: machineId=~p", [NewMachineId]),
                    self() ! monitor_machine_id,
                    self() ! monitor_node_list_change,
                    self() ! up,
                    {noreply, State#state{machine_id=NewMachineId, stage = up}};
                {error, disabled} ->
                    self() ! monitor_node_list_change,
                    self() ! up,
                    {noreply, State#state{stage = up}};
                {error, Reason} ->
                    ?ERROR_MSG("fail to generate machineid: reason=~p", [Reason]),
                    init:stop()
            end;
        _ ->
            self() ! monitor_machine_id,
            self() ! monitor_node_list_change,
            self() ! up,
            {noreply, State#state{stage = up}}
    end;
handle_info(monitor_machine_id, #state{client = ZK,
                                       machine_id = MachineId,
                                       retry_delay = RetryDelay} = State) when is_integer(MachineId) ->
    case fireplace_config_machine_id:monitor_machine_id(ZK, MachineId) of
        {ok, Path} ->
            ?INFO_MSG("monitor machine id ok:path=~p", [Path]),
            {noreply, State#state{machine_id_path = Path}};
        {error, machine_id_changed} ->
            ?ERROR_MSG("machine id changed, need register again", []),
            self() ! ensure_machine_id,
            {noreply, State#state{machine_id = undefined, stage = ensure_machine_id}};
        {error, Reason} ->
            ?ERROR_MSG("monitor machine id fail:reason=~p", [Reason]),
            erlang:send_after(RetryDelay, self(), monitor_machine_id),
            {noreply, State}
    end;
handle_info(refresh_config, #state{client = ZK,
                                   retry_delay = RetryDelay
                                  } = State) ->
    case fireplace_config_load:refresh_config(ZK) of
        {ok, _Path} ->
            ?INFO_MSG("refresh config ok", []),
            {noreply, State};
        {error, bad_binary} ->
            ?ERROR_MSG("refresh config fail:reason=~p", [bad_binary]),
            {noreply, State};
        {error, Reason} ->
            ?ERROR_MSG("refresh config fail:reason=~p", [Reason]),
            erlang:send_after(RetryDelay, self(), refresh_config),
            {noreply, State}
    end;

handle_info(monitor_node_register, #state{client = ZK,
                                          monitor_node = Node,
                                          monitor_node_type_list = TypeList,
                                          retry_delay = RetryDelay}=State) ->
    case fireplace_config_node_mgr:monitor_node_register(ZK, Node, TypeList) of
        {ok, PathList} ->
            ?INFO_MSG("monitor node type ok:Node=~p, TypeList=~p, Paths=~p",
                       [Node, TypeList, PathList]),
            {noreply, State#state{monitor_node_paths = PathList}};
        {error, Reason} ->
            ?ERROR_MSG("monitor node type fail:Reason=~p, Node=~p, TypeList=~p",
                       [Reason, Node, TypeList]),
            erlang:send_after(RetryDelay, self(), monitor_node_register),
            {noreply, State}
    end;
handle_info(monitor_node_list_change, #state{client = ZK,
                                             monitor_node_list_change_type_list = TypeList,
                                             retry_delay = RetryDelay} = State) ->
    case fireplace_config_node_mgr:monitor_node_list_change(ZK, TypeList) of
        {ok, PathList} ->
            ?INFO_MSG("monitor node list change ok: TypeList=~p, Paths=~p",
                      [TypeList, PathList]),
            {noreply, State#state{monitor_node_list_change_paths = PathList}};
        {error, Reason} ->
            ?ERROR_MSG("monitor node list change fail:Reason=~p, TypeList=~p",
                       [Reason, TypeList]),
            erlang:send_after(RetryDelay, self(), monitor_node_list_change),
            {noreply, State}
    end;
handle_info(up, #state{stage = up, wait_list=WaitList}=State) ->
    lists:foreach(
      fun(From) ->
              gen_server:reply(From, ok)
      end, WaitList),
    {noreply, State#state{wait_list=[]}};
handle_info({'DOWN', Ref, process, Pid, Reason}, #state{client = Pid, client_ref = Ref} = State) ->
    self() ! connect,
    ?INFO_MSG("connection down: pid=~p, reason=~p", [Pid, Reason]),
    {noreply, State#state{client = undefined, client_ref = undefined, stage = down}};
handle_info({node_deleted, MachineIdPath}, #state{machine_id_path=MachineIdPath} =State) ->
    ?INFO_MSG("machine id deleted: Path=~p", [MachineIdPath]),
    self() ! monitor_machine_id,
    {noreply, State};
handle_info({node_deleted, Path}, #state{monitor_node_paths=Paths} =State) ->
    case lists:member(Path, Paths) of
        true ->
            ?INFO_MSG("monitor node deleted: Path=~p", [Path]),
            self() ! monitor_node_register;
        false ->
            skip
    end,
    {noreply, State};
handle_info({node_data_changed, MachineIdPath}, #state{machine_id_path=MachineIdPath} =State) ->
    ?INFO_MSG("machine id changed: Path=~p", [MachineIdPath]),
    self() ! monitor_machine_id,
    {noreply, State};
handle_info({node_data_changed, ConfigPath}, #state{config_path=ConfigPath} =State) ->
    ?INFO_MSG("config changed: Path=~p", [ConfigPath]),
    self() ! refresh_config,
    {noreply, State};
handle_info({node_children_changed, Path}, #state{monitor_node_list_change_paths = Paths}=State) ->
    case lists:member(Path, Paths) of
        true ->
            self() ! monitor_node_list_change;
        false ->
            skip
    end,
    {noreply, State};
handle_info({expired,_,_}, State) ->
    ?INFO_MSG("session expired: State=~p", [State]),
    self() ! monitor_machine_id,
    self() ! refresh_config,
    self() ! monitor_node_register,
    self() ! monitor_node_list_change,
    {noreply, State};
handle_info({connected,_,_}, #state{stage=Stage}=State) ->
    ?INFO_MSG("connected: State=~p", [State]),
    case Stage of
        up ->
            self() ! monitor_machine_id,
            self() ! refresh_config,
            self() ! monitor_node_register,
            self() ! monitor_node_list_change;
        _ ->
            skip
    end,
    {noreply, State};
handle_info({'EXIT', Pid, Reason}, _State) ->
    ?INFO_MSG("receive exit event: pid=~p, reason=~p", [Pid, Reason]),
    {stop, normal, Reason};
handle_info(Info, State) ->
    ?INFO_MSG("unhandled Info:~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, #state{client = ZK}=__State) ->
    try
        erlzk:close(ZK)
    catch
        _:_ ->
            ok
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================

maybe_create_root(#state{client = Client,
                         zookeeper_timeout = ZookeeperTimeout,
                         zookeeper_list = ZookeeperList,
                         zookeeper_root = ZookeeperRoot}) ->
    case erlzk:exists(Client, "/") of
        {ok, _} ->
            ok;
        {error, no_node} ->
            case erlzk:connect(ZookeeperList, ZookeeperTimeout, []) of
                {ok, TmpClient} ->
                    Result = erlzk:create(TmpClient, ZookeeperRoot),
                    erlzk:close(TmpClient),
                    case Result of
                        {ok, _} ->
                            ok;
                        {error, node_exists} ->
                            ok;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

ensure_paths(Client, [Path|Rest]) ->
    case erlzk:create(Client, Path) of
        {ok, _} ->
            ensure_paths(Client, Rest);
        {error, node_exists} ->
            ensure_paths(Client, Rest);
        {error, Reason} ->
            {error, Reason}
    end;
ensure_paths(_, []) ->
    ok.
