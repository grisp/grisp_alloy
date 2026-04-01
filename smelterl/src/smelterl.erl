%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl).
-moduledoc """
Main `smelterl` escript entrypoint.

This module loads the application configuration needed by the CLI and then
delegates argument handling to `smelterl_cli`.
""".

%=== EXPORTS ===================================================================

-export([main/1]).
-export_type([smelterl_config/0]).


%=== TYPES =====================================================================

-doc """
Runtime configuration passed into the CLI dispatcher.

The command-handlers map selects the module that owns each top-level command,
and the version string is shown by `--version`.
""".
-type smelterl_config() :: #{
    command_handlers := #{atom() => module()},
    version := string()
}.


%=== API FUNCTIONS =============================================================

-doc """
Run the `smelterl` command-line entrypoint for one argv list.

Returns the process exit status that the outer escript wrapper should use.
""".
-spec main([string()]) -> integer().
main(Argv) ->
    ok = ensure_application_loaded(),
    Config = #{
        command_handlers => command_handlers(),
        version => version()
    },
    smelterl_cli:run(Argv, Config).


%=== INTERNAL FUNCTIONS ========================================================

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
        {ok, Version} ->
            Version;
        undefined ->
            case application:get_key(smelterl, vsn) of
                {ok, Version} -> Version;
                undefined -> "dev"
            end
    end.
