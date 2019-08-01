%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_load.erl
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
-module(fireplace_config_load).

-include("fireplace_config.hrl").
-export([first_load_config/1, refresh_config/1, write_config_to_zk/1]).

first_load_config(ZK) ->
    case enabled() of
        true ->
            Path = config_key(),
            case refresh_config(ZK, false) of
                {ok, _} ->
                    {ok, Path};
                {error, Reason} ->
                    ?ERROR_MSG("load_config use backup:Reason=~p", [Reason]),
                    case load_env_from_file() of
                        ok ->
                            ?INFO_MSG("load_config from backup ok", []),
                            {ok, Path};
                        {error, Reason2} ->
                            ?ERROR_MSG("first_load_config from backup fail:Reason=~p", [Reason2]),
                            halt()
                    end
            end;
        false ->
            {error, disabled}
    end.

refresh_config(ZK) ->
    refresh_config(ZK, true).

refresh_config(ZK, ShowDiff) ->
    Path = config_key(),
    case erlzk:get_data(ZK, Path, self()) of
        {ok, {ConfigBin, _}} ->
            case load_env_from_binary(ConfigBin, ShowDiff) of
                ok ->
                    backup_config_to_file(ConfigBin),
                    {ok, Path};
                {error, Reason} ->
                    ?ERROR_MSG("load_config fail:Reason=~p", [Reason]),
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

write_config_to_zk(FileName) ->
    {ok, Binary} = file:read_file(FileName),
    ZK = fireplace_config_mgr:get_client(),
    Path = config_key(),
    case is_valid_config_binary(Binary) of
        true ->
            {ok, _} = erlzk:set_data(ZK, Path, Binary),
            ok;
        _ ->
            {error, bad_config_data}
    end.

is_valid_config_binary(Binary) ->
    case string_to_term(binary_to_list(Binary)) of
        L when is_list(L) ->
            lists:all(
              fun({App, AppConfigs}) when is_atom(App), is_list(AppConfigs) ->
                      lists:all(
                        fun({Key, _Value}) when is_atom(Key) ->
                                true;
                           (_) ->
                                false
                        end, AppConfigs);
                 (_) ->
                      false
              end, L);
        _ ->
            false
    end.

enabled() ->
    fireplace_config_mgr:enabled()
        andalso application:get_env(fireplace_config, enable_zookeeper_config_env, true).

string_to_term(String) ->
    case erl_scan:string(String) of
        {ok, Tokens, _} ->
            case erl_parse:parse_term(Tokens) of
                {ok, Term} -> Term;
                _Err -> undefined
            end;
        _Error ->
            undefined
    end.

configs_to_env([{App, AppConfigs}|Configs], ShowDiff) ->
    application:load(App),
    app_config_to_env(App, AppConfigs, ShowDiff),
    configs_to_env(Configs, ShowDiff);
configs_to_env([],_) ->
    ok.

app_config_to_env(App, [{Key, Value}|AppConfigs], ShowDiff) ->
    case is_ignore(App, Key) of
        false ->
            case application:get_env(App, Key) of
                {ok, Value} ->
                    ok;
                {ok, OldValue} ->
                    ShowDiff andalso
                        ?INFO_MSG("Change Env: app=~p, key=~p, old_value=~p, new_value=~p",
                                  [App, Key, OldValue, Value]),
                    application:set_env(App, Key, Value);
                undefined ->
                    ShowDiff andalso
                        ?INFO_MSG("Add Env: app=~p, key=~p, value=~p",
                              [App, Key, Value]),
                    application:set_env(App, Key, Value)
            end;
        true ->
            skip
    end,
    app_config_to_env(App, AppConfigs, ShowDiff);
app_config_to_env(_, [], _) ->
    ok.

is_ignore(ticktick, machine_id) ->
    true;
is_ignore(fireplace_config, method) ->
    true;
is_ignore(fireplace_config, zookeeper_list) ->
    true;
is_ignore(fireplace_config, zookeeper_root) ->
    true;
is_ignore(xsync, node_type) ->
    true;
is_ignore(_App, _Key) ->
    false.

backup_config_to_file(ConfigBin) ->
    File = get_config_backup_file(),
    filelib:ensure_dir(File),
    case file:write_file(File, ConfigBin) of
        ok ->
            ok;
        {error, Reason} ->
            ?ERROR_MSG("fail to write backup file:file=~p", [File]),
            {error, Reason}
    end.

load_env_from_file() ->
    File = get_config_backup_file(),
    case file:read_file(File) of
        {ok, Bin} ->
            load_env_from_binary(Bin);
        {error, Reason} ->
            {error, Reason}
    end.

load_env_from_binary(Binary) ->
    load_env_from_binary(Binary, false).
load_env_from_binary(Binary, ShowDiff) ->
    case string_to_term(binary_to_list(Binary)) of
        Configs when is_list(Configs) ->
            configs_to_env(Configs, ShowDiff);
        _ ->
            ?ERROR_MSG("fail to load env from binary:Binary=~p", [Binary]),
            {error, bad_binary}
    end.

get_config_backup_file() ->
    application:get_env(fireplace_config, config_backup_file, ".config.backup").

config_key() ->
    <<"/config">>.
