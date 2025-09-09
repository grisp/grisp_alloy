%%%-------------------------------------------------------------------
%% @doc hello_grisp public API
%% @end
%%%-------------------------------------------------------------------

-module(hello_grisp_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    io:format(">>>>> ~s~n", [hello:world()]),
    io:format("Config: ~p~n", [application:get_env(hello_grisp, key)]),
    hello_grisp_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
