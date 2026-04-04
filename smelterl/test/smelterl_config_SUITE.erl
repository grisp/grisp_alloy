-module(smelterl_config_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    consolidate_resolves_paths_flavors_computed_and_exec/1,
    consolidate_rejects_duplicate_exports/1,
    consolidate_rejects_export_config_conflicts/1,
    consolidate_rejects_same_key_in_config_and_exports_of_same_nugget/1
]).

all() ->
    [
        consolidate_resolves_paths_flavors_computed_and_exec,
        consolidate_rejects_duplicate_exports,
        consolidate_rejects_export_config_conflicts,
        consolidate_rejects_same_key_in_config_and_exports_of_same_nugget
    ].

consolidate_resolves_paths_flavors_computed_and_exec(_Config) ->
    RepoDir = make_repo_dir("smelterl-config-resolve"),
    ok = write_exec_script(
        RepoDir,
        "system_core/scripts/render-env.sh",
        [
            "#!/bin/sh\n",
            "printf '%s|%s|%s|%s|%s' "
            "\"$1\" "
            "\"$ALLOY_CONFIG_BOARD_TYPE\" "
            "\"$ALLOY_CONFIG_TARGET_ARCH\" "
            "\"$ALLOY_CACHE_DIR\" "
            "\"$ALLOY_NUGGET_PLATFORM_CORE_CONFIG_BOARD_TYPE\"\n"
        ]
    ),
    Motherlode = motherlode(
        RepoDir,
        [
            nugget(product, feature, [
                {required, nugget, builder_core},
                {required, nugget, toolchain_core},
                {required, nugget, {platform_core, [{flavor, pro}]}},
                {required, nugget, system_core}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, [], [
                {flavors, [dev, pro]},
                {config, [
                    {board_type,
                        {flavor_map, [
                            {dev, <<"dev-board">>},
                            {pro, <<"pro-board">>}
                        ]},
                        platform_core},
                    {debug_level, 1, platform_core},
                    {rootfs_overlay, {path, <<"overlay">>}, platform_core},
                    {artifact_root,
                        {computed, <<"[[ALLOY_CACHE_DIR]]/[[ALLOY_CONFIG_BOARD_TYPE]]">>},
                        platform_core}
                ]},
                {exports, [
                    {target_arch, arm, platform_core}
                ]}
            ]),
            nugget(system_core, system, [], [
                {config, [
                    {debug_level, 2, system_core},
                    {device_tree, {path, <<"@platform_core/dts/pro.dts">>}, system_core},
                    {generated_value, {exec, <<"scripts/render-env.sh">>}, system_core}
                ]}
            ])
        ]
    ),
    Tree = target_tree(product, [builder_core, toolchain_core, platform_core, system_core]),
    Topology = [builder_core, toolchain_core, platform_core, system_core, product],
    ExtraConfig = #{
        <<"ALLOY_CACHE_DIR">> => <<"/var/cache/alloy">>,
        <<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>
    },
    {ok, Config} = smelterl_config:consolidate(Tree, Topology, Motherlode, ExtraConfig),
    assert_entry(
        {nugget, platform_core, <<"pro-board">>},
        <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_BOARD_TYPE">>,
        Config
    ),
    assert_entry(
        {global, undefined, <<"pro-board">>},
        <<"ALLOY_CONFIG_BOARD_TYPE">>,
        Config
    ),
    assert_entry(
        {nugget, platform_core, <<"1">>},
        <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_DEBUG_LEVEL">>,
        Config
    ),
    assert_entry(
        {nugget, system_core, <<"2">>},
        <<"ALLOY_NUGGET_SYSTEM_CORE_CONFIG_DEBUG_LEVEL">>,
        Config
    ),
    assert_entry(
        {global, undefined, <<"2">>},
        <<"ALLOY_CONFIG_DEBUG_LEVEL">>,
        Config
    ),
    assert_entry(
        {nugget, platform_core, <<"${ALLOY_MOTHERLODE}/builtin/platform_core/overlay">>},
        <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_ROOTFS_OVERLAY">>,
        Config
    ),
    assert_entry(
        {nugget, platform_core, <<"/var/cache/alloy/pro-board">>},
        <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_ARTIFACT_ROOT">>,
        Config
    ),
    assert_entry(
        {nugget, system_core, <<"${ALLOY_MOTHERLODE}/builtin/platform_core/dts/pro.dts">>},
        <<"ALLOY_NUGGET_SYSTEM_CORE_CONFIG_DEVICE_TREE">>,
        Config
    ),
    assert_entry(
        {global, undefined, <<"${ALLOY_MOTHERLODE}/builtin/platform_core/dts/pro.dts">>},
        <<"ALLOY_CONFIG_DEVICE_TREE">>,
        Config
    ),
    assert_entry(
        {nugget, system_core, <<"generated_value|pro-board|arm|/var/cache/alloy|pro-board">>},
        <<"ALLOY_NUGGET_SYSTEM_CORE_CONFIG_GENERATED_VALUE">>,
        Config
    ),
    assert_entry(
        {global, undefined, <<"generated_value|pro-board|arm|/var/cache/alloy|pro-board">>},
        <<"ALLOY_CONFIG_GENERATED_VALUE">>,
        Config
    ),
    assert_entry(
        {nugget, platform_core, <<"arm">>},
        <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_TARGET_ARCH">>,
        Config
    ),
    assert_entry(
        {global, undefined, <<"arm">>},
        <<"ALLOY_CONFIG_TARGET_ARCH">>,
        Config
    ).

