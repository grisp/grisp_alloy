-module(smelterl_cmd_plan_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    global_help_lists_plan_command/1,
    command_help_shows_plan_usage/1,
    plan_requires_product/1,
    plan_requires_motherlode/1,
    plan_requires_output_plan/1,
    plan_reports_circular_dependency/1,
    plan_reports_missing_dependency/1,
    plan_reports_override_validation_failure/1,
    plan_reports_capability_validation_failure/1,
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
        plan_reports_circular_dependency,
        plan_reports_missing_dependency,
        plan_reports_override_validation_failure,
        plan_reports_capability_validation_failure,
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

plan_reports_circular_dependency(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-plan-cycle"),
    ok = write_repo(
        MotherlodeDir,
        "builtin",
        [
            {"demo/demo.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, demo},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [{required, nugget, dep_a}]}\n",
                    "]}.\n"
                ]},
            {"dep_a/dep_a.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, dep_a},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [{required, nugget, dep_b}]}\n",
                    "]}.\n"
                ]},
            {"dep_b/dep_b.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, dep_b},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [{required, nugget, demo}]}\n",
                    "]}.\n"
                ]}
        ]
    ),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_contains(Output, <<"plan: circular dependency detected: demo -> dep_a -> dep_b -> demo">>).

plan_reports_missing_dependency(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-plan-missing-dep"),
    ok = write_repo(
        MotherlodeDir,
        "builtin",
        [
            {"demo/demo.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, demo},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [{required, nugget, missing_dep}]}\n",
                    "]}.\n"
                ]}
        ]
    ),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_contains(
        Output,
        <<"plan: nugget 'demo' requires missing dependency 'missing_dep' (required)">>
    ).

plan_reports_override_validation_failure(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-plan-override-duplicate-aux"),
    ok = write_repo(
        MotherlodeDir,
        "builtin",
        [
            {"demo/demo.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, demo},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [\n",
                    "        {required, nugget, builder_core},\n",
                    "        {required, nugget, toolchain_core},\n",
                    "        {required, nugget, platform_core},\n",
                    "        {required, nugget, system_core}\n",
                    "    ]},\n",
                    "    {auxiliary_products, [{aux_a, aux_root_a}, {aux_b, aux_root_b}]},\n",
                    "    {overrides, [{auxiliary_product, aux_a, aux_b}]}\n",
                    "]}.\n"
                ]},
            {"builder_core/builder_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, builder_core},\n",
                    "    {category, builder}\n",
                    "]}.\n"
                ]},
            {"toolchain_core/toolchain_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, toolchain_core},\n",
                    "    {category, toolchain}\n",
                    "]}.\n"
                ]},
            {"platform_core/platform_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, platform_core},\n",
                    "    {category, platform}\n",
                    "]}.\n"
                ]},
            {"system_core/system_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, system_core},\n",
                    "    {category, system}\n",
                    "]}.\n"
                ]},
            {"aux_root_a/aux_root_a.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, aux_root_a},\n",
                    "    {category, feature}\n",
                    "]}.\n"
                ]},
            {"aux_root_b/aux_root_b.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, aux_root_b},\n",
                    "    {category, feature}\n",
                    "]}.\n"
                ]}
        ]
    ),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_contains(Output, <<"plan: duplicate auxiliary target id 'aux_b'">>).

