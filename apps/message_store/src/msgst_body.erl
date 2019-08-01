%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_body.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :
%%% Created :  14 Nov 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(msgst_body).

-export([
         write/2,
         read/1,
         read_odbc/1,
         delete/1,
         write_odbc/2,
         delete_odbc/1
        ]).

-include("logger.hrl").
-include("message_store_const.hrl").


%%****************************************************************************
%% API functions
%%****************************************************************************

write(MID, MBody) ->
    case write_redis(MID, MBody) of
        ok ->
            spawn(fun() ->
                          msgst_history:add_body(MID, MBody)
                  end),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

read(MID) ->
    case read_redis(MID) of
        {ok, MBody} ->
            {ok, MBody};
        {error, _Reason} ->
            read_odbc(MID)
    end.

delete(MID) ->
    case delete_redis(MID) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            spawn(fun() -> msgst_history:delete_body(MID) end),
            ok
    end.


%%****************************************************************************
%% internal functions
%%****************************************************************************

write_redis(MID, MBody) ->
    Key = redis_key(MID),
    Ttl = redis_ttl(),
    Value = compress(MBody),
    Query = ["SETEX", Key, Ttl, Value],
    case redis_pool:q(?REDIS_BODY_SERVICE, Query) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

read_redis(MIDList) when is_list(MIDList) ->
    Queries = lists:map(fun(MID) -> ["GET", redis_key(MID)] end, MIDList),
    case redis_pool:qp(?REDIS_BODY_SERVICE, Queries) of
        {error, Reason} ->
            {error, Reason};
        ResList ->
            MBodyList = check_res_list(ResList, []),
            {ok, MBodyList}
    end;
read_redis(MID) ->
    Key = redis_key(MID),
    Query = ["GET", Key],
    case redis_pool:q(?REDIS_BODY_SERVICE, Query) of
        {ok, undefined} ->
            {error, <<"not found">>};
        {ok, CBody} ->
            {ok, decompress(CBody)};
        {error, Reason} ->
            {error, Reason}
    end.

delete_redis(MID) ->
    Key = redis_key(MID),
    Query = ["DEL", Key],
    case redis_pool:q(?REDIS_BODY_SERVICE, Query) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

redis_key(MID) ->
    <<?REDIS_BODY_KEY_PREFIX/binary, (integer_to_binary(MID))/binary>>.

redis_ttl() ->
    application:get_env(message_store, redis_body_ttl, ?REDIS_BODY_TTL).

compress(MBody) ->
    case snappyer:compress(MBody) of
        {ok, CBody} ->
            CBody;
        {error,_} ->
            MBody
    end.

check_res_list([{ok, undefined} | ResList], MBodyList) ->
    check_res_list(ResList, [{error, <<"not found">>} | MBodyList]);
check_res_list([{ok, CBody} | ResList], MBodyList) ->
    check_res_list(ResList, [decompress(CBody) | MBodyList]);
check_res_list([{error, Reason} | ResList], MBodyList) ->
    check_res_list(ResList, [{error, Reason} | MBodyList]);
check_res_list([], MBodyList) ->
    MBodyList.

decompress(CBody) ->
    case snappyer:decompress(CBody) of
        {ok, MBody} ->
            MBody;
        {error,_} ->
            CBody
    end.

write_odbc(MID, MBody) ->
    case application:get_env(message_store, enable_body_write_odbc, true) of
        true ->
            write_odbc_1(MID, MBody);
        false ->
            ok
    end.

write_odbc_1(MID, MBody) ->
    HexBody = odbc_pool:hex(MBody),
    Query= [<<"insert ignore into message_body (mid, body) values (">>, integer_to_binary(MID), <<", X'">>, HexBody, <<"');">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {error, Reason} ->
            ?ERROR_MSG("write odbc body error, Reason:~p, MID: ~p, MBody:~p~n", [Reason, MID, MBody]),
            {error, Reason};
        {updated, 1} ->
            ok;
        {updated, UpdatedNum} ->
            ?WARNING_MSG("write odbc body no update: MID: ~p, MBody:~p, updated=~p",
                         [MID, MBody, UpdatedNum]),
            ok
    catch
        Class:Exception ->
            ?ERROR_MSG("write odbc body exception, Class:~p, Exception:~p, MID: ~p, MBody:~p~n", [Class, Exception, MID, MBody]),
            {error, Exception}
    end.

read_odbc(MIDOrList) ->
    case application:get_env(message_store, enable_body_read_odbc, true) of
        true ->
            read_odbc_1(MIDOrList);
        false ->
            case is_list(MIDOrList) of
                true ->
                    {ok, []};
                false ->
                    {error, <<"not found">>}
            end
    end.

read_odbc_1(MIDList) when is_list(MIDList) ->
    QueryRange = midlist_to_query_range(MIDList, []),
    Query= [<<"select body from  message_body where mid in (">>, QueryRange, <<") and is_del=0 order by mid asc;">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"body">>], ResList} ->
            BodyList = lists:map(
                         fun([Body]) ->
                                 Body
                         end, ResList),
            {ok, BodyList};
        {error, Reason} ->
            ?ERROR_MSG("pipe read odbc body error, Reason:~p, MIDList: ~p~n", [Reason, MIDList]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("pipe read odbc body exception, Class:~p, Exception:~p, MIDList: ~p~n", [Class, Exception, MIDList]),
            {error, Exception}
    end;
read_odbc_1(MID) ->
    Query= [<<"select body from  message_body where mid = ">>, integer_to_binary(MID), <<" and is_del=0;">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {selected, [<<"body">>], []} ->
            {error, <<"not found">>};
        {selected, [<<"body">>], [[Body]]} ->
            {ok, Body};
        {error, Reason} ->
            ?ERROR_MSG("read odbc body error, Reason:~p, MID: ~p~n", [Reason, MID]),
            {error, Reason}
    catch
        Class:Exception ->
            ?ERROR_MSG("read odbc body exception, Class:~p, Exception:~p, MID: ~p~n", [Class, Exception, MID]),
            {error, Exception}
    end.

midlist_to_query_range([MID], ResList) ->
    midlist_to_query_range([], [integer_to_binary(MID) | ResList]);
midlist_to_query_range([MID | MIDList], ResList) ->
    midlist_to_query_range(MIDList, [<<",">>, integer_to_binary(MID) | ResList]);
midlist_to_query_range([], ResList) ->
    ResList.

delete_odbc(MID) ->
    case application:get_env(message_store, enable_body_write_odbc, true) of
        true ->
            delete_odbc_1(MID);
        false ->
            ok
    end.

delete_odbc_1(MID) ->
    Query= [<<"update message_body set is_del=1 where mid = ">>, integer_to_binary(MID), <<";">>],
    try odbc_pool:sql_query(?ODBC_SERVICE_NAME, Query) of
        {error, Reason} ->
            ?ERROR_MSG("delete odbc body error, Reason:~p, MID: ~p~n", [Reason, MID]),
            {error, Reason};
        _ ->
            ok
    catch
        Class:Exception ->
            ?ERROR_MSG("delete odbc body exception, Class:~p, Exception:~p, MID: ~p~n", [Class, Exception, MID]),
            {error, Exception}
    end.
