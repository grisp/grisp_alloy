-module(smelterl_tree_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    build_preserves_dependency_order_and_skips_missing_optional/1,
    build_detects_circular_dependency/1,
    build_reports_missing_product/1,
    build_targets_discovers_auxiliaries_and_merges_backbone/1
]).

all() ->
    [
        build_preserves_dependency_order_and_skips_missing_optional,
        build_detects_circular_dependency,
        build_reports_missing_product,
        build_targets_discovers_auxiliaries_and_merges_backbone
    ].

build_preserves_dependency_order_and_skips_missing_optional(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {optional, nugget, missing_optional},
            {required, nugget, app_feature}
        ]),
        nugget(builder_core, builder, []),
        nugget(app_feature, feature, [
            {required, nugget, shared_dep}
        ]),
        nugget(shared_dep, feature, [])
    ]),
    {ok, Tree} = smelterl_tree:build(product, Motherlode),
    assert_equal(product, maps:get(root, Tree)),
    assert_equal(
        [builder_core, app_feature],
        maps:get(product, maps:get(edges, Tree))
    ),
    assert_equal([shared_dep], maps:get(app_feature, maps:get(edges, Tree))),
    assert_equal([], maps:get(builder_core, maps:get(edges, Tree))),
    assert_equal([], maps:get(shared_dep, maps:get(edges, Tree))).

build_detects_circular_dependency(_Config) ->
    Motherlode = motherlode([
        nugget(a, feature, [{required, nugget, b}]),
        nugget(b, feature, [{required, nugget, c}]),
        nugget(c, feature, [{required, nugget, a}])
    ]),
    assert_equal(
        {error, {circular_dependency, [a, b, c, a]}},
        smelterl_tree:build(a, Motherlode)
    ).

build_reports_missing_product(_Config) ->
    Motherlode = motherlode([nugget(other, feature, [])]),
    assert_equal(
        {error, {product_not_found, missing_product}},
        smelterl_tree:build(missing_product, Motherlode)
    ).

build_targets_discovers_auxiliaries_and_merges_backbone(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, app_feature}
        ], [
            {aux_main, aux_root}
        ]),
        nugget(builder_core, builder, [{required, nugget, shared_dep}]),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(app_feature, feature, [], [
            {aux_secondary, aux_secondary_root}
        ]),
        nugget(aux_root, feature, [
            {required, nugget, aux_feature},
            {required, nugget, shared_dep}
        ]),
        nugget(aux_secondary_root, feature, []),
        nugget(aux_feature, feature, []),
        nugget(shared_dep, feature, [])
    ]),
    {ok, Targets} = smelterl_tree:build_targets(product, Motherlode),
    MainTree = maps:get(main, Targets),
    Auxiliaries = maps:get(auxiliaries, Targets),
    assert_equal(product, maps:get(root, MainTree)),
    assert_equal([aux_main, aux_secondary], [maps:get(id, Aux) || Aux <- Auxiliaries]),
    [AuxMain, AuxSecondary] = Auxiliaries,
    assert_equal(aux_root, maps:get(root_nugget, AuxMain)),
    assert_equal(aux_root, maps:get(root, maps:get(specific_tree, AuxMain))),
    assert_equal(
        [aux_feature, shared_dep],
        maps:get(aux_root, maps:get(edges, maps:get(specific_tree, AuxMain)))
    ),
    assert_equal(
        [aux_feature, shared_dep],
        maps:get(aux_root, maps:get(edges, maps:get(tree, AuxMain)))
    ),
    assert_equal(
        [shared_dep],
        maps:get(builder_core, maps:get(edges, maps:get(tree, AuxMain)))
    ),
    assert_equal([], maps:get(toolchain_core, maps:get(edges, maps:get(tree, AuxMain)))),
    assert_equal([], maps:get(platform_core, maps:get(edges, maps:get(tree, AuxMain)))),
    assert_equal([], maps:get(system_core, maps:get(edges, maps:get(tree, AuxMain)))),
    assert_equal(aux_secondary_root, maps:get(root, maps:get(tree, AuxSecondary))),
    assert_equal(
        [
            aux_secondary_root,
            builder_core,
            platform_core,
            shared_dep,
            system_core,
            toolchain_core
        ],
        dedupe_sorted(maps:keys(maps:get(edges, maps:get(tree, AuxSecondary))))
    ).

motherlode(Nuggets) ->
    #{
        nuggets => maps:from_list([{maps:get(id, Nugget), Nugget} || Nugget <- Nuggets]),
        repositories => #{}
    }.

nugget(Id, Category, DependsOn) ->
    nugget(Id, Category, DependsOn, []).

nugget(Id, Category, DependsOn, AuxiliaryProducts) ->
    #{
        id => Id,
        category => Category,
        depends_on => DependsOn,
        auxiliary_products => AuxiliaryProducts
    }.

dedupe_sorted(Items) ->
    lists:sort(lists:usort(Items)).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
