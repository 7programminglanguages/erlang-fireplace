-ifndef(_user_service_types_included).
-define(_user_service_types_included, yeah).

%% struct 'DeviceDetail'

-record('DeviceDetail', {'deviceSN' :: integer(),
                         'deviceUUID' :: string() | binary(),
                         'deviceToken' :: string() | binary(),
                         'notifier' :: string() | binary(),
                         'deviceInfo' :: string() | binary(),
                         'platform' :: integer()}).
-type 'DeviceDetail'() :: #'DeviceDetail'{}.

%% struct 'UserDevice'

-record('UserDevice', {'deviceSN' :: integer(),
                       'deviceUUID' :: string() | binary()}).
-type 'UserDevice'() :: #'UserDevice'{}.

-endif.
