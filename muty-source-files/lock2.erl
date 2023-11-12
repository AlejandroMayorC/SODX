-module(lock2).
-export([start/1]).

start(MyId) ->
    spawn(fun() -> init(MyId) end).

init(MyId) ->
    receive
        {peers, Nodes} ->
            open(Nodes, MyId);
        stop ->
            ok
    end.

open(Nodes, MyId) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, MyId),
            wait(Nodes, Master, Refs, [], Ref, MyId);
        {request, From, Ref, FromId} when MyId > FromId ->
            From ! {ok, Ref},
            open(Nodes, MyId);
        {request, From, Ref, FromId} ->
            open(Nodes, MyId, [{From, Ref, FromId}]);
        stop ->
            ok
    end.

open(Nodes, MyId, Waiting) ->
    receive
        {take, Master, Ref} ->
            Refs = requests(Nodes, MyId),
            wait(Nodes, Master, Refs, Waiting, Ref, MyId);
        {request, From, Ref, FromId} ->
            open(Nodes, MyId, [{From, Ref, FromId}|Waiting]);
        stop ->
            ok
    end.

requests(Nodes, MyId) ->
    lists:map(
      fun(P) -> 
        R = make_ref(), 
        P ! {request, self(), R, MyId}, 
        R 
      end, 
      Nodes).

wait(Nodes, Master, [], Waiting, TakeRef, MyId) ->
    Master ! {taken, TakeRef},
    held(Nodes, Waiting, MyId);
wait(Nodes, Master, Refs, Waiting, TakeRef, MyId) ->
    receive
        {request, From, Ref, FromId} ->
            wait(Nodes, Master, Refs, [{From, Ref, FromId}|Waiting], TakeRef, MyId);
        {ok, Ref} ->
            NewRefs = lists:delete(Ref, Refs),
            wait(Nodes, Master, NewRefs, Waiting, TakeRef, MyId);
        release ->
            ok(Waiting),            
            open(Nodes, MyId)
    end.

ok(Waiting) ->
    lists:map(
      fun({F,R, _}) -> 
        F ! {ok, R} 
      end, 
      Waiting).

held(Nodes, Waiting, MyId) ->
    receive
        {request, From, Ref, FromId} ->
            held(Nodes, [{From, Ref, FromId}|Waiting], MyId);
        release ->
            ok(Waiting),
            open(Nodes, MyId)
    end.
