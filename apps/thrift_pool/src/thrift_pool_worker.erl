%%%-------------------------------------------------------------------------------------------------
%%% File    :  thrift_pool_worker.erl
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
-module(thrift_pool_worker).

-compile([{parse_transform, lager_transform}]).

-behaviour(gen_server).

%% API
-export([start_link/1]).
-export([thrift_call/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, {service,
                host,
                port,
                options,
                multiplexing_name,
                client
               }).

%%%===================================================================
%%% API
%%%===================================================================

start_link([Service, Opts]) ->
    gen_server:start_link(?MODULE, [Service, Opts], []).

thrift_call(Pid, Call, Args) ->
    gen_server:call(Pid, {thrift_call, Call, Args}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Service, Opts]) ->
    {Host, Port} = chose_server(Opts),
    Options = proplists:get_value(options, Opts, []),
    MultiplexingName = proplists:get_value(multiplexing_name, Opts, none),
    {ok, #state{
            host = Host,
            port = Port,
            service = Service,
            multiplexing_name = MultiplexingName,
            options = Options
           }}.

handle_call({thrift_call, Call, Args}, _From, State) ->
    handle_thrift_call(Call, Args, State).

handle_cast(_Request, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================

chose_server(Opts) ->
    case proplists:get_value(server_list, Opts, []) of
        [{Host, Port}] ->
            {Host, Port};
        Servers ->
            Idx = rand:uniform(length(Servers)),
            lists:nth(Idx, Servers)
    end.

handle_thrift_call(Call, Args, #state{client = undefined,
                                      host = Host,
                                      port = Port,
                                      service = Service,
                                      multiplexing_name = none,
                                      options = Options} = State) ->
    case thrift_client_util:new(Host, Port, Service, Options) of
        {ok, Client} ->
            handle_thrift_call(Call, Args, State#state{client = Client});
        {error, Reason} ->
            lager:error("cannot create thrift client: Reason = ~p, State = ~p~n", [Reason, State]),
            {stop, normal, {error, no_connection}, State}
    end;
handle_thrift_call(Call, Args, #state{client = undefined,
                                      host = Host,
                                      port = Port,
                                      service = Service,
                                      multiplexing_name = MultiplexingName,
                                      options = Options} = State) ->
    Services = [{MultiplexingName, Service}],
    case thrift_client_util:new_multiplexed(Host, Port, Services, Options) of
        {ok, [{MultiplexingName, Client}]} ->
            handle_thrift_call(Call, Args, State#state{client = Client});
        {error, Reason} ->
            lager:error("cannot create thrift client: Reason = ~p, State = ~p~n", [Reason, State]),
            {stop, normal, {error, no_connection}, State}
    end;
handle_thrift_call(Call, Args, #state{client = Client} = State) ->
    {NewClient, Res} = (catch thrift_client:call(Client, Call, Args)),
    handle_thrift_call_res(Res, State#state{client = NewClient}).

handle_thrift_call_res({ok, _} = Res, State) ->
    {reply, Res, State};
handle_thrift_call_res({exception, _} = Res, State) ->
    {reply, Res, State};
handle_thrift_call_res({error, Reason}, State) ->
    lager:warning("thrift error: reason = ~p, State = ~p", [Reason, State]),
    catch thrift_client:close(State#state.client),
    {stop, normal, {error, Reason}, State};
handle_thrift_call_res(Other, State) ->
    lager:warning("thrift error: reason = ~p, State = ~p", [Other, State]),
    catch thrift_client:close(State#state.client),
    {stop, normal, {error, Other}, State}.
