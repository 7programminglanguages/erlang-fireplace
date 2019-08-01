%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  9 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(process_sync).

-export([handle/3, handle_sync/3]).
-include("xsync_pb.hrl").

handle(undefined, Response, _XID) ->
    xsync_proto:set_status(Response, 'INVALID_PARAMETER', <<"no sync payload">>);

handle(#'SyncUL'{} = SyncUL, Response, XID) ->
    ReceiveTime = erlang:system_time(milli_seconds),
    case xsync_cluster:worker_rpc(?MODULE, handle_sync, [SyncUL, Response, XID], badrpc) of
        badrpc ->
            Response1 = xsync_proto:set_status(Response, 'FAIL', <<"internal rpc error">>);
        Response1 ->
            skip
    end,
    FinishTime = erlang:system_time(milli_seconds),
    xsync_proto:set_sync_server_time(Response1, ReceiveTime, FinishTime).

handle_sync(#'SyncUL'{meta = Meta,
                      key = Key,
                      xid = CID,
                      is_full_sync = IsFullSync,
                      full_sync_num = FullSyncNum}, Response, XID) ->
    Response1 = process_sync_meta:handle(Meta, Response, XID),
    {Code, _} = xsync_proto:get_status(Response1),
    case Code of
        'OK' ->
            case IsFullSync of
                false ->
                    process_sync_conversation:handle(Key, CID, Response1, XID);
                true ->
                    Response2 = xsync_proto:set_full_sync(Response1),
                    process_sync_full_sync:handle(Key, CID, Response2, FullSyncNum, XID)
            end;
        _ ->
            Response1
    end.
