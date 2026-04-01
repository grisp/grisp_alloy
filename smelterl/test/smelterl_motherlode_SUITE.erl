-module(smelterl_motherlode_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    load_rejects_missing_motherlode_path/1,
    load_merges_defaults_and_nugget_metadata/1,
    load_rejects_invalid_registry_root/1,
    load_rejects_missing_metadata_file/1,
    load_rejects_metadata_without_id/1,
    load_rejects_duplicated_nugget_ids/1,
    load_rejects_unsupported_registry_default/1
]).

all() ->
    [
        load_rejects_missing_motherlode_path,
        load_merges_defaults_and_nugget_metadata,
        load_rejects_invalid_registry_root,
        load_rejects_missing_metadata_file,
        load_rejects_metadata_without_id,
        load_rejects_duplicated_nugget_ids,
        load_rejects_unsupported_registry_default
    ].

load_rejects_missing_motherlode_path(_Config) ->
    Missing = filename:join(os:getenv("TMPDIR", "/tmp"), "smelterl-missing-" ++ integer_to_list(erlang:unique_integer([positive]))),
    case smelterl_motherlode:load(Missing) of
        {error, {invalid_path, _, enoent}} -> ok;
        Other -> ct:fail("Expected invalid_path error, got ~tp", [Other])
    end.

