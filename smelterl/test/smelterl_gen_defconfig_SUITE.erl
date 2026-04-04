-module(smelterl_gen_defconfig_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    build_model_merges_regular_and_cumulative_keys/1,
    build_model_selects_flavor_specific_fragment/1
]).

all() ->
    [
        build_model_merges_regular_and_cumulative_keys,
        build_model_selects_flavor_specific_fragment
    ].

build_model_merges_regular_and_cumulative_keys(_Config) ->
    RepoDir = make_repo_dir("smelterl-defconfig-merge"),
    ok = write_file(
        RepoDir,
        "platform_core/buildroot-pro.defconfig.fragment",
        [
            "BR2_TARGET_GENERIC_HOSTNAME=\"[[ALLOY_PRODUCT_NAME]]\"\n",
            "BR2_ROOTFS_OVERLAY=\"overlay/platform\"\n",
            "BR2_ROOTFS_POST_BUILD_SCRIPT=\"scripts/platform-post-build.sh\"\n",
            "BR2_ENABLE_LOCALE_WHITELIST=\"C\"\n"
        ]
    ),
    ok = write_file(
        RepoDir,
        "system_core/buildroot.defconfig.fragment",
        [
            "BR2_TARGET_GENERIC_HOSTNAME=\"[[ALLOY_CONFIG_DEVICE_NAME]]\"\n",
            "BR2_TARGET_GENERIC_ISSUE=\"[[ALLOY_PRODUCT_VERSION]] @ [[ALLOY_CACHE_DIR]]\"\n",
            "BR2_ROOTFS_OVERLAY=\"overlay/system\"\n",
            "BR2_GLOBAL_PATCH_DIR=\"patches/system\"\n",
            "BR2_ENABLE_LOCALE_WHITELIST=\"en_US.utf8\"\n"
        ]
    ),
    ok = write_file(
        RepoDir,
        "product/buildroot.defconfig.fragment",
        [
            "BR2_PACKAGE_PRODUCT=y\n",
            "BR2_ROOTFS_POST_IMAGE_SCRIPT=\"scripts/product-post-image.sh\"\n"
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
            ], [
                {name, <<"Demo Product">>},
                {version, <<"1.2.3">>},
                {buildroot, [{defconfig_fragment, <<"buildroot.defconfig.fragment">>}]}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, [], [
                {flavors, [dev, pro]},
                {buildroot, [
                    {defconfig_fragment,
                        {flavor_map, [
                            {dev, <<"buildroot-dev.defconfig.fragment">>},
                            {pro, <<"buildroot-pro.defconfig.fragment">>}
                        ]}}
                ]}
            ]),
            nugget(system_core, system, [], [
                {buildroot, [{defconfig_fragment, <<"buildroot.defconfig.fragment">>}]}
            ])
        ]
    ),
    Config = #{
        <<"ALLOY_CONFIG_DEVICE_NAME">> => {global, undefined, <<"device-01">>},
        <<"ALLOY_CACHE_DIR">> => {extra, undefined, <<"/var/cache/alloy">>}
    },
    Topology = [builder_core, toolchain_core, platform_core, system_core, product],
    {ok, Model} = smelterl_gen_defconfig:build_model(
        main,
        Topology,
        Motherlode,
        Config,
        product
    ),
    assert_equal(
        [
            {<<"BR2_TARGET_GENERIC_HOSTNAME">>, <<"\"device-01\"">>},
            {<<"BR2_TARGET_GENERIC_ISSUE">>, <<"\"1.2.3 @ /var/cache/alloy\"">>},
            {<<"BR2_PACKAGE_PRODUCT">>, <<"y">>}
        ],
        maps:get(regular, Model)
    ),
    assert_equal(
        [
            {<<"BR2_ROOTFS_OVERLAY">>,
                <<"\"${ALLOY_MOTHERLODE}/builtin/platform_core/overlay/platform "
                  "${ALLOY_MOTHERLODE}/builtin/system_core/overlay/system\"">>},
            {<<"BR2_ROOTFS_POST_BUILD_SCRIPT">>,
                <<"\"${ALLOY_MOTHERLODE}/builtin/platform_core/scripts/platform-post-build.sh "
                  "$(BR2_EXTERNAL)/board/main/scripts/post-build.sh\"">>},
            {<<"BR2_ENABLE_LOCALE_WHITELIST">>, <<"\"C en_US.utf8\"">>},
            {<<"BR2_GLOBAL_PATCH_DIR">>,
                <<"\"${ALLOY_MOTHERLODE}/builtin/system_core/patches/system\"">>},
            {<<"BR2_ROOTFS_POST_IMAGE_SCRIPT">>,
                <<"\"${ALLOY_MOTHERLODE}/builtin/product/scripts/product-post-image.sh "
                  "$(BR2_EXTERNAL)/board/main/scripts/post-image.sh\"">>},
            {<<"BR2_ROOTFS_POST_FAKEROOT_SCRIPT">>,
                <<"\"$(BR2_EXTERNAL)/board/main/scripts/post-fakeroot.sh\"">>}
        ],
        maps:get(cumulative, Model)
    ).

build_model_selects_flavor_specific_fragment(_Config) ->
    RepoDir = make_repo_dir("smelterl-defconfig-flavor"),
    ok = write_file(
        RepoDir,
        "platform_core/buildroot-dev.defconfig.fragment",
        "BR2_PACKAGE_DEV=y\n"
    ),
    ok = write_file(
        RepoDir,
        "platform_core/buildroot-pro.defconfig.fragment",
        "BR2_PACKAGE_PRO=y\n"
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
                {buildroot, [
                    {defconfig_fragment,
                        {flavor_map, [
                            {dev, <<"buildroot-dev.defconfig.fragment">>},
                            {pro, <<"buildroot-pro.defconfig.fragment">>}
                        ]}}
                ]}
            ]),
            nugget(system_core, system, [])
        ]
    ),
    {ok, Model} = smelterl_gen_defconfig:build_model(
        main,
        [builder_core, toolchain_core, platform_core, system_core, product],
        Motherlode,
        #{},
        product
    ),
    assert_equal(
        [{<<"BR2_PACKAGE_PRO">>, <<"y">>}],
        maps:get(regular, Model)
    ).

make_repo_dir(Name) ->
    Root = make_temp_dir(Name),
    RepoDir = filename:join(Root, "builtin"),
    ok = filelib:ensure_dir(filename:join(RepoDir, "placeholder")),
    RepoDir.

write_file(RepoDir, RelativePath, Contents) ->
    FullPath = filename:join(RepoDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, Contents).

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

make_temp_dir(Prefix) ->
    Base = os:getenv("TMPDIR", "/tmp"),
    make_temp_dir(Base, Prefix, 0).

make_temp_dir(Base, Prefix, Attempt) ->
    Suffix =
        integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++
        integer_to_list(erlang:unique_integer([positive])) ++
        "-" ++
        integer_to_list(Attempt),
    Dir = filename:join(Base, Prefix ++ "-" ++ Suffix),
    case file:make_dir(Dir) of
        ok ->
            Dir;
        {error, eexist} ->
            make_temp_dir(Base, Prefix, Attempt + 1)
    end.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
