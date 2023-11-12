-module(lock3).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(Id) ->
    receive
        {peers, Nodes} ->
            open(Id, Nodes, 0);
        stop ->
            ok
    end.

open(Id, Nodes, Clock) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Id, Nodes, Clock),
            wait(Id, Nodes, Master, Refs, [], Ref, Clock);
        {request, From, OtherId, Ref, Timestamp} ->
            NewClock = max(Clock, Timestamp),
            From ! {ok, Ref},
            open(Id, Nodes, NewClock);
        stop ->
            ok
    end.

requests(Id, Nodes, Clock) ->
    NewClock = Clock + 1,
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), Id, R, NewClock}, 
        R 
      end, 
      Nodes).

wait(Id, Nodes, Master, Refs, Waiting, TakeRef, Clock) ->
    receive
        {request, From, OtherId, Ref, Timestamp} when Timestamp < Clock ->
            From ! {ok, Ref},
            wait(Id, Nodes, Master, Refs, Waiting, TakeRef, Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp > Clock ->
            wait(Id, Nodes, Master, Refs, [{From, Ref, Timestamp}|Waiting], TakeRef, Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp =:= Clock, OtherId < Id ->
            From ! {ok, Ref},
            wait(Id, Nodes, Master, Refs, Waiting, TakeRef, Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp =:= Clock, OtherId > Id ->
            wait(Id, Nodes, Master, Refs, [{From, Ref, Timestamp}|Waiting], TakeRef, Clock);
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            Master ! {taken, TakeRef},
            held(Nodes, Master, NewRefs, Waiting, Clock);
        release ->
            ok(Waiting),            
            open(Id, Nodes, Clock)
    end.

ok(Waiting) ->
    lists:map(
      fun({F,R,_}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Master, Refs, Waiting, Clock) ->
    receive
        {request, From, OtherId, Ref, Timestamp} when Timestamp < Clock ->
            From ! {ok, Ref},
            held(Nodes, Master, Refs, Waiting, Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp > Clock ->
            held(Nodes, Master, Refs, [{From, Ref, Timestamp}|Waiting], Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp =:= Clock, OtherId < Id ->
            From ! {ok, Ref},
            held(Nodes, Master, Refs, Waiting, Clock);
        {request, From, OtherId, Ref, Timestamp} when Timestamp =:= Clock, OtherId > Id ->
            held(Nodes, Master, Refs, [{From, Ref, Timestamp}|Waiting], Clock);
        release ->
            ok(Waiting),
            open(Id, Nodes, Clock)
    end.
