-module(smelterl_validate_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    validate_tree_accepts_valid_tree/1,
    validate_tree_rejects_bad_category_cardinality/1,
    validate_tree_rejects_missing_category_dependency/1,
    validate_tree_rejects_missing_capability_dependency/1,
    validate_tree_rejects_nugget_conflict/1,
    validate_tree_rejects_capability_conflict/1,
    validate_tree_rejects_incompatible_version/1,
    validate_tree_rejects_invalid_flavor/1,
    validate_tree_rejects_flavor_mismatch/1,
    validate_tree_rejects_one_of_nugget_cardinality/1,
    validate_targets_rejects_duplicate_auxiliary_id/1,
    validate_targets_rejects_auxiliary_forbidden_category/1,
    validate_targets_rejects_shared_flavor_mismatch/1,
    validate_targets_rejects_invalid_firmware_hook_scope/1
]).

all() ->
    [
        validate_tree_accepts_valid_tree,
        validate_tree_rejects_bad_category_cardinality,
        validate_tree_rejects_missing_category_dependency,
        validate_tree_rejects_missing_capability_dependency,
        validate_tree_rejects_nugget_conflict,
        validate_tree_rejects_capability_conflict,
        validate_tree_rejects_incompatible_version,
        validate_tree_rejects_invalid_flavor,
        validate_tree_rejects_flavor_mismatch,
        validate_tree_rejects_one_of_nugget_cardinality,
        validate_targets_rejects_duplicate_auxiliary_id,
        validate_targets_rejects_auxiliary_forbidden_category,
        validate_targets_rejects_shared_flavor_mismatch,
        validate_targets_rejects_invalid_firmware_hook_scope
    ].

validate_tree_accepts_valid_tree(_Config) ->
    Motherlode = valid_motherlode([]),
    Tree = valid_main_tree(),
    assert_equal(ok, smelterl_validate:validate_tree(Tree, Motherlode)).

validate_tree_rejects_bad_category_cardinality(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_a},
            {required, nugget, builder_b},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core}
        ]),
        nugget(builder_a, builder, []),
        nugget(builder_b, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, [])
    ]),
    Tree = tree(product, [
        {product, [builder_a, builder_b, toolchain_core, platform_core, system_core]},
        {builder_a, []},
        {builder_b, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []}
    ]),
    assert_equal(
        {error, {bad_category_cardinality, builder, 2, [builder_a, builder_b]}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_missing_category_dependency(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{required, category, bootflow}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, []}
    ]),
    assert_equal(
        {error, {missing_category_dependency, feature_a, bootflow, required}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_missing_capability_dependency(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{required, capability, secure_boot}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, []}
    ]),
    assert_equal(
        {error, {missing_capability_dependency, feature_a, secure_boot}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_nugget_conflict(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{conflicts_with, nugget, feature_b}]),
        nugget(feature_b, feature, [])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a, feature_b]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, []},
        {feature_b, []}
    ]),
    assert_equal(
        {error, {nugget_conflict, feature_a, feature_b}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_capability_conflict(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{conflicts_with, capability, secure_boot}]),
        nugget(feature_b, feature, [], [{provides, [secure_boot]}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a, feature_b]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, []},
        {feature_b, []}
    ]),
    assert_equal(
        {error, {capability_conflict, feature_a, capability, secure_boot}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_incompatible_version(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{required, nugget, {versioned_dep, <<">= 2.0.0">>}}]),
        nugget(versioned_dep, feature, [], [{version, <<"1.0.0">>}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, [versioned_dep]},
        {versioned_dep, []}
    ]),
    assert_equal(
        {error,
            {incompatible_version,
                feature_a,
                versioned_dep,
                <<">= 2.0.0">>,
                <<"1.0.0">>}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_invalid_flavor(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{required, nugget, {flavored_dep, [{flavor, secure}]}}]),
        nugget(flavored_dep, feature, [], [{flavors, [plain]}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, [flavored_dep]},
        {flavored_dep, []}
    ]),
    assert_equal(
        {error, {invalid_flavor, flavored_dep, secure}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_flavor_mismatch(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{required, nugget, {shared_dep, [{flavor, plain}]}}]),
        nugget(feature_b, feature, [{required, nugget, {shared_dep, [{flavor, secure}]}}]),
        nugget(shared_dep, feature, [], [{flavors, [plain, secure]}])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a, feature_b]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, [shared_dep]},
        {feature_b, [shared_dep]},
        {shared_dep, []}
    ]),
    assert_equal(
        {error, {flavor_mismatch, shared_dep, secure}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_tree_rejects_one_of_nugget_cardinality(_Config) ->
    Motherlode = valid_motherlode([
        nugget(feature_a, feature, [{one_of, nugget, [dep_a, dep_b]}]),
        nugget(dep_a, feature, []),
        nugget(dep_b, feature, [])
    ]),
    Tree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, [dep_a, dep_b]},
        {dep_a, []},
        {dep_b, []}
    ]),
    assert_equal(
        {error,
            {invalid_dependency_match_count,
                feature_a,
                one_of,
                nugget,
                [dep_a, dep_b],
                2}},
        smelterl_validate:validate_tree(Tree, Motherlode)
    ).

