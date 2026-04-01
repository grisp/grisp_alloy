%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_cli).
-moduledoc """
Command-line parser and dispatcher for `smelterl`.

This module handles global options, resolves the target command handler, and
parses command-local long options before handing execution to the command
module.
""".

%=== EXPORTS ===================================================================

-export([run/2]).
-export_type([option_spec/0]).


%=== TYPES =====================================================================

-doc """
Description of one supported command-line option.

`name` is the atom stored in the parsed option map, `long` is the CLI long
option name without the leading `--`, and `type` controls how the parser
consumes values.
""".
-type option_spec() :: #{
    name := atom(),
    long := string(),
    type := flag | value | accum
}.


%=== API FUNCTIONS =============================================================

-doc """
Parse one `smelterl` argv list and run the selected command.

Returns an exit status code instead of terminating the VM directly so callers
can compose it into escript or test harness entrypoints.
""".
-spec run([string()], smelterl:smelterl_config()) -> integer().
run(Argv, Config) ->
    case first_pass(Argv) of
        {error, Message} ->
            print_error(Message),
            2;
        {ok, #{version := true}} ->
            io:format("smelterl ~ts~n", [maps:get(version, Config)]),
            0;
        {ok, #{help := true, command := undefined}} ->
            io:put_chars(global_help(Config)),
            0;
        {ok, #{command := undefined}} ->
            print_error("smelterl requires a command. Use --help for usage."),
            2;
        {ok, #{command := Command, rest := Rest}} ->
            dispatch(Command, Rest, Config)
    end.


%=== INTERNAL FUNCTIONS ========================================================

dispatch(Command, Rest, Config) ->
    Handlers = maps:get(command_handlers, Config),
    case maps:get(Command, Handlers, undefined) of
        undefined ->
            print_error(
                io_lib:format(
                    "Unknown command: ~ts",
                    [atom_to_list(Command)]
                )
            ),
            2;
        Module ->
            Action = resolve_action(Command, Module),
            Spec = Module:options_spec(Action),
            case parse_command_args(Rest, Spec, #{}) of
                {error, Message} ->
                    print_error(Message),
                    2;
                {ok, Opts} ->
                    case maps:get(help, Opts, false) of
                        true ->
                            io:put_chars(Module:help(Action)),
                            0;
                        false ->
                            Module:run(Action, maps:remove(help, Opts))
                    end
            end
    end.

resolve_action(Command, Module) ->
    case Module:actions() of
        [Action] ->
            Action;
        Actions when is_list(Actions) ->
            Command
    end.

first_pass(Argv) ->
    first_pass(
        Argv,
        #{help => false, version => false, command => undefined, rest => []}
    ).

first_pass([], State) ->
    {ok, State};
first_pass(["--help" | Rest], State) ->
    first_pass(Rest, State#{help := true});
first_pass(["-h" | Rest], State) ->
    first_pass(["--help" | Rest], State);
first_pass(["--version" | Rest], State) ->
    first_pass(Rest, State#{version := true});
first_pass(["-v" | Rest], State) ->
    first_pass(["--version" | Rest], State);
first_pass([Token | _], _State)
  when is_list(Token), Token =/= [], hd(Token) =:= $- ->
    {error, io_lib:format("Unknown global option: ~ts", [Token])};
first_pass([Token | Rest], State) ->
    {ok, State#{command := list_to_atom(Token), rest := Rest}}.

parse_command_args([], _Spec, Opts) ->
    {ok, Opts};
parse_command_args(["--" | Rest], _Spec, _Opts) ->
    {error,
        io_lib:format(
            "Unexpected positional arguments: ~ts",
            [string:join(Rest, " ")]
        )};
parse_command_args([Token | Rest], Spec, Opts) ->
    case Token of
        "--help" ->
            parse_command_args(Rest, Spec, Opts#{help => true});
        "-h" ->
            parse_command_args(Rest, Spec, Opts#{help => true});
        _ when is_list(Token), Token =/= [], hd(Token) =:= $- ->
            case split_long_option(Token) of
                {error, Message} ->
                    {error, Message};
                {ok, Name, Attached} ->
                    case option_by_long(Name, Spec) of
                        undefined ->
                            {error,
                                io_lib:format(
                                    "plan: unknown argument '~ts'",
                                    [Token]
                                )};
                        OptionSpec ->
                            parse_option(
                                Rest,
                                Spec,
                                Opts,
                                OptionSpec,
                                Token,
                                Attached
                            )
                    end
            end;
        _ ->
            {error,
                io_lib:format(
                    "plan: unexpected positional argument '~ts'",
                    [Token]
                )}
    end.

parse_option(Rest, Spec, Opts, #{name := Name, type := flag}, Token, Attached) ->
    case Attached of
        undefined ->
            parse_command_args(Rest, Spec, Opts#{Name => true});
        _ ->
            {error,
                io_lib:format(
                    "plan: option '~ts' does not take a value",
                    [Token]
                )}
    end;
parse_option(Rest, Spec, Opts, #{name := Name, type := value}, _Token, Attached) ->
    case Attached of
        undefined ->
            case Rest of
                [Value | Tail] ->
                    parse_command_args(Tail, Spec, Opts#{Name => Value});
                [] ->
                    {error,
                        io_lib:format(
                            "plan: option '--~ts' requires a value",
                            [atom_to_list(Name)]
                        )}
            end;
        Value ->
            parse_command_args(Rest, Spec, Opts#{Name => Value})
    end;
parse_option(Rest, Spec, Opts, #{name := Name, type := accum}, _Token, Attached) ->
    case Attached of
        undefined ->
            case Rest of
                [Value | Tail] ->
                    Values = maps:get(Name, Opts, []),
                    parse_command_args(Tail, Spec, Opts#{Name => Values ++ [Value]});
                [] ->
                    {error,
                        io_lib:format(
                            "plan: option '--~ts' requires a value",
                            [atom_to_list(Name)]
                        )}
            end;
        Value ->
            Values = maps:get(Name, Opts, []),
            parse_command_args(Rest, Spec, Opts#{Name => Values ++ [Value]})
    end.

split_long_option([$-, $- | Rest]) ->
    case string:split(Rest, "=", all) of
        [Name] ->
            {ok, Name, undefined};
        [Name, Value] ->
            {ok, Name, Value};
        [Name | Tail] ->
            {ok, Name, string:join(Tail, "=")}
    end;
split_long_option(Token) ->
    {error, io_lib:format("plan: unknown argument '~ts'", [Token])}.

option_by_long(Name, Spec) ->
    lists:foldl(
        fun(Entry, Acc) ->
            case Acc of
                undefined ->
                    case maps:get(long, Entry) of
                        Name -> Entry;
                        _ -> undefined
                    end;
                _ ->
                    Acc
            end
        end,
        undefined,
        Spec
    ).

global_help(Config) ->
    Commands = maps:keys(maps:get(command_handlers, Config)),
    Sorted = lists:sort(Commands),
    CommandLines = [
        io_lib:format("  ~ts~n", [atom_to_list(Command)])
     || Command <- Sorted
    ],
    [
        "Usage: smelterl <command> [options]\n\n",
        "Commands:\n",
        CommandLines,
        "\nGlobal options:\n",
        "  --help, -h     Show help (global or command-specific)\n",
        "  --version, -v  Show smelterl version\n"
    ].

print_error(Message) ->
    io:format(standard_error, "~ts~n", [Message]).
