%%%-------------------------------------------------------------------------------------------------
%%% File    :  fireplace_config_app.erl
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
-module(fireplace_config_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    Res = fireplace_config_sup:start_link(),
    try
        fireplace_config_mgr:wait_ready()
    catch
        _:_ ->
            ok
    end,
    Res.

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