validate_targets_rejects_duplicate_auxiliary_id(_Config) ->
    Motherlode = valid_motherlode([
        nugget(aux_root_a, feature, []),
        nugget(aux_root_b, feature, [])
    ]),
    Targets = #{
        main => valid_main_tree(),
        auxiliaries => [
            auxiliary(dup_aux, aux_root_a, [], tree(aux_root_a, [{aux_root_a, []}]), effective_aux_tree(aux_root_a)),
            auxiliary(dup_aux, aux_root_b, [], tree(aux_root_b, [{aux_root_b, []}]), effective_aux_tree(aux_root_b))
        ]
    },
    assert_equal(
        {error, {duplicate_auxiliary_id, dup_aux}},
        smelterl_validate:validate_targets(Targets, Motherlode)
    ).

validate_targets_rejects_auxiliary_forbidden_category(_Config) ->
    Motherlode = valid_motherlode([
        nugget(aux_builder, builder, [])
    ]),
    Targets = #{
        main => valid_main_tree(),
        auxiliaries => [
            auxiliary(
                aux_bad,
                aux_builder,
                [],
                tree(aux_builder, [{aux_builder, []}]),
                effective_aux_tree(aux_builder)
            )
        ]
    },
    assert_equal(
        {error, {auxiliary_forbidden_category, aux_bad, aux_builder, builder}},
        smelterl_validate:validate_targets(Targets, Motherlode)
    ).

validate_targets_rejects_shared_flavor_mismatch(_Config) ->
    Motherlode = valid_motherlode([
        nugget(shared_dep, feature, [], [{flavors, [plain, secure]}]),
        nugget(feature_a, feature, [{required, nugget, {shared_dep, [{flavor, plain}]}}])
    ]),
    MainTree = tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core, feature_a]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []},
        {feature_a, [shared_dep]},
        {shared_dep, []}
    ]),
    Targets = #{
        main => MainTree,
        auxiliaries => [
            auxiliary(
                aux_secure,
                shared_dep,
                [{flavor, secure}],
                tree(shared_dep, [{shared_dep, []}]),
                effective_aux_tree(shared_dep)
            )
        ]
    },
    assert_equal(
        {error, {shared_flavor_mismatch, aux_secure, shared_dep, plain, secure}},
        smelterl_validate:validate_targets(Targets, Motherlode)
    ).

validate_targets_rejects_invalid_firmware_hook_scope(_Config) ->
    Motherlode = valid_motherlode([
        nugget(hooked_feature, feature, [], [
            {hooks, [{pre_firmware, <<"scripts/pre-firmware.sh">>, auxiliary}]}
        ])
    ]),
    Targets = #{
        main => tree(product, [
            {product, [builder_core, toolchain_core, platform_core, system_core, hooked_feature]},
            {builder_core, []},
            {toolchain_core, []},
            {platform_core, []},
            {system_core, []},
            {hooked_feature, []}
        ]),
        auxiliaries => []
    },
    assert_equal(
        {error, {invalid_firmware_hook_scope, hooked_feature, pre_firmware, auxiliary}},
        smelterl_validate:validate_targets(Targets, Motherlode)
    ).

valid_motherlode(ExtraNuggets) ->
    motherlode(
        [
            nugget(product, feature, [
                {required, nugget, builder_core},
                {required, nugget, toolchain_core},
                {required, nugget, platform_core},
                {required, nugget, system_core}
            ]),
            nugget(builder_core, builder, []),
            nugget(toolchain_core, toolchain, []),
            nugget(platform_core, platform, []),
            nugget(system_core, system, [])
        ] ++ ExtraNuggets
    ).

valid_main_tree() ->
    tree(product, [
        {product, [builder_core, toolchain_core, platform_core, system_core]},
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []}
    ]).

effective_aux_tree(Root) ->
    effective_aux_tree(Root, [{Root, []}]).

effective_aux_tree(Root, SpecificEdges) ->
    tree(Root, SpecificEdges ++ [
        {builder_core, []},
        {toolchain_core, []},
        {platform_core, []},
        {system_core, []}
    ]).

auxiliary(Id, RootNugget, Constraints, SpecificTree, Tree) ->
    #{
        id => Id,
        root_nugget => RootNugget,
        constraints => Constraints,
        specific_tree => SpecificTree,
        tree => Tree
    }.

tree(Root, EdgeList) ->
    #{root => Root, edges => maps:from_list(EdgeList)}.

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
            depends_on => DependsOn
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
