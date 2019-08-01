%%%-------------------------------------------------------------------------------------------------
%%% File    :  kafka_pool_sup.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(kafka_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_service/1, stop_service/1]).
-export([get_pool_size/1, get_client_id/2, get_reader_name/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_service(Service) ->
    start_client_by_name(Service),
    start_reader_by_name(Service).

stop_service(Service) ->
    stop_client_by_name(Service),
    stop_reader_by_name(service).

get_pool_size(Service) ->
    proplists:get_value(pool_size, application:get_env(kafka_pool, Service,[]), 1).

get_client_id(Service, PoolId) ->
    make_client_id(Service, PoolId).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: #{id => Id, start => {M, F, A}}
%% Optional keys are restart, shutdown, type, modules.
%% Before OTP 18 tuples must be used to specify a child. e.g.
%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    start_all_clients(),
    ChildSpecs = reader_specs(),
    CollectorSpecs = collector_specs(),
    {ok, { {one_for_one, 100000, 1}, ChildSpecs ++ CollectorSpecs} }.

%%====================================================================
%% Internal functions
%%====================================================================

start_all_clients() ->
    Services = application:get_env(kafka_pool, services, []),
    lists:foreach(
      fun(Service) ->
              start_client_by_name(Service)
      end, Services).

start_client_by_name(Service) ->
    {ok, Opts} = application:get_env(kafka_pool, Service),
    case proplists:get_value(server_list, Opts, []) of
        [] ->
            Host = proplists:get_value(host, Opts),
            Port = proplists:get_value(port, Opts, 9092),
            ServerList = [{Host, Port}];
        ServerList ->
            ok
    end,
    PoolSize = proplists:get_value(pool_size, Opts, 1),
    ClientOpts = make_client_opts(Service),
    lists:foreach(
      fun(PoolId) ->
              ClientId = make_client_id(Service, PoolId),
              brod:start_client(ServerList, ClientId, ClientOpts)
      end, lists:seq(1, PoolSize)).

stop_client_by_name(Service) ->
    lists:foreach(
      fun({ClientId, _,_,_}) ->
              case ClientId == Service of
                  true ->
                      brod:stop(ClientId);
                  false ->
                      IsPrefix =
                          re:run(atom_to_list(ClientId),
                                 lists:concat(["^", Service, "#"])) /= nomatch,
                      case IsPrefix of
                          true ->
                              brod:stop(ClientId);
                          false ->
                              skip
                      end
              end
      end, supervisor:which_children(brod_sup)).

start_reader_by_name(Service) ->
    case reader_spec(Service) of
        [] ->
            skip;
        Specs ->
            [supervisor:start_child(?SERVER, Spec)
             || Spec <- Specs]
    end.

stop_reader_by_name(Service) ->
    lists:foreach(
      fun({ReaderName, _,_,_}) ->
              IsServiceReader =
                  re:run(atom_to_list(ReaderName),
                         lists:concat(["^", Service, "#"])) /= nomatch,
              case IsServiceReader of
                  true ->
                      try
                          supervisor:terminate_child(?SERVER, ReaderName),
                          supervisor:delete_chidl(?SERVER, ReaderName)
                      catch
                          _:_ ->
                              skip
                      end;
                  false ->
                      skip
              end
      end, supervisor:which_children(?SERVER)).

make_client_opts(Service) ->
    {ok,ServiceOpts} = application:get_env(kafka_pool, Service),
    ClientDefaultOpts = application:get_env(kafka_pool, client_default, []),
    ProducerDefaultOpts = application:get_env(kafka_pool, producer_default, []),
    ProducerOpts = update_opts(ProducerDefaultOpts, ServiceOpts),
    update_opts([{default_producer_config, ProducerOpts}] ++ ClientDefaultOpts,
                ServiceOpts).

update_opts(DefaultOpts, NewOpts) ->
    lists:map(
      fun({Key, Value}) ->
              {Key, proplists:get_value(Key, NewOpts, Value)}
      end, DefaultOpts).

make_client_id(Service, PoolId) when PoolId > 1 ->
    list_to_atom(lists:concat([Service, "#", PoolId]));
make_client_id(Service, _) ->
    Service.

reader_specs() ->
    Services = application:get_env(kafka_pool, services, []),
    lists:append(
      [reader_spec(Service)||Service<-Services]).

reader_spec(Service) ->
    {ok,ServiceOpts} = application:get_env(kafka_pool, Service),
    case proplists:get_value(topic, ServiceOpts) of
        undefined ->
            [];
        Topic ->
            ConsumerDefaultOpts = application:get_env(kafka_pool, consumer_default, []),
            ConsumerGroupDefaultOpts = application:get_env(kafka_pool, consumer_group_default, []),
            ConsumerOpts = update_opts(ConsumerDefaultOpts, ServiceOpts),
            ConsumerGroupOpts = update_opts(ConsumerGroupDefaultOpts, ServiceOpts),
            ConsumerGroupId = decide_consumer_group_id(ServiceOpts, Topic),
            ReaderName = get_reader_name(Service),
            [{ReaderName,
             {kafka_pool_reader, start_link, [ReaderName, Service, Topic,
                                              ConsumerGroupId, ConsumerOpts, ConsumerGroupOpts]},
             permanent, 5000, worker, [ReaderName]}]
    end.

decide_consumer_group_id(ServiceOpts, Topic) ->
    case proplists:get_value(consumer_group_id, ServiceOpts) of
        undefined ->
            Prefix = application:get_env(kafka_pool, consumer_group_prefix, <<"xsync-consumer-">>),
            <<Prefix/binary, Topic/binary>>;
        ConsumerGroup ->
            ConsumerGroup
    end.

get_reader_name(Service) ->
    list_to_atom(lists:concat([Service, "#reader"])).

collector_specs() ->
    Opts = application:get_env(kafka_pool, produce_collector, []),
    case proplists:get_value(pool_size, Opts) of
        undefined ->
            [];
        PoolSizeOrig ->
            ServiceName = kafka_pool_produce_collector,
            PoolSize = normalize_pool_size(PoolSizeOrig),
            PoolOpts = [ServiceName, PoolSize,
                        [kafka_pool_produce_collector],
                        {kafka_pool_produce_collector, start_link, []}],
            [{ServiceName,
             {cuesport, start_link, PoolOpts},
             permanent,
             infinity,
             supervisor,
             [kafka_pool_produce_collector]
            }]
    end.

normalize_pool_size({each_scheduler, Base}) ->
    max(1, round(Base * erlang:system_info(schedulers)));
normalize_pool_size(Number) when is_number(Number)  ->

    max(1, round(Number)).
