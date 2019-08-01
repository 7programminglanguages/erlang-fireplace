%%%-------------------------------------------------------------------------------------------------
%%% File    :  msgst_shaper.erl
%%% Author  :  JinHai <jinhai@bmxlabs.com>
%%% Purpose :
%%% Created :  5 Dec 2018 by JinHai <jinhai@bmxlabs.com>
%%%-------------------------------------------------------------------------------------------------
%%%
%%%                    Copyright (C) 2018-2019   MaxIM.Top
%%%
%%% You may obtain a copy of the licence at http://www.maxim.top/LICENCE-MAXIM.md
%%%
%%%-------------------------------------------------------------------------------------------------
-module(msgst_shaper).

-export([new/2, update/2, change/2]).

-record(avgrate, {
                  avgrate,
                  lasttime,
                  lastsize
                 }).

new(_, none) ->
    none;
new(max, Speed) ->
    p1_shaper:new(Speed);
new(avg, Speed) ->
    #avgrate{avgrate = Speed,
             lasttime = usec(),
             lastsize = 0}.

update(none, _) ->
    {none, 0};
update(#avgrate{avgrate=AvgRate, lastsize = LastSize, lasttime = LastTime} = State, Size) ->
    Now = usec(),
    MinInterv = 1000 * (LastSize + Size) / AvgRate,
    Interv = (Now - LastTime) / 1000,
    case Interv > 2000 of
        true ->
            {State#avgrate{lasttime = Now, lastsize = Size}, 0};
        false ->
            Pause = if
                        MinInterv - Interv >= 1 ->
                            trunc(MinInterv - Interv);
                        true ->
                            0
                    end,
            NextTime = Now + Pause * 1000,
            NewState =
                if
                    NextTime > LastTime + 1000000 ->
                        State#avgrate{
                          lasttime = (LastTime+NextTime) / 2,
                          lastsize = (LastSize+Size) /2
                         };
                    true ->
                        State#avgrate{
                          lastsize = LastSize + Size
                         }
                end,
            {NewState, Pause}
    end;
update(State, Speed) ->
    p1_shaper:update(State, Speed).

change(#avgrate{}=State, Speed) ->
    State#avgrate{avgrate = Speed};
change(none, _Speed) ->
    none;
change(State, Speed) ->
    p1_shaper:new(Speed).

usec() ->
   erlang:monotonic_time(micro_seconds).