load_merges_defaults_and_nugget_metadata(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-motherlode"),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    InheritDir = filename:join(RepoDir, "inherit"),
    OverrideDir = filename:join(RepoDir, "override"),
    ok = ensure_file(filename:join(RepoDir, "LICENSE"), <<"registry license">>),
    ok = ensure_file(filename:join(OverrideDir, "NOTICE"), <<"override license">>),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {defaults, [\n",
            "        {license, <<\"Apache-2.0\">>},\n",
            "        {license_files, [<<\"LICENSE\">>]},\n",
            "        {author, <<\"ACME\">>}\n",
            "    ]},\n",
            "    {nuggets, [\n",
            "        <<\"inherit/inherit.nugget\">>,\n",
            "        <<\"override/override.nugget\">>\n",
            "    ]}\n",
            "]}.\n"
        ]
    ),
    ok = ensure_file(
        filename:join(InheritDir, "inherit.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, inherit_demo},\n",
            "    {category, feature},\n",
            "    {config, [{rootfs_overlay, {path, <<\"overlay\">>}}]},\n",
            "    {exports, [{tool, <<\"demo\">>}]} \n",
            "]}.\n"
        ]
    ),
    ok = ensure_file(
        filename:join(OverrideDir, "override.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {id, override_demo},\n",
            "    {category, feature},\n",
            "    {license_files, [<<\"NOTICE\">>]}\n",
            "]}.\n"
        ]
    ),
    {ok, Motherlode} = smelterl_motherlode:load(MotherlodeDir),
    Nuggets = maps:get(nuggets, Motherlode),
    Inherit = maps:get(inherit_demo, Nuggets),
    Override = maps:get(override_demo, Nuggets),
    assert_equal(#{}, maps:get(repositories, Motherlode)),
    assert_equal({registry, <<"Apache-2.0">>}, maps:get(license, Inherit)),
    assert_equal({registry, <<"ACME">>}, maps:get(author, Inherit)),
    assert_equal(
        {registry, [path_binary(filename:join(RepoDir, "LICENSE"))]},
        maps:get(license_files, Inherit)
    ),
    assert_equal([{rootfs_overlay, {path, <<"overlay">>}, inherit_demo}], maps:get(config, Inherit)),
    assert_equal([{tool, <<"demo">>, inherit_demo}], maps:get(exports, Inherit)),
    assert_equal(path_binary(RepoDir), maps:get(repo_path, Inherit)),
    assert_equal(<<"inherit">>, maps:get(nugget_relpath, Inherit)),
    assert_equal(builtin, maps:get(repository, Inherit)),
    assert_equal(
        {nugget, [path_binary(filename:join(OverrideDir, "NOTICE"))]},
        maps:get(license_files, Override)
    ).

load_rejects_invalid_registry_root(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-bad-registry"),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        "{not_a_registry, <<\"1.0\">>, []}.\n"
    ),
    case smelterl_motherlode:load(MotherlodeDir) of
        {error, {invalid_registry, _, invalid_root}} -> ok;
        Other -> ct:fail("Expected invalid_registry invalid_root, got ~tp", [Other])
    end.

load_rejects_missing_metadata_file(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-missing-metadata"),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {nuggets, [<<\"missing/demo.nugget\">>]}\n",
            "]}.\n"
        ]
    ),
    case smelterl_motherlode:load(MotherlodeDir) of
        {error, {missing_metadata, _, <<"missing/demo.nugget">>}} -> ok;
        Other -> ct:fail("Expected missing_metadata error, got ~tp", [Other])
    end.

load_rejects_metadata_without_id(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-missing-id"),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    NuggetDir = filename:join(RepoDir, "demo"),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {nuggets, [<<\"demo/demo.nugget\">>]}\n",
            "]}.\n"
        ]
    ),
    ok = ensure_file(
        filename:join(NuggetDir, "demo.nugget"),
        [
            "{nugget, <<\"1.0\">>, [\n",
            "    {category, feature}\n",
            "]}.\n"
        ]
    ),
    case smelterl_motherlode:load(MotherlodeDir) of
        {error, {invalid_metadata, _, <<"demo/demo.nugget">>, missing_id}} -> ok;
        Other -> ct:fail("Expected invalid_metadata missing_id, got ~tp", [Other])
    end.

load_rejects_duplicated_nugget_ids(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-duplicate-id"),
    ok = write_single_nugget_repo(MotherlodeDir, "repo_one", "demo_one", duplicate_demo),
    ok = write_single_nugget_repo(MotherlodeDir, "repo_two", "demo_two", duplicate_demo),
    case smelterl_motherlode:load(MotherlodeDir) of
        {error, {duplicated_nugget_id, duplicate_demo, _, _}} -> ok;
        Other -> ct:fail("Expected duplicated_nugget_id error, got ~tp", [Other])
    end.

load_rejects_unsupported_registry_default(_Config) ->
    MotherlodeDir = make_temp_dir("smelterl-bad-default"),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        [
            "{nugget_registry, <<\"1.0\">>, [\n",
            "    {defaults, [{category, feature}]},\n",
            "    {nuggets, []}\n",
            "]}.\n"
        ]
    ),
    case smelterl_motherlode:load(MotherlodeDir) of
        {error, {invalid_registry, _, {unsupported_default, category}}} -> ok;
        Other -> ct:fail("Expected unsupported_default error, got ~tp", [Other])
    end.

write_single_nugget_repo(MotherlodeDir, RepoName, NuggetDirName, NuggetId) ->
    RepoDir = filename:join(MotherlodeDir, RepoName),
    NuggetDir = filename:join(RepoDir, NuggetDirName),
    ok = ensure_file(
        filename:join(RepoDir, ".nuggets"),
        io_lib:format(
            "{nugget_registry, <<\"1.0\">>, [{nuggets, [<<\"~ts/~ts.nugget\">>]}]}.\n",
            [NuggetDirName, NuggetDirName]
        )
    ),
    ensure_file(
        filename:join(NuggetDir, NuggetDirName ++ ".nugget"),
        io_lib:format(
            "{nugget, <<\"1.0\">>, [{id, ~ts}, {category, feature}]}.\n",
            [atom_to_list(NuggetId)]
        )
    ).

ensure_file(Path, Contents) ->
    ok = filelib:ensure_dir(Path),
    file:write_file(Path, Contents).

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

path_binary(Path) ->
    unicode:characters_to_binary(filename:absname(Path)).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected -> ok;
        _ -> ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
