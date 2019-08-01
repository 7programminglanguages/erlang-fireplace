-ifndef(_xsync_service_types_included).
-define(_xsync_service_types_included, yeah).

-define(XSYNC_SERVICE_XSYNCERRORCODE_DB_ERROR, 1).
-define(XSYNC_SERVICE_XSYNCERRORCODE_TIMEOUT, 2).
-define(XSYNC_SERVICE_XSYNCERRORCODE_INVALID_PARAMETER, 3).

%% struct 'ConversationMessages'

-record('ConversationMessages', {'messages' = [] :: list(),
                                 'is_last' :: boolean()}).
-type 'ConversationMessages'() :: #'ConversationMessages'{}.

%% struct 'Unread'

-record('Unread', {'conversationId' :: 'XID'(),
                   'num' :: integer()}).
-type 'Unread'() :: #'Unread'{}.

%% struct 'XID'

-record('XID', {'uid' :: integer(),
                'deviceSN' :: integer()}).
-type 'XID'() :: #'XID'{}.

%% struct 'Message'

-record('Message', {'from_xid' = #'XID'{} :: 'XID'(),
                    'to_xid' = #'XID'{} :: 'XID'(),
                    'msgId' :: integer(),
                    'timestamp' :: integer(),
                    'ctype' :: string() | binary(),
                    'content' :: string() | binary(),
                    'config' :: string() | binary(),
                    'attachment' :: string() | binary(),
                    'ext' :: string() | binary()}).
-type 'Message'() :: #'Message'{}.

%% struct 'XSyncException'

-record('XSyncException', {'errorCode' :: integer(),
                           'reason' :: string() | binary()}).
-type 'XSyncException'() :: #'XSyncException'{}.

-endif.
