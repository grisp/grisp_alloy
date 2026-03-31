-module(smelterl_cmd_plan).

-behaviour(smelterl_command).

-export([actions/0, help/1, options_spec/1, run/2]).

-spec actions() -> [atom()].
actions() ->
    [plan].

-spec options_spec(atom()) -> [map()].
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

-spec help(atom()) -> iodata().
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

-spec run(atom(), map()) -> integer().
run(plan, Opts) ->
    case require_options(Opts) of
        ok ->
            io:format(standard_error, "plan execution not implemented yet.~n", []),
            1;
        {error, Message} ->
            io:format(standard_error, "~ts~n", [Message]),
            2
    end.

require_options(Opts) ->
    case maps:get(product, Opts, undefined) of
        undefined -> {error, "plan requires --product."};
        [] -> {error, "plan requires --product."};
        _ ->
            case maps:get(motherlode, Opts, undefined) of
                undefined -> {error, "plan requires --motherlode."};
                [] -> {error, "plan requires --motherlode."};
                _ ->
                    case maps:get(output_plan, Opts, undefined) of
                        undefined -> {error, "plan requires --output-plan."};
                        [] -> {error, "plan requires --output-plan."};
                        _ -> ok
                    end
            end
    end.