consolidate_rejects_duplicate_exports(_Config) ->
    Motherlode = motherlode(
        make_repo_dir("smelterl-config-duplicate-export"),
        [
            nugget(product, feature, [
                {required, nugget, builder_core},
                {required, nugget, toolchain_core},
                {required, nugget, platform_core},
                {required, nugget, system_core}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, [], [
                {exports, [{target_arch, arm, platform_core}]}
            ]),
            nugget(system_core, system, [], [
                {exports, [{target_arch, aarch64, system_core}]}
            ])
        ]
    ),
    Tree = target_tree(product, [builder_core, toolchain_core, platform_core, system_core]),
    Topology = [builder_core, toolchain_core, platform_core, system_core, product],
    assert_equal(
        {error, {duplicate_export, target_arch, platform_core, system_core}},
        smelterl_config:consolidate(Tree, Topology, Motherlode, extra_config())
    ).

consolidate_rejects_export_config_conflicts(_Config) ->
    Motherlode = motherlode(
        make_repo_dir("smelterl-config-export-conflict"),
        [
            nugget(product, feature, [
                {required, nugget, builder_core},
                {required, nugget, toolchain_core},
                {required, nugget, platform_core},
                {required, nugget, system_core}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, [], [
                {exports, [{target_arch, arm, platform_core}]}
            ]),
            nugget(system_core, system, [], [
                {config, [{target_arch, aarch64, system_core}]}
            ])
        ]
    ),
    Tree = target_tree(product, [builder_core, toolchain_core, platform_core, system_core]),
    Topology = [builder_core, toolchain_core, platform_core, system_core, product],
    assert_equal(
        {error, {export_config_conflict, target_arch, platform_core, system_core}},
        smelterl_config:consolidate(Tree, Topology, Motherlode, extra_config())
    ).

consolidate_rejects_same_key_in_config_and_exports_of_same_nugget(_Config) ->
    Motherlode = motherlode(
        make_repo_dir("smelterl-config-same-nugget-conflict"),
        [
            nugget(product, feature, [
                {required, nugget, builder_core},
                {required, nugget, toolchain_core},
                {required, nugget, platform_core},
                {required, nugget, system_core}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, [], [
                {config, [{target_arch, arm, platform_core}]},
                {exports, [{target_arch, arm, platform_core}]}
            ]),
            nugget(system_core, system, [])
        ]
    ),
    Tree = target_tree(product, [builder_core, toolchain_core, platform_core, system_core]),
    Topology = [builder_core, toolchain_core, platform_core, system_core, product],
    assert_equal(
        {error, {config_export_conflict, platform_core, target_arch}},
        smelterl_config:consolidate(Tree, Topology, Motherlode, extra_config())
    ).

make_repo_dir(Name) ->
    Root = make_temp_dir(Name),
    RepoDir = filename:join(Root, "builtin"),
    ok = filelib:ensure_dir(filename:join(RepoDir, "placeholder")),
    RepoDir.

write_exec_script(RepoDir, RelativePath, Contents) ->
    FullPath = filename:join(RepoDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, Contents),
    ok = file:change_mode(FullPath, 8#755).

target_tree(ProductId, Dependencies) ->
    #{
        root => ProductId,
        edges => #{
            ProductId => Dependencies,
            builder_core => [],
            toolchain_core => [],
            platform_core => [],
            system_core => []
        }
    }.

motherlode(RepoDir, Nuggets) ->
    #{
        nuggets => maps:from_list([
            begin
                Nugget = with_repo_dir(RepoDir, Nugget0),
                {maps:get(id, Nugget), Nugget}
            end
         || Nugget0 <- Nuggets
        ]),
        repositories => #{builtin => #{path => list_to_binary(RepoDir)}}
    }.

nugget(Id, Category, DependsOn) ->
    nugget(Id, Category, DependsOn, []).

nugget(Id, Category, DependsOn, ExtraFields) ->
    maps:merge(
        #{
            id => Id,
            category => Category,
            depends_on => DependsOn,
            config => [],
            exports => [],
            auxiliary_products => [],
            repository => builtin,
            nugget_relpath => list_to_binary(atom_to_list(Id))
        },
        maps:from_list(ExtraFields)
    ).

with_repo_dir(RepoDir, Nugget) ->
    maps:put(repo_path, list_to_binary(filename:absname(RepoDir)), Nugget).

extra_config() ->
    #{
        <<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>
    }.

make_temp_dir(Prefix) ->
    make_temp_dir(Prefix, 0).

make_temp_dir(Prefix, Attempt) ->
    Suffix =
        integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++
        integer_to_list(erlang:unique_integer([monotonic, positive])) ++
        "-" ++
        integer_to_list(Attempt),
    Base = filename:join(os:getenv("TMPDIR", "/tmp"), Prefix ++ "-" ++ Suffix),
    case file:make_dir(Base) of
        ok ->
            Base;
        {error, eexist} ->
            make_temp_dir(Prefix, Attempt + 1)
    end.

assert_entry(Expected, Key, Config) ->
    assert_equal(Expected, maps:get(Key, Config)).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
