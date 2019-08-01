%%%-------------------------------------------------------------------------------------------------
%%% File    :  message_store_const.hrl
%%% Author  :  XiangKui <xiangkui@bmxlabs.com>
%%% Purpose :  message_store interface
%%% Created :  14 Nov 2018 by XiangKui <xiangkui@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------

% odbc
-define(ODBC_SERVICE_NAME, odbc).

% device
-define(DEFAULT_DEVICE, 0).

% chat
-define(REDIS_INDEX_SERVICE, index).
-define(UNREAD_MID_LIST_KEY_PREFIX, <<"uri:">>).
-define(UNREAD_CONVERSATION_KEY_PREFIX, <<"urn:">>).

% group chat
-define(UNREAD_SHARE_LIST_KEY_PREFIX, <<"shr:">>).
-define(UNREAD_CURSOR_KEY_PREFIX, <<"cur:">>).

% body
-define(REDIS_BODY_SERVICE, body).
-define(REDIS_BODY_KEY_PREFIX, <<"bd:">>).
-define(REDIS_BODY_TTL, 604800).  % second

% id cache
-define(ID_CACHE_SERVICE, idcache).
-define(ID_CACHE_PREFIX, <<"ic:">>).
-define(ID_CACHE_TTL, 120).  % second

% chat type
-define(CHAT, 0).
-define(GROUP_CHAT, 1).

% limit
-define(SYNC_MSG_NUM_LIMIT, 200).

-define(REDIS_LRANGE_LIMIT, 500).
-define(REDIS_CHAT_MID_LIMIT, 200).
-define(REDIS_CHAT_MID_MAX, 300).
-define(REDIS_GROUPCHAT_MID_LIMIT, 200).
-define(REDIS_GROUPCHAT_MID_MAX, 300).

-define(MYSQL_ROAM_LIMIT, 300).

% apns
-define(REDIS_APNS_SERVICE, apns).
-define(REDIS_APNS_KEY_PREFIX, <<"pn:">>).

% total key
-define(TOTAL_KEY, <<"t">>).

