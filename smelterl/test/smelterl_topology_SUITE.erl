-module(smelterl_topology_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    topology_order_returns_dependencies_before_dependents/1,
    topology_order_uses_dependency_declaration_order_as_tie_break/1,
    topology_order_is_stable_across_repeated_runs/1,
    topology_order_reports_cycles/1
]).

all() ->
    [
        topology_order_returns_dependencies_before_dependents,
        topology_order_uses_dependency_declaration_order_as_tie_break,
        topology_order_is_stable_across_repeated_runs,
        topology_order_reports_cycles
    ].

topology_order_returns_dependencies_before_dependents(_Config) ->
    Tree = tree(product, [
        {product, [builder_core, app_feature]},
        {builder_core, [shared_dep]},
        {app_feature, [shared_dep, toolchain_core]},
        {shared_dep, []},
        {toolchain_core, []}
    ]),
    {ok, Order} = smelterl_topology:topology_order(Tree),
    assert_equal(
        [shared_dep, builder_core, toolchain_core, app_feature, product],
        Order
    ).

topology_order_uses_dependency_declaration_order_as_tie_break(_Config) ->
    Tree = tree(product, [
        {product, [feature_b, feature_a]},
        {feature_a, []},
        {feature_b, []}
    ]),
    {ok, Order} = smelterl_topology:topology_order(Tree),
    assert_equal([feature_b, feature_a, product], Order).

topology_order_is_stable_across_repeated_runs(_Config) ->
    Tree = tree(product, [
        {product, [feature_b, feature_a]},
        {feature_b, [shared_dep]},
        {feature_a, [shared_dep]},
        {shared_dep, []}
    ]),
    {ok, First} = smelterl_topology:topology_order(Tree),
    {ok, Second} = smelterl_topology:topology_order(Tree),
    {ok, Third} = smelterl_topology:topology_order(Tree),
    assert_equal(First, Second),
    assert_equal(Second, Third).

topology_order_reports_cycles(_Config) ->
    Tree = tree(product, [
        {product, [dep_a]},
        {dep_a, [dep_b]},
        {dep_b, [product]}
    ]),
    assert_equal(
        {error, {cycle_detected, [product, dep_a, dep_b, product]}},
        smelterl_topology:topology_order(Tree)
    ).

tree(Root, EdgeList) ->
    #{root => Root, edges => maps:from_list(EdgeList)}.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
