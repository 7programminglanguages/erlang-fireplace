%%%-------------------------------------------------------------------
%%% @author jinhai <jinhai@bmxlabs.com>
%%% @doc
%%%
%%% @end
%%% Created :  6 Nov 2018
%%%-------------------------------------------------------------------

-compile([{parse_transform, lager_transform}]).

-define(DEBUG(Format, Args),
        lager:debug(Format, Args)).

-define(INFO_MSG(Format, Args),
        lager:info(Format, Args)).

-define(WARNING_MSG(Format, Args),
        lager:warning(Format, Args)).

-define(ERROR_MSG(Format, Args),
        lager:error(Format, Args)).

-define(CRITICAL_MSG(Format, Args),
        lager:critical(Format, Args)).
