-module(smelterl).

-export([main/1]).
-export_type([smelterl_config/0]).

-type smelterl_config() :: #{
    command_handlers := #{atom() => module()},
    version := string()
}.

-spec main([string()]) -> integer().
main(Argv) ->
    ok = ensure_application_loaded(),
    Config = #{
        command_handlers => command_handlers(),
        version => version()
    },
    smelterl_cli:run(Argv, Config).

ensure_application_loaded() ->
    case application:load(smelterl) of
        ok -> ok;
        {error, {already_loaded, smelterl}} -> ok
    end.

command_handlers() ->
    {ok, Handlers} = application:get_env(smelterl, command_handlers),
    maps:from_list(Handlers).

version() ->
    case application:get_env(smelterl, version) of
        {ok, Version} -> Version;
        undefined ->
            case application:get_key(smelterl, vsn) of
                {ok, Version} -> Version;
                undefined -> "dev"
            end
    end.
