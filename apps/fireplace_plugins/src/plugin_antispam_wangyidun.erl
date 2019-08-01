%%%-------------------------------------------------------------------------------------------------
%%% File    :  plugin_antispam_wangyidun.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  9 Jan 2019 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(plugin_antispam_wangyidun).
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").
-include("logger.hrl").
-export([check_meta/1]).
-define(PASS,0).
-define(DOUBT,1).
-define(DENY,2).

check_meta(#'Meta'{ns = 'MESSAGE',
                   id = MsgId,
                   from = #'XID'{uid = FromUserId},
                   payload = #'MessageBody'{
                                type = Type,
                                ctype = CType,
                                content = Content
                               }}) when Type == 'CHAT';
                                        Type == 'GROUPCHAT';
                                        Type == 'NORMAL' ->
    check_content(FromUserId, CType, MsgId, Content);
check_meta(_) ->
    ok.

check_content(_FromUserId, _CType, _MsgId, <<>>) ->
    ok;
check_content(FromUserId, _CType, MsgId, Content) ->
    Opts = get_opts(),
    Enable = proplists:get_value(enable, Opts, true),
    case Enable of
        false ->
            ok;
        true ->
            {_, SecretId} = lists:keyfind(secret_id, 1, Opts),
            {_, SecretKey} = lists:keyfind(secret_key, 1, Opts),
            {_, BusinessId} = lists:keyfind(business_id, 1, Opts),
            Timestamp = erlang:system_time(milli_seconds),
            Params = [{secretId, SecretId},
                      {businessId, BusinessId},
                      {timestamp, Timestamp},
                      {nonce, rand:uniform(2100000000)},
                      {version, "v3"},
                      {dataId, MsgId},
                      {content, Content},
                      {account, FromUserId}],
            check_antispam(SecretKey, Params, Opts)
    end.

check_antispam(SecretKey, Params, Opts) ->
    Url = proplists:get_value(text_url, Opts, "https://api.aq.163.com/v3/text/check"),
    HttpTimeout = proplists:get_value(http_timeout, Opts, 5000),
    HttpResult = do_request(Url, Params, SecretKey, HttpTimeout),
    AntispamResult = case HttpResult of
                         {ok, #{<<"code">> := 200,
                                <<"result">> :=
                                    #{<<"action">> := ?PASS}}} ->
                             ok;
                         {ok, #{<<"code">> := 200,
                                <<"result">> :=
                                    #{<<"action">> := ?DOUBT}}} ->
                             case proplists:get_value(doubt_msg, Opts, allow) of
                                 allow ->
                                     ok;
                                 deny ->
                                     {error, {'FAIL', <<"antispam">>}}
                             end;
                         {ok, #{<<"code">> := 200,
                                <<"result">> :=
                                    #{<<"action">> := ?DENY}}} ->
                             case proplists:get_value(deny_msg, Opts, deny) of
                                 allow ->
                                     ok;
                                 deny ->
                                     {error, {'FAIL', <<"antispam">>}}
                             end;
                         _ ->
                             case proplists:get_value(fail_msg, Opts, allow) of
                                 allow ->
                                     ok;
                                 deny ->
                                     {error, {'FAIL', <<"antispam">>}}
                             end
                     end,
    ?INFO_MSG("Antispam result: Params=~p, HttpResult=~p, AntispamResult=~p",
              [Params, HttpResult, AntispamResult]),
    AntispamResult.

do_request(Url, Params, SecretKey, HttpTimeout) ->
    Headers = [],
    ContentType = "application/x-www-form-urlencoded",
    RequestBody = make_request_body(SecretKey, Params),
    try httpc:request(post, {Url, Headers, ContentType, RequestBody}, [{timeout, HttpTimeout}], []) of
        {ok, {{_, 200, _}, _, ResBody}} ->
            ?INFO_MSG("Antispam Req ok: url=~p, params=~p, ResBody=~ts",
                      [Url, Params, ResBody]),
            try
                ResBodyBin = iolist_to_binary(ResBody),
                {ok, jsx:decode(ResBodyBin, [{return_maps, true}])}
            catch
                _:_ ->
                    ?ERROR_MSG("Antispam Req fail: url=~p, params=~p, ResBody=~ts, reason=~p",
                               [Url, Params, ResBody, bad_json]),
                    {error, bad_json}
            end;
        Other ->
            ?ERROR_MSG("Antispam Req fail: url=~p, params=~p, Res=~p",
                       [Url, Params, Other]),
            {error, {unknown_result, Other}}
    catch
        C:E ->
            ?ERROR_MSG("Antispam Req fail: url=~p, params=~p, Res=~p",
                       [Url, Params, {C,{E, erlang:get_stacktrace()}}]),
            {error, {C,E}}
    end.

make_request_body(SecretKey, Params) ->
    Params1 = lists:map(
                fun({Key, Value}) ->
                        {atom_to_list(Key), to_list(Value)}
                end, Params),
    ParamsSorted = lists:sort(Params1),
    ParamsIolist = lists:map(
                fun({Key, Value}) ->
                        [Key, Value]
                end, ParamsSorted),
    Md5 = md5([ParamsIolist, SecretKey]),
    ParamsNew = [{"signature",Md5}|ParamsSorted],
    mochiweb_util:urlencode(ParamsNew).

get_opts() ->
    application:get_env(fireplace_plugins, ?MODULE, []).

to_list(Integer) when is_integer(Integer) ->
    integer_to_list(Integer);
to_list(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
to_list(List) when is_list(List) ->
    List;
to_list(Bin) when is_binary(Bin) ->
    binary_to_list(Bin).

md5(S) ->
    binary_to_list(
      iolist_to_binary(
        [io_lib:format("~2.16.0b", [N])
         || N <- binary_to_list(erlang:md5(S))])).
