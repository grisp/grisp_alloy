%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_cmd_plan).
-moduledoc """
`smelterl plan` command implementation.

This module exposes the command metadata consumed by `smelterl_cli` and owns
the current `plan` execution stub, including required-option validation and
motherlode loading error formatting.
""".

-behaviour(smelterl_command).

%=== EXPORTS ===================================================================

-export([actions/0]).
-export([help/1]).
-export([options_spec/1]).
-export([run/2]).


%=== BEHAVIOUR smelterl_command CALLBACKS ======================================

actions() ->
    [plan].

options_spec(plan) ->
    [
        #{name => product, long => "product", type => value},
        #{name => motherlode, long => "motherlode", type => value},
        #{name => output_plan, long => "output-plan", type => value},
        #{name => output_plan_env, long => "output-plan-env", type => value},
        #{name => extra_config, long => "extra-config", type => accum},
        #{name => log, long => "log", type => value},
        #{name => verbose, long => "verbose", type => flag},
        #{name => debug, long => "debug", type => flag}
    ].

help(plan) ->
    [
        "Usage: smelterl plan [OPTIONS]\n\n",
        "Required:\n",
        "  --product ID           Main product nugget identifier\n",
        "  --motherlode PATH      Staged nugget repository directory\n",
        "  --output-plan PATH     Output path for build_plan.term\n\n",
        "Optional:\n",
        "  --output-plan-env PATH Output path for build_plan.env\n",
        "  --extra-config K=V     Repeatable plan-time extra config\n",
        "  --log LEVEL            Logging level\n",
        "  --verbose              Enable verbose logging\n",
        "  --debug                Enable debug logging\n",
        "  --help, -h             Show this help text\n"
    ].

run(plan, Opts) ->
    case require_options(Opts) of
        ok ->
            run_plan(Opts);
        {error, Message} ->
            io:format(standard_error, "~ts~n", [Message]),
            2
    end.


%=== INTERNAL FUNCTIONS ========================================================

run_plan(Opts) ->
    case smelterl_motherlode:load(maps:get(motherlode, Opts)) of
        {ok, _Motherlode} ->
            io:format(
                standard_error,
                "plan execution not implemented yet.~n",
                []
            ),
            1;
        {error, Reason} ->
            io:format(standard_error, "~ts~n", [format_load_error(Reason)]),
            1
    end.

require_options(Opts) ->
    case maps:get(product, Opts, undefined) of
        undefined ->
            {error, "plan requires --product."};
        [] ->
            {error, "plan requires --product."};
        _ ->
            case maps:get(motherlode, Opts, undefined) of
                undefined ->
                    {error, "plan requires --motherlode."};
                [] ->
                    {error, "plan requires --motherlode."};
                _ ->
                    case maps:get(output_plan, Opts, undefined) of
                        undefined ->
                            {error, "plan requires --output-plan."};
                        [] ->
                            {error, "plan requires --output-plan."};
                        _ ->
                            ok
                    end
            end
    end.

format_load_error({invalid_path, Path, Posix}) ->
    io_lib:format("plan: invalid motherlode path '~ts': ~tp", [Path, Posix]);
format_load_error({invalid_registry, RepoPath, Detail}) ->
    io_lib:format(
        "plan: invalid nugget registry in '~ts': ~ts",
        [RepoPath, format_detail(Detail)]
    );
format_load_error({missing_metadata, RepoPath, NuggetRelPath}) ->
    io_lib:format(
        "plan: nugget metadata '~ts' listed by '~ts/.nuggets' does not exist",
        [NuggetRelPath, RepoPath]
    );
format_load_error({invalid_metadata, RepoPath, NuggetRelPath, Detail}) ->
    io_lib:format(
        "plan: invalid nugget metadata '~ts/~ts': ~ts",
        [RepoPath, NuggetRelPath, format_detail(Detail)]
    );
format_load_error({duplicated_nugget_id, NuggetId, RepoPath1, RepoPath2}) ->
    io_lib:format(
        "plan: duplicated nugget id '~ts' in '~ts' and '~ts'",
        [atom_to_list(NuggetId), RepoPath1, RepoPath2]
    );
format_load_error({missing_file, RepoPath, NuggetRelPath, FileRelPath, Detail}) ->
    io_lib:format(
        "plan: missing referenced file '~ts' for '~ts/~ts': ~ts",
        [FileRelPath, RepoPath, NuggetRelPath, format_detail(Detail)]
    );
format_load_error(Reason) ->
    io_lib:format("plan: motherlode loading failed: ~tp", [Reason]).

format_detail({parse_error, FileError}) ->
    io_lib:format("~tp", [FileError]);
format_detail(Detail) when is_atom(Detail) ->
    atom_to_list(Detail);
format_detail(Detail) ->
    io_lib:format("~tp", [Detail]).
