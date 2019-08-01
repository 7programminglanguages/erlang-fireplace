%%
%% Autogenerated by Thrift Compiler (0.11.0)
%%
%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
%%

-module(xsync_service_types).

-include("xsync_service_types.hrl").

-export([struct_info/1, struct_info_ext/1, enum_info/1, enum_names/0, struct_names/0, exception_names/0]).

struct_info('ConversationMessages') ->
  {struct, [{1, {list, {struct, {'xsync_service_types', 'Message'}}}},
          {2, bool}]}
;

struct_info('Unread') ->
  {struct, [{1, {struct, {'xsync_service_types', 'XID'}}},
          {2, i32}]}
;

struct_info('XID') ->
  {struct, [{1, i64},
          {3, i32}]}
;

struct_info('Message') ->
  {struct, [{1, {struct, {'xsync_service_types', 'XID'}}},
          {2, {struct, {'xsync_service_types', 'XID'}}},
          {3, i64},
          {4, i64},
          {5, string},
          {6, string},
          {7, string},
          {8, string},
          {9, string}]}
;

struct_info('XSyncException') ->
  {struct, [{1, i32},
          {2, string}]}
;

struct_info(_) -> erlang:error(function_clause).

struct_info_ext('ConversationMessages') ->
  {struct, [{1, required, {list, {struct, {'xsync_service_types', 'Message'}}}, 'messages', []},
          {2, required, bool, 'is_last', undefined}]}
;

struct_info_ext('Unread') ->
  {struct, [{1, required, {struct, {'xsync_service_types', 'XID'}}, 'conversationId', undefined},
          {2, required, i32, 'num', undefined}]}
;

struct_info_ext('XID') ->
  {struct, [{1, optional, i64, 'uid', undefined},
          {3, optional, i32, 'deviceSN', undefined}]}
;

struct_info_ext('Message') ->
  {struct, [{1, required, {struct, {'xsync_service_types', 'XID'}}, 'from_xid', #'XID'{}},
          {2, required, {struct, {'xsync_service_types', 'XID'}}, 'to_xid', #'XID'{}},
          {3, required, i64, 'msgId', undefined},
          {4, required, i64, 'timestamp', undefined},
          {5, optional, string, 'ctype', undefined},
          {6, optional, string, 'content', undefined},
          {7, optional, string, 'config', undefined},
          {8, optional, string, 'attachment', undefined},
          {9, optional, string, 'ext', undefined}]}
;

struct_info_ext('XSyncException') ->
  {struct, [{1, required, i32, 'errorCode', undefined},
          {2, required, string, 'reason', undefined}]}
;

struct_info_ext(_) -> erlang:error(function_clause).

struct_names() ->
  ['ConversationMessages', 'Unread', 'XID', 'Message'].

enum_info('XsyncErrorCode') ->
  [
    {'DB_ERROR', 1},
    {'TIMEOUT', 2},
    {'INVALID_PARAMETER', 3}
  ];

enum_info(_) -> erlang:error(function_clause).

enum_names() ->
  ['XsyncErrorCode'].

exception_names() ->
  ['XSyncException'].

