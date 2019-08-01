%%%-------------------------------------------------------------------------------------------------
%%% File    :  message_store_app.erl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

-module(message_store_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    message_store_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
