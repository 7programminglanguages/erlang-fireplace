#!/usr/bin/env escript
%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ft=erlang ts=4 sw=4 et

main([]) ->
    FileList = filelib:wildcard("include/*_pb.hrl"),
    [process(File)||File<- FileList].

process(File) ->
    case file:read_file(File) of
        {ok, Bin} ->
            List = binary_to_list(Bin),
            case string:str(List, "record_pb_xid") of
                0 ->
                    try_replace(File, List);
                _ ->
                    skip
            end;
        _ ->
            skip
    end.

try_replace(File, List) ->
    Str = re:replace(List, "-record\\\('XID[^.]*\.", "-ifndef(record_pb_xid).\n-define(record_pb_xid, true).\n&\n-endif.\n"),
    case Str /= List of
        true ->
            io:format("format pb: ~p~n", [File]),
            file:write_file(File, Str);
        false ->
            skip
    end.
