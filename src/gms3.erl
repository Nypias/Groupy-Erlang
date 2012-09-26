-module(gms3).
-export([start/1, start/2]).

-define(timeout, 1000).
-define(arghh, 100).

start(Id) ->
    Rnd = random:uniform(1000),
    Self = self(),
    spawn_link(fun() -> init(Id, Rnd, Self) end).

init(Id, Rnd, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id, Master, 1, [], [Master]).

start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Self = self(),
    spawn_link(fun() -> init(Id, Rnd, Grp, Self) end).

init(Id, Rnd, Grp, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    Self = self(),
    Grp ! {join, Master, Self},
    receive
	{view, N, [Leader|Slaves], Group} ->
	    Master ! {view, Group},
	    erlang:monitor(process, Leader),
	    slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group}, Slaves, Group)
    after ?timeout ->
	    Master ! {error, "no reply from leader"}
    end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
    receive
	{mcast, Msg} ->
	    Leader ! {mcast, Msg},
	    slave(Id, Master, Leader, N, Last, Slaves, Group);
	{join, Wrk, Peer} ->
	    Leader ! {join, Wrk, Peer},
	    slave(Id, Master, Leader, N, Last, Slaves, Group);
	{msg, N, Msg} ->
	    Master ! Msg,
	    slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);
	{msg, I, _} when I < N->
	    slave(Id, Master, Leader, N, Last, Slaves, Group);
	{view, N, [Leader|Slaves2], Group2} ->
	    Master ! {view, Group2},
	    slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves2], Group2}, Slaves2, Group2);
	{'DOWN', _Ref, process, Leader, _Reason} ->
	    election(Id, Master, N, Last, Slaves, Group);
	stop ->
	    ok;
	Error ->
	    io:format("gms ~w: slave, strange message ~w~n", [Id, Error])
    end.


leader(Id, Master, N, Slaves, Group) ->
    receive
	{mcast, Msg} ->
	    bcast(Id, {msg, N, Msg}, Slaves),
	    Master ! Msg,
	    leader(Id, Master, N+1, Slaves, Group);
	{join, Wrk, Peer} ->
	    Slaves2 = lists:append(Slaves, [Peer]),
	    Group2 = lists:append(Group, [Wrk]),
	    bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
	    Master ! {view, Group2},
	    leader(Id, Master, N+1, Slaves2, Group2);
	stop ->
	    ok;
	Error ->
	    io:format("gms ~w: leader, strange message ~w~n", [Id, Error])
    end.

bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> Node ! Msg, crash(Id) end, Nodes).

crash(Id) ->
    case random:uniform(?arghh) of
	?arghh ->
	    io:format("leader ~w: crash~n", [Id]),
	    exit(no_luck);
	_ ->
	    ok
    end.

election(Id, Master, N, Last, Slaves, [_|Group]) ->
    Self = self(),
    case Slaves of
	[Self|Rest] ->
	    bcast(Id, Last, Rest),
	    bcast(Id, {view, N, Slaves, Group}, Rest),
	    Master ! {view, Group},
	    leader(Id, Master, N+1, Rest, Group);
	[Leader|Rest] ->
	    erlang:monitor(process, Leader),
	    slave(Id, Master, Leader, N, Last, Rest, Group)
    end.
