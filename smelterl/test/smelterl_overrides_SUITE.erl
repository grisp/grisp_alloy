-module(smelterl_overrides_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    apply_overrides_replaces_nugget_and_recomputes_topology/1,
    apply_overrides_applies_scoped_config_to_target_views/1,
    apply_overrides_revalidates_auxiliary_remap_duplicates/1
]).

all() ->
    [
        apply_overrides_replaces_nugget_and_recomputes_topology,
        apply_overrides_applies_scoped_config_to_target_views,
        apply_overrides_revalidates_auxiliary_remap_duplicates
    ].

apply_overrides_replaces_nugget_and_recomputes_topology(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, feature_old},
            {required, nugget, shared_dep}
        ], [
            {overrides, [{nugget, feature_old, feature_new}]}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(feature_old, feature, [{required, nugget, shared_dep}]),
        nugget(feature_new, feature, [{required, nugget, shared_dep}]),
        nugget(shared_dep, feature, [])
    ]),
    {Targets, TopologyOrders} = planned_targets(product, Motherlode),
    {ok, OverriddenTargets, OverriddenTopologies, _TargetViews} =
        smelterl_overrides:apply_overrides(Targets, TopologyOrders, Motherlode),
    MainTree = maps:get(main, OverriddenTargets),
    MainOrder = maps:get(main, OverriddenTopologies),
    assert_equal(
        [builder_core, toolchain_core, platform_core, system_core, feature_new, shared_dep],
        maps:get(product, maps:get(edges, MainTree))
    ),
    assert_equal(false, maps:is_key(feature_old, maps:get(edges, MainTree))),
    assert_equal(true, maps:is_key(feature_new, maps:get(edges, MainTree))),
    assert_equal(
        [builder_core, toolchain_core, platform_core, system_core, shared_dep, feature_new, product],
        MainOrder
    ).

apply_overrides_applies_scoped_config_to_target_views(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, main_feature}
        ], [
            {auxiliary_products, [{aux_a, aux_root_a}, {aux_b, aux_root_b}]},
            {overrides, [
                {config, all, debug_level, 1},
                {config, main, debug_level, 2},
                {config, aux_a, debug_level, 3}
            ]}
        ]),
        nugget(builder_core, builder, [], [
            {config, [{debug_level, 0, builder_core}]}
        ]),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(main_feature, feature, []),
        nugget(aux_root_a, feature, []),
        nugget(aux_root_b, feature, [])
    ]),
    {Targets, TopologyOrders} = planned_targets(product, Motherlode),
    {ok, _OverriddenTargets, _OverriddenTopologies, TargetViews} =
        smelterl_overrides:apply_overrides(Targets, TopologyOrders, Motherlode),
    assert_equal(
        {debug_level, 2, product},
        config_entry(debug_level, builder_core, maps:get(main, TargetViews))
    ),
    assert_equal(
        {debug_level, 3, product},
        config_entry(debug_level, builder_core, maps:get(aux_a, TargetViews))
    ),
    assert_equal(
        {debug_level, 1, product},
        config_entry(debug_level, builder_core, maps:get(aux_b, TargetViews))
    ).

apply_overrides_revalidates_auxiliary_remap_duplicates(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core}
        ], [
            {auxiliary_products, [{aux_a, aux_root_a}, {aux_b, aux_root_b}]},
            {overrides, [{auxiliary_product, aux_a, aux_b}]}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(aux_root_a, feature, []),
        nugget(aux_root_b, feature, [])
    ]),
    {Targets, TopologyOrders} = planned_targets(product, Motherlode),
    assert_equal(
        {error, {validation_failed, {duplicate_auxiliary_id, aux_b}}},
        smelterl_overrides:apply_overrides(Targets, TopologyOrders, Motherlode)
    ).

planned_targets(ProductId, Motherlode) ->
    {ok, Targets} = smelterl_tree:build_targets(ProductId, Motherlode),
    ok = smelterl_validate:validate_targets(Targets, Motherlode),
    {ok, TopologyOrders} = topology_orders(Targets),
    {Targets, TopologyOrders}.

topology_orders(Targets) ->
    MainTree = maps:get(main, Targets),
    Auxiliaries = maps:get(auxiliaries, Targets, []),
    {ok, MainOrder} = smelterl_topology:topology_order(MainTree),
    {ok, AuxiliaryOrders} = topology_orders(Auxiliaries, #{}),
    {ok, maps:put(main, MainOrder, AuxiliaryOrders)}.

topology_orders([], Orders) ->
    {ok, Orders};
topology_orders([Auxiliary | Rest], Orders0) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    {ok, Order} = smelterl_topology:topology_order(maps:get(tree, Auxiliary)),
    topology_orders(Rest, maps:put(AuxiliaryId, Order, Orders0)).

config_entry(ConfigKey, NuggetId, TargetMotherlode) ->
    Nugget = maps:get(NuggetId, maps:get(nuggets, TargetMotherlode)),
    hd([
        Entry
     || Entry = {Key, _Value, _Origin} <- maps:get(config, Nugget, []),
        Key =:= ConfigKey
    ]).

motherlode(Nuggets) ->
    #{
        nuggets => maps:from_list([{maps:get(id, Nugget), Nugget} || Nugget <- Nuggets]),
        repositories => #{}
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
            auxiliary_products => []
        },
        maps:from_list(ExtraFields)
    ).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
