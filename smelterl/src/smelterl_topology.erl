%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_topology).
-moduledoc """
Compute deterministic topological orderings for Smelterl nugget trees.

The tree edges already preserve declared dependency order, so this module uses
that ordering directly as the stable tie-break while producing a dependency-
before-dependent order with the tree root last.
""".

%=== EXPORTS ===================================================================

-export([topology_order/1]).


%=== TYPES =====================================================================

-type nugget_id() :: atom().
-type nugget_tree() :: #{
    root := nugget_id(),
    edges := #{nugget_id() => [nugget_id()]}
}.
-type nugget_topology_order() :: [nugget_id()].


%=== API FUNCTIONS =============================================================

-doc """
Return one deterministic topological order for a nugget tree.

Dependencies are emitted before their dependents, and the tree root is last.
If the input graph contains a cycle, return the detected cycle path.
""".
-spec topology_order(nugget_tree()) ->
    {ok, nugget_topology_order()} | {error, term()}.
topology_order(Tree) ->
    Root = maps:get(root, Tree),
    Edges = maps:get(edges, Tree),
    maybe
        {ok, {_Visited, Order}} ?= visit_node(Root, Edges, #{}, [], []),
        {ok, Order}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

visit_node(NodeId, Edges, Visited0, Path, Order0) ->
    case maps:get(NodeId, Visited0, unvisited) of
        done ->
            {ok, {Visited0, Order0}};
        visiting ->
            {error, {cycle_detected, cycle_path(NodeId, Path)}};
        unvisited ->
            Dependencies = maps:get(NodeId, Edges, []),
            Visited1 = maps:put(NodeId, visiting, Visited0),
            maybe
                {ok, {Visited2, Order1}} ?= visit_dependencies(
                    Dependencies,
                    Edges,
                    Visited1,
                    [NodeId | Path],
                    Order0
                ),
                Visited3 = maps:put(NodeId, done, Visited2),
                {ok, {Visited3, Order1 ++ [NodeId]}}
            else
                {error, _} = Error ->
                    Error
            end
    end.

visit_dependencies([], _Edges, Visited, _Path, Order) ->
    {ok, {Visited, Order}};
visit_dependencies([DependencyId | Rest], Edges, Visited0, Path, Order0) ->
    maybe
        {ok, {Visited1, Order1}} ?= visit_node(
            DependencyId,
            Edges,
            Visited0,
            Path,
            Order0
        ),
        visit_dependencies(Rest, Edges, Visited1, Path, Order1)
    else
        {error, _} = Error ->
            Error
    end.

cycle_path(Target, Path) ->
    drop_until(Target, lists:reverse(Path)) ++ [Target].

drop_until(Target, [Target | Rest]) ->
    [Target | Rest];
drop_until(Target, [_Other | Rest]) ->
    drop_until(Target, Rest).
