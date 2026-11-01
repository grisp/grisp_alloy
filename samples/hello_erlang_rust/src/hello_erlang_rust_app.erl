-module(hello_erlang_rust_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    io:format("~ts~n", [hello_rust_nif:world()]),
    hello_erlang_rust_sup:start_link().

stop(_State) ->
    ok.
