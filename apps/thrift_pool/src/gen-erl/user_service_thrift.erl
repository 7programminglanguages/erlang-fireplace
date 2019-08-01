%%
%% Autogenerated by Thrift Compiler (0.11.0)
%%
%% DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
%%

-module(user_service_thrift).
-behaviour(thrift_service).


-include("user_service_thrift.hrl").

-export([struct_info/1, function_info/2, function_names/0]).

struct_info(_) -> erlang:error(function_clause).
%%% interface
% createDevice(This, UserId, DeviceDetail)
function_info('createDevice', params_type) ->
  {struct, [{1, i64},
          {2, {struct, {'user_service_types', 'DeviceDetail'}}}]}
;
function_info('createDevice', reply_type) ->
  bool;
function_info('createDevice', exceptions) ->
  {struct, []}
;
% updateDevice(This, UserId, DeviceDetail)
function_info('updateDevice', params_type) ->
  {struct, [{1, i64},
          {2, {struct, {'user_service_types', 'DeviceDetail'}}}]}
;
function_info('updateDevice', reply_type) ->
  bool;
function_info('updateDevice', exceptions) ->
  {struct, []}
;
% deleteDevice(This, UserId, DeviceSN)
function_info('deleteDevice', params_type) ->
  {struct, [{1, i64},
          {2, i32}]}
;
function_info('deleteDevice', reply_type) ->
  bool;
function_info('deleteDevice', exceptions) ->
  {struct, []}
;
% getUserDevices(This, UserId)
function_info('getUserDevices', params_type) ->
  {struct, [{1, i64}]}
;
function_info('getUserDevices', reply_type) ->
  {list, {struct, {'user_service_types', 'UserDevice'}}};
function_info('getUserDevices', exceptions) ->
  {struct, []}
;
function_info(_Func, _Info) -> erlang:error(function_clause).

function_names() -> 
  ['createDevice', 'updateDevice', 'deleteDevice', 'getUserDevices'].
