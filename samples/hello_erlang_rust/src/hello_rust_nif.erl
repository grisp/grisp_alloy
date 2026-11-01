-module(hello_rust_nif).
-on_load(init/0).
-export([world/0]).

init() ->
    erlang:load_nif(filename:join(code:priv_dir(hello_erlang_rust), "hello_rust_nif"), 0).

world() ->
    erlang:nif_error(nif_not_loaded).
