%%
%% Autogenerated by Thrift Compiler (0.11.0)
%%
%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
%%

-module(roster_service_types).

-include("roster_service_types.hrl").

-export([struct_info/1, struct_info_ext/1, enum_info/1, enum_names/0, struct_names/0, exception_names/0]).

struct_info('RosterException') ->
  {struct, [{1, i32},
          {2, string}]}
;

struct_info(_) -> erlang:error(function_clause).

struct_info_ext('RosterException') ->
  {struct, [{1, required, i32, 'errorCode', undefined},
          {2, required, string, 'reason', undefined}]}
;

struct_info_ext(_) -> erlang:error(function_clause).

struct_names() ->
  [].

enum_info('RosterErrorCode') ->
  [
    {'UNKNOWN', 1},
    {'FAIL', 2},
    {'BAD_REQUEST', 3},
    {'DB_ERROR', 4}
  ];

enum_info(_) -> erlang:error(function_clause).

enum_names() ->
  ['RosterErrorCode'].

exception_names() ->
  ['RosterException'].

