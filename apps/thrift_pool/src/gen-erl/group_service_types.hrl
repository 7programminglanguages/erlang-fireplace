-ifndef(_group_service_types_included).
-define(_group_service_types_included, yeah).

-define(GROUP_SERVICE_GROUPERRORCODE_UNKNOWN, 1).
-define(GROUP_SERVICE_GROUPERRORCODE_FAIL, 2).
-define(GROUP_SERVICE_GROUPERRORCODE_BAD_REQUEST, 3).
-define(GROUP_SERVICE_GROUPERRORCODE_DB_ERROR, 4).
-define(GROUP_SERVICE_GROUPERRORCODE_GROUP_NOT_EXIST, 5).

%% struct 'GroupException'

-record('GroupException', {'errorCode' :: integer(),
                           'reason' :: string() | binary()}).
-type 'GroupException'() :: #'GroupException'{}.

%% struct 'ApnsBlockConfig'

-record('ApnsBlockConfig', {'userId' :: integer(),
                            'blockType' :: integer()}).
-type 'ApnsBlockConfig'() :: #'ApnsBlockConfig'{}.

-endif.
