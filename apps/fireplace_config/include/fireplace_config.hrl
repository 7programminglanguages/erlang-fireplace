-compile([{parse_transform, lager_transform}]).
-define(DEBUG(Format, Args),
        case whereis(lager_event) of
            undefined ->
                error_logger:info_msg(Format, Args);
            _ ->
                lager:debug(Format, Args)
        end).


-define(INFO_MSG(Format, Args),
        case whereis(lager_event) of
            undefined ->
                error_logger:info_msg(Format, Args);
            _ ->
                lager:info(Format, Args)
        end).

-define(WARNING_MSG(Format, Args),
        case whereis(lager_event) of
            undefined ->
                error_logger:info_msg(Format, Args);
            _ ->
                lager:warning(Format, Args)
        end).

-define(ERROR_MSG(Format, Args),
        case whereis(lager_event) of
            undefined ->
                error_logger:error_msg(Format, Args);
            _ ->
                lager:error(Format, Args)
        end).

-define(CRITICAL_MSG(Format, Args),
        case whereis(lager_event) of
            undefined ->
                error_logger:info_msg(Format, Args);
            _ ->
                lager:critical(Format, Args)
        end).
