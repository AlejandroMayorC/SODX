-module(wait).
-export([hello/0, start/0]).

hello() ->
    receive
        Message -> io:format("Received: ~p~n", [Message])
    end.

start() ->
    P = spawn(wait, hello, []),
    P ! "hello".
