-module(smelterl_cmd_plan_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    global_help_lists_plan_command/1,
    command_help_shows_plan_usage/1,
    plan_requires_product/1,
    plan_requires_motherlode/1,
    plan_requires_output_plan/1,
    plan_warns_when_repository_is_missing_registry/1,
    plan_warns_for_multiple_missing_registries_in_sorted_order/1,
    plan_reports_invalid_motherlode_path/1,
    plan_rejects_unknown_argument/1,
    valid_plan_args_report_not_implemented/1
]).

all() ->
    [
        global_help_lists_plan_command,
        command_help_shows_plan_usage,
        plan_requires_product,
        plan_requires_motherlode,
        plan_requires_output_plan,
        plan_warns_when_repository_is_missing_registry,
        plan_warns_for_multiple_missing_registries_in_sorted_order,
        plan_reports_invalid_motherlode_path,
        plan_rejects_unknown_argument,
        valid_plan_args_report_not_implemented
    ].

global_help_lists_plan_command(_Config) ->
    {Status, Output} = run_main(["--help"]),
    assert_equal(0, Status),
    assert_contains(Output, <<"Usage: smelterl">>),
    assert_contains(Output, <<"  plan">>).

command_help_shows_plan_usage(_Config) ->
    {Status, Output} = run_main(["plan", "--help"]),
    assert_equal(0, Status),
    assert_contains(Output, <<"Usage: smelterl plan [OPTIONS]">>),
    assert_contains(Output, <<"--output-plan PATH">>).

plan_requires_product(_Config) ->
    {Status, Output} = run_main(["plan", "--motherlode", "/tmp/motherlode", "--output-plan", "/tmp/build_plan.term"]),
    assert_equal(2, Status),
    assert_contains(Output, <<"plan requires --product.">>).

plan_requires_motherlode(_Config) ->
    {Status, Output} = run_main(["plan", "--product", "demo", "--output-plan", "/tmp/build_plan.term"]),
    assert_equal(2, Status),
    assert_contains(Output, <<"plan requires --motherlode.">>).

plan_requires_output_plan(_Config) ->
    {Status, Output} = run_main(["plan", "--product", "demo", "--motherlode", "/tmp/motherlode"]),
    assert_equal(2, Status),
    assert_contains(Output, <<"plan requires --output-plan.">>).

plan_warns_when_repository_is_missing_registry(_Config) ->
    MotherlodeDir = create_valid_motherlode(),
    create_repo_without_registry(MotherlodeDir, "missing_registry"),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_contains(
        Output,
        <<"warning: motherlode repository '">>
    ),
    assert_contains(Output, <<"missing_registry' has no .nuggets registry">>),
    assert_contains(Output, <<"plan execution not implemented yet.">>).

plan_warns_for_multiple_missing_registries_in_sorted_order(_Config) ->
    MotherlodeDir = create_valid_motherlode(),
    create_repo_without_registry(MotherlodeDir, "zzz_missing"),
    create_repo_without_registry(MotherlodeDir, "aaa_missing"),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_order(
        Output,
        <<"aaa_missing' has no .nuggets registry">>,
        <<"zzz_missing' has no .nuggets registry">>
    ).

plan_reports_invalid_motherlode_path(_Config) ->
    {Status, Output} = run_main(["plan", "--product", "demo", "--motherlode", "/definitely/missing", "--output-plan", "/tmp/build_plan.term"]),
    assert_equal(1, Status),
    assert_contains(Output, <<"plan: invalid motherlode path">>).

plan_rejects_unknown_argument(_Config) ->
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", "/tmp/motherlode",
        "--output-plan", "/tmp/build_plan.term",
        "--bogus"
    ]),
    assert_equal(2, Status),
    assert_contains(Output, <<"plan: unknown argument '--bogus'">>).

valid_plan_args_report_not_implemented(_Config) ->
    MotherlodeDir = create_valid_motherlode(),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term",
        "--output-plan-env", "/tmp/build_plan.env",
        "--extra-config", "FOO=bar",
        "--extra-config", "BAZ=qux",
        "--verbose"
    ]),
    assert_equal(1, Status),
    assert_contains(Output, <<"plan execution not implemented yet.">>).

run_main(Argv) ->
    ScriptDir = filename:dirname(code:which(?MODULE)),
    SmelterlEbin = filename:join(filename:dirname(ScriptDir), "ebin"),
    Eval = io_lib:format("halt(smelterl:main(~tp)).", [Argv]),
    Port =
        open_port(
            {spawn_executable, os:find_executable("erl")},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                use_stdio,
                {args, ["-noshell", "-pa", SmelterlEbin, "-eval", lists:flatten(Eval)]}
            ]
        ),
    collect_port_output(Port, []).

collect_port_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_port_output(Port, [Data | Acc]);
        {Port, {exit_status, Status}} ->
            {Status, iolist_to_binary(lists:reverse(Acc))}
    end.

assert_contains(Haystack, Needle) ->
    case binary:match(Haystack, Needle) of
        nomatch ->
            ct:fail("Expected ~tp to contain ~tp", [Haystack, Needle]);
        _ ->
            ok
    end.

assert_order(Haystack, FirstNeedle, SecondNeedle) ->
    case {
        binary:match(Haystack, FirstNeedle),
        binary:match(Haystack, SecondNeedle)
    } of
        {{FirstIndex, _}, {SecondIndex, _}} when FirstIndex < SecondIndex ->
            ok;
        {FirstMatch, SecondMatch} ->
            ct:fail(
                "Expected ~tp before ~tp in ~tp, got ~tp and ~tp",
                [FirstNeedle, SecondNeedle, Haystack, FirstMatch, SecondMatch]
            )
    end.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected -> ok;
        _ -> ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.

create_valid_motherlode() ->
    Dir = make_temp_dir("smelterl-plan-motherlode"),
    RepoDir = filename:join(Dir, "builtin"),
    NuggetDir = filename:join(RepoDir, "demo"),
    ok = filelib:ensure_dir(filename:join(NuggetDir, "demo.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {nuggets, [<<\"demo/demo.nugget\">>]}\n",
            "]}.\n"
        ]
    ),
    ok = file:write_file(
        filename:join(NuggetDir, "demo.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, demo},\n",
            "    {category, feature}\n",
            "]}.\n"
        ]
    ),
    Dir.

create_repo_without_registry(MotherlodeDir, RepoName) ->
    ok = file:make_dir(filename:join(MotherlodeDir, RepoName)).

make_temp_dir(Prefix) ->
    Base = filename:join(os:getenv("TMPDIR", "/tmp"), Prefix ++ "-" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = file:make_dir(Base),
    Base.
