-module(hello).

-on_load(init/0).

-export([init/0, world/0]).

-define(APPNAME, hello_grisp).
-define(LIBNAME, hello_grisp).

world() ->
      "NIF library not loaded".

init() ->
    SoName = case code:priv_dir(?APPNAME) of
        {error, bad_name} ->
            case filelib:is_dir(filename:join(["..", priv])) of
                true -> filename:join(["..", priv, ?LIBNAME]);
                _ -> filename:join([priv, ?LIBNAME])
            end;
        Dir -> filename:join(Dir, ?LIBNAME)
    end,
    erlang:load_nif(SoName, 0).