plan_reports_capability_validation_failure(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-plan-missing-secure-bootflow"),
    ok = write_repo(
        MotherlodeDir,
        "builtin",
        [
            {"demo/demo.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, demo},\n",
                    "    {category, feature},\n",
                    "    {depends_on, [\n",
                    "        {required, nugget, builder_core},\n",
                    "        {required, nugget, toolchain_core},\n",
                    "        {required, nugget, platform_core},\n",
                    "        {required, nugget, system_core},\n",
                    "        {required, nugget, bootflow_plain},\n",
                    "        {required, nugget, secure_feature}\n",
                    "    ]}\n",
                    "]}.\n"
                ]},
            {"builder_core/builder_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, builder_core},\n",
                    "    {category, builder}\n",
                    "]}.\n"
                ]},
            {"toolchain_core/toolchain_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, toolchain_core},\n",
                    "    {category, toolchain}\n",
                    "]}.\n"
                ]},
            {"platform_core/platform_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, platform_core},\n",
                    "    {category, platform}\n",
                    "]}.\n"
                ]},
            {"system_core/system_core.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, system_core},\n",
                    "    {category, system}\n",
                    "]}.\n"
                ]},
            {"bootflow_plain/bootflow_plain.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, bootflow_plain},\n",
                    "    {category, bootflow},\n",
                    "    {firmware_variant, [plain]}\n",
                    "]}.\n"
                ]},
            {"secure_feature/secure_feature.nugget",
                [
                    "{nugget, <<\"1.0\">>, [\n",
                    "    {id, secure_feature},\n",
                    "    {category, feature},\n",
                    "    {firmware_variant, [secure]}\n",
                    "]}.\n"
                ]}
        ]
    ),
    {Status, Output} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", MotherlodeDir,
        "--output-plan", "/tmp/build_plan.term"
    ]),
    assert_equal(1, Status),
    assert_contains(
        Output,
        <<"plan: firmware variant 'secure' must be provided by exactly one bootflow nugget; found 0">>
    ).

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
            "    {nuggets, [\n",
            "        <<\"demo/demo.nugget\">>,\n",
            "        <<\"builder_core/builder_core.nugget\">>,\n",
            "        <<\"toolchain_core/toolchain_core.nugget\">>,\n",
            "        <<\"platform_core/platform_core.nugget\">>,\n",
            "        <<\"system_core/system_core.nugget\">>,\n",
            "        <<\"bootflow_plain/bootflow_plain.nugget\">>\n",
            "    ]}\n",
            "]}.\n"
        ]
    ),
    ok = file:write_file(
        filename:join(NuggetDir, "demo.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, demo},\n",
            "    {category, feature},\n",
            "    {depends_on, [\n",
            "        {required, nugget, builder_core},\n",
            "        {required, nugget, toolchain_core},\n",
            "        {required, nugget, platform_core},\n",
            "        {required, nugget, system_core},\n",
            "        {required, nugget, bootflow_plain}\n",
            "    ]}\n",
            "]}.\n"
        ]
    ),
    ok = filelib:ensure_dir(filename:join(RepoDir, "builder_core/builder_core.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, "builder_core/builder_core.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, builder_core},\n",
            "    {category, builder}\n",
            "]}.\n"
        ]
    ),
    ok = filelib:ensure_dir(filename:join(RepoDir, "toolchain_core/toolchain_core.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, "toolchain_core/toolchain_core.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, toolchain_core},\n",
            "    {category, toolchain}\n",
            "]}.\n"
        ]
    ),
    ok = filelib:ensure_dir(filename:join(RepoDir, "platform_core/platform_core.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, "platform_core/platform_core.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, platform_core},\n",
            "    {category, platform}\n",
            "]}.\n"
        ]
    ),
    ok = filelib:ensure_dir(filename:join(RepoDir, "system_core/system_core.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, "system_core/system_core.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, system_core},\n",
            "    {category, system}\n",
            "]}.\n"
        ]
    ),
    ok = filelib:ensure_dir(filename:join(RepoDir, "bootflow_plain/bootflow_plain.nugget")),
    ok = file:write_file(
        filename:join(RepoDir, "bootflow_plain/bootflow_plain.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, bootflow_plain},\n",
            "    {category, bootflow},\n",
            "    {firmware_variant, [plain]}\n",
            "]}.\n"
        ]
    ),
    Dir.

create_repo_without_registry(MotherlodeDir, RepoName) ->
    ok = file:make_dir(filename:join(MotherlodeDir, RepoName)).

write_repo(MotherlodeDir, RepoName, Nuggets) ->
    RepoDir = filename:join(MotherlodeDir, RepoName),
    RegistryEntries = [
        io_lib:format("        <<\"~ts\">>", [Path])
     || {Path, _Contents} <- Nuggets
    ],
    ok = filelib:ensure_dir(filename:join(RepoDir, ".nuggets")),
    ok = file:write_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {nuggets, [\n",
            string:join([lists:flatten(Entry) || Entry <- RegistryEntries], ",\n"),
            "\n    ]}\n",
            "]}.\n"
        ]
    ),
    lists:foreach(
        fun({Path, Contents}) ->
            FullPath = filename:join(RepoDir, Path),
            ok = filelib:ensure_dir(FullPath),
            ok = file:write_file(FullPath, Contents)
        end,
        Nuggets
    ),
    ok.

make_temp_dir(Prefix) ->
    make_temp_dir(Prefix, 0).

make_temp_dir(Prefix, Attempt) ->
    Suffix = integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++ integer_to_list(erlang:unique_integer([monotonic, positive])) ++ "-" ++ integer_to_list(Attempt),
    Base = filename:join(os:getenv("TMPDIR", "/tmp"), Prefix ++ "-" ++ Suffix),
    case file:make_dir(Base) of
        ok ->
            Base;
        {error, eexist} ->
            make_temp_dir(Prefix, Attempt + 1)
    end.
