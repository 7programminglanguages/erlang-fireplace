%%%-------------------------------------------------------------------------------------------------
%%% File    :  process_sync_meta_message_groupchat.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  10 Nov 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(process_sync_meta_message_groupchat).

-export([handle/1]).
-include("xsync_pb.hrl").

handle(#'Meta'{} = Meta) ->
    case check_user_send_groupchat(Meta) of
        {error, {Code, Reason}} ->
            {error, {Code, Reason}};
        ok ->
            case xsync_group_router:route(Meta) of
                {error, Reason} ->
                    %%@TODO: fill real reason
                    ReasonDesc = misc:normalize_reason(Reason),
                    {error, {'FAIL', ReasonDesc}};
                ok ->
                    ok
            end
    end.

check_user_send_groupchat(#'Meta'{to = To}=Meta) ->
    case check_to(To) of
        {error, Reason} ->
            {error, Reason};
        ok ->
            %% TODO: check ....
            ok
    end.

check_to(#'XID'{uid = GroupId} =To) ->
    case misc:is_group(GroupId) of
        false ->
            {error, {'INVALID_PARAMETER', <<"bad group id">>}};
        true ->
            ok
    end.
