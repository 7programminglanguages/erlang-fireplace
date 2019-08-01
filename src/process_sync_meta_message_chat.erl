%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta_message_chat.erl
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
-module(process_sync_meta_message_chat).

-export([handle/1]).
-include("xsync_pb.hrl").
-include("messagebody_pb.hrl").

handle(#'Meta'{} = Meta) ->
    case check_user_send_chat(Meta) of
        {error, {Code, Reason}} ->
            {error, {Code, Reason}};
        ok ->
            case xsync_router:route(Meta) of
                {error, Reason} ->
                    %%@TODO: fill real reason
                    ReasonDesc = misc:normalize_reason(Reason),
                    {error, {'FAIL', ReasonDesc}};
                ok ->
                    ok
            end
    end.

check_user_send_chat(#'Meta'{to = To} = Meta) ->
    %% @TODO: check user send chat
    %% check privacy
    %% check roster
    case check_to(To) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            case check_roster(Meta) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    case check_privacy(Meta) of
                        {error, Reason} ->
                            {error, Reason};
                        ok ->
                            ok
                    end
            end
    end.

check_to(#'XID'{uid = UserId}) ->
    case misc:is_user(UserId) of
        false ->
            {error, {'INVALID_PARAMETER', <<"bad user id">>}};
        true ->
            ok
    end.

check_roster(#'Meta'{payload = #'MessageBody'{type='OPER'}}) ->
    ok;
check_roster(#'Meta'{
               from = #'XID'{uid = FromUserId},
               to = #'XID'{uid = ToUserId}}) ->
    Rule = application:get_env(xsync, roster_message_rule, []),
    case lists:all(
           fun({_, Action}) ->
                   Action == allow
           end, Rule) of
        true ->
            ok;
        false ->
            case msgst_roster:get_relation(FromUserId, ToUserId) of
                {error, _Reason} ->
                    case roster_fail_bypass() of
                        true ->
                            ok;
                        false ->
                            {error, {'FAIL', <<"roster db error">>}}
                    end;
                {ok, Relation} ->
                    Action = proplists:get_value(Relation, Rule, deny),
                    case Action of
                        deny ->
                            {error, {'UNAUTHORIZED', <<"your relation with target does not allow chat">>}};
                        allow ->
                            ok
                    end
            end
    end.

check_privacy(#'Meta'{payload = #'MessageBody'{type='OPER'}}) ->
    ok;
check_privacy(#'Meta'{
                 from = #'XID'{uid = FromUserId},
                 to = #'XID'{uid = ToUserId}}) ->
    case msgst_roster:is_blocked(FromUserId, ToUserId) of
        {error, _Reason} ->
            case privacy_fail_bypass() of
                true ->
                    ok;
                false ->
                    {error, {'FAIL', <<"privacy db error">>}}
            end;
        {ok, true} ->
            {error, {'UNAUTHORIZED', <<"your privacy with target does not allow chat">>}};
        {ok, false} ->
            ok
    end.

roster_fail_bypass() ->
    application:get_env(xsync, roster_fail_bypass, true).

privacy_fail_bypass() ->
    application:get_env(xsync, privacy_fail_bypass, true).
