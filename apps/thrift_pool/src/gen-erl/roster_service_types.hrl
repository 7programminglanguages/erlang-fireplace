-ifndef(_roster_service_types_included).
-define(_roster_service_types_included, yeah).

-define(ROSTER_SERVICE_ROSTERERRORCODE_UNKNOWN, 1).
-define(ROSTER_SERVICE_ROSTERERRORCODE_FAIL, 2).
-define(ROSTER_SERVICE_ROSTERERRORCODE_BAD_REQUEST, 3).
-define(ROSTER_SERVICE_ROSTERERRORCODE_DB_ERROR, 4).

%% struct 'RosterException'

-record('RosterException', {'errorCode' :: integer(),
                            'reason' :: string() | binary()}).
-type 'RosterException'() :: #'RosterException'{}.

-endif.
