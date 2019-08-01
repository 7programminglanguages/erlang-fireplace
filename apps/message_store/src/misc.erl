%%%-------------------------------------------------------------------------------------------------
%%% File    :  misc.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  17 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(misc).

-export([to_binary/2,
         is_user/1,
         is_group/1,
         chat_type/1,
         normalize_reason/1,
         map_pal/2,
         map_pal/3,
         foreach_pal/3
        ]).
-include("message_store_const.hrl").
-define(ID_MAGIC, 2#111110000000000000000000000000000). %% 29-33 bits

to_binary(Atom, _) when is_atom(Atom) ->
    atom_to_binary(Atom, utf8);
to_binary(Binary, _) when is_binary(Binary) ->
    Binary;
to_binary(List, Separator) when is_list(List) ->
    case io_lib:printable_list(List) of
        true ->
            list_to_binary(List);
        false ->
            iolist_to_binary(string:join([binary_to_list(to_binary(E, Separator))||E<-List], Separator))
    end;
to_binary(Integer, _) when is_integer(Integer) ->
    integer_to_binary(Integer);
to_binary(Tuple, Separator) when is_tuple(Tuple) ->
    to_binary(tuple_to_list(Tuple),Separator);
to_binary(O,_) ->
    iolist_to_binary(io_lib:format("~p",[O])).

is_user(0) ->
    false;
is_user(Id) ->
    case application:get_env(message_store, use_new_id_rule, true) of
        true ->
            Id band ?ID_MAGIC == 0;
        false ->
            Id band 2#111 == 0
    end.

is_group(Id) ->
    case application:get_env(message_store, use_new_id_rule, true) of
        true ->
            Id band ?ID_MAGIC /= 0;
        false ->
            Id band 2#111 == 1
    end.

chat_type(Id) ->
    case is_group(Id) of
        true ->
            ?GROUP_CHAT;
        false ->
            ?CHAT
    end.

normalize_reason(tcp_closed) ->
    <<"db error">>;
normalize_reason(timeout) ->
    <<"db timeout">>;
normalize_reason(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
normalize_reason(Reason) ->
    to_binary(Reason, ":").

map_pal(F, L) ->
    map_pal(F, L, 1000).
map_pal(F, L, Pal) ->
    map_pal(F, L, Pal, 1, dict:new(), []).

map_pal(F, [I|L], Pal, Idx, Dict, Values) when Pal > 0 ->
    {_,Ref} = spawn_monitor(
                fun() ->
                        exit({map_pal_res, F(I)})
                end),
    Dict1 = dict:store(Ref, Idx, Dict),
    map_pal(F, L, Pal-1, Idx+1, Dict1, Values);
map_pal(F, L, Pal, Idx, Dict, Values) ->
    case dict:is_empty(Dict) of
        true ->
            [Value||{_,Value}<-lists:sort(Values)];
        false ->
            receive
                {'DOWN', Ref, process, _Pid, {map_pal_res, Res}} ->
                    case dict:find(Ref, Dict) of
                        error ->
                            map_pal(F, L, Pal, Idx, Dict, Values);
                        {ok, TIdx} ->
                            Dict1 = dict:erase(Ref, Dict),
                            map_pal(F, L, Pal+1, Idx, Dict1, [{TIdx,Res}|Values])
                    end;
                {'DOWN', _Ref, process, _Pid, Error} ->
                    erlang:error(Error)
            end
    end.

foreach_pal(F, L, Pal) ->
    foreach_pal(F, L, Pal, 0).

foreach_pal(F, [I|L], Pal, Wait) when Pal > 0 ->
    {_,_Ref} = spawn_monitor(
                 fun() ->
                         exit({pal_res, F(I)})
                 end),
    foreach_pal(F, L, Pal-1, Wait+1);
foreach_pal(F, L, Pal, Wait)  when Wait > 0 ->
    receive
        {'DOWN', _Ref, process, _Pid, {pal_res, _Res}} ->
            foreach_pal(F, L, Pal+1, Wait-1);
        {'DOWN', _Ref, process, _Pid, Error} ->
            erlang:error(Error)
    end;
foreach_pal(_F, _L, _Pal, _Wait) ->
    ok.
