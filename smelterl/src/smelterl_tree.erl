%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_tree).
-moduledoc """
Construct Smelterl main and auxiliary target trees from the loaded motherlode.

This module builds nugget-only dependency subtrees with cycle detection and
provides the target-set construction used by the plan command to discover
auxiliary targets and compose effective auxiliary trees with the main backbone.
""".

%=== EXPORTS ===================================================================

-export([build/2]).
-export([build_targets/2]).


%=== API FUNCTIONS =============================================================

-doc """
Build one nugget dependency subtree from a root nugget identifier.

Only nugget-kind dependency constraints contribute edges. Category and
capability constraints are ignored at this stage, while cycles and missing
required nugget dependencies abort the build.
""".
-spec build(smelterl:nugget_id(), smelterl:motherlode()) ->
    {ok, smelterl:nugget_tree()} | {error, term()}.
build(ProductId, Motherlode) ->
    case lookup_nugget(ProductId, Motherlode) of
        undefined ->
            {error, {product_not_found, ProductId}};
        _Nugget ->
            case build_node(ProductId, Motherlode, [], #{}) of
                {ok, Edges} ->
                    {ok, #{root => ProductId, edges => Edges}};
                {error, _} = Error ->
                    Error
            end
    end.

-doc """
Build the main target tree and all effective auxiliary target trees.

The main tree is built from the selected product nugget. Auxiliary targets are
discovered from `auxiliary_products` metadata in the main tree, each
auxiliary-specific subtree is built independently, and then the main backbone
(`builder`, `toolchain`, `platform`, `system` plus their transitive nugget
dependencies) is merged into each effective auxiliary tree.
""".
-spec build_targets(smelterl:nugget_id(), smelterl:motherlode()) ->
    {ok, smelterl:target_trees()} | {error, term()}.
build_targets(ProductId, Motherlode) ->
    case build(ProductId, Motherlode) of
        {ok, MainTree} ->
            case discover_auxiliary_targets(MainTree, Motherlode) of
                {ok, AuxiliarySpecs} ->
                    build_auxiliary_targets(AuxiliarySpecs, MainTree, Motherlode);
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

build_node(NuggetId, Motherlode, Path, Edges0) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    case resolve_dependency_ids(NuggetId, Nugget, Motherlode) of
        {ok, DependencyIds0} ->
            DependencyIds = dedupe_keep_first(DependencyIds0),
            Edges1 = maps:put(NuggetId, DependencyIds, Edges0),
            build_dependencies(DependencyIds, Motherlode, Path ++ [NuggetId], Edges1);
        {error, _} = Error ->
            Error
    end.

build_dependencies([], _Motherlode, _Path, Edges) ->
    {ok, Edges};
build_dependencies([DependencyId | Rest], Motherlode, Path, Edges0) ->
    case lists:member(DependencyId, Path) of
        true ->
            {error, {circular_dependency, cycle_path(DependencyId, Path)}};
        false ->
            case maps:is_key(DependencyId, Edges0) of
                true ->
                    build_dependencies(Rest, Motherlode, Path, Edges0);
                false ->
                    case build_node(DependencyId, Motherlode, Path, Edges0) of
                        {ok, Edges1} ->
                            build_dependencies(Rest, Motherlode, Path, Edges1);
                        {error, _} = Error ->
                            Error
                    end
            end
    end.

resolve_dependency_ids(NuggetId, Nugget, Motherlode) ->
    case maps:get(depends_on, Nugget, []) of
        DependsOn when is_list(DependsOn) ->
            resolve_dependency_constraints(NuggetId, DependsOn, Motherlode, []);
        InvalidDependsOn ->
            {error, {invalid_dependency_constraints, NuggetId, InvalidDependsOn}}
    end.

resolve_dependency_constraints(_NuggetId, [], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
resolve_dependency_constraints(NuggetId, [Constraint | Rest], Motherlode, Acc) ->
    case constraint_dependency_ids(NuggetId, Constraint, Motherlode) of
        {ok, DependencyIds} ->
            resolve_dependency_constraints(
                NuggetId,
                Rest,
                Motherlode,
                lists:reverse(DependencyIds) ++ Acc
            );
        {error, _} = Error ->
            Error
    end.

constraint_dependency_ids(NuggetId, {required, nugget, Spec}, Motherlode) ->
    resolve_required_dependency(NuggetId, Spec, required, Motherlode);
constraint_dependency_ids(NuggetId, {optional, nugget, Spec}, Motherlode) ->
    resolve_optional_dependency(NuggetId, Spec, Motherlode);
constraint_dependency_ids(NuggetId, {one_of, nugget, Specs}, Motherlode)
  when is_list(Specs) ->
    resolve_multi_dependency(NuggetId, Specs, one_of, Motherlode);
constraint_dependency_ids(NuggetId, {any_of, nugget, Specs}, Motherlode)
  when is_list(Specs) ->
    resolve_multi_dependency(NuggetId, Specs, any_of, Motherlode);
constraint_dependency_ids(_NuggetId, {conflicts_with, nugget, _Spec}, _Motherlode) ->
    {ok, []};
constraint_dependency_ids(_NuggetId, {_Type, category, _Spec}, _Motherlode) ->
    {ok, []};
constraint_dependency_ids(_NuggetId, {_Type, capability, _Spec}, _Motherlode) ->
    {ok, []};
constraint_dependency_ids(NuggetId, Constraint, _Motherlode) ->
    {error, {invalid_dependency_constraint, NuggetId, Constraint}}.

resolve_required_dependency(NuggetId, Spec, ConstraintType, Motherlode) ->
    case dependency_id(Spec) of
        {ok, DependencyId} ->
            case lookup_nugget(DependencyId, Motherlode) of
                undefined ->
                    {error,
                        {dependency_not_found,
                            NuggetId,
                            DependencyId,
                            ConstraintType}};
                _Dependency ->
                    {ok, [DependencyId]}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Spec}}
    end.

resolve_optional_dependency(NuggetId, Spec, Motherlode) ->
    case dependency_id(Spec) of
        {ok, DependencyId} ->
            case lookup_nugget(DependencyId, Motherlode) of
                undefined ->
                    {ok, []};
                _Dependency ->
                    {ok, [DependencyId]}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Spec}}
    end.

resolve_multi_dependency(NuggetId, Specs, ConstraintType, Motherlode) ->
    case dependency_ids(Specs) of
        {ok, DependencyIds} ->
            AvailableIds = [
                DependencyId
             || DependencyId <- DependencyIds,
                lookup_nugget(DependencyId, Motherlode) =/= undefined
            ],
            case AvailableIds of
                [] ->
                    {error,
                        {dependency_not_found,
                            NuggetId,
                            hd(DependencyIds),
                            ConstraintType}};
                _ ->
                    {ok, AvailableIds}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Specs}}
    end.

dependency_ids(Specs) ->
    dependency_ids(Specs, []).

dependency_ids([], Acc) ->
    {ok, lists:reverse(Acc)};
dependency_ids([Spec | Rest], Acc) ->
    case dependency_id(Spec) of
        {ok, DependencyId} ->
            dependency_ids(Rest, [DependencyId | Acc]);
        {error, _} = Error ->
            Error
    end.

dependency_id(DependencyId) when is_atom(DependencyId) ->
    {ok, DependencyId};
dependency_id({DependencyId, _Version}) when is_atom(DependencyId) ->
    {ok, DependencyId};
dependency_id({DependencyId, ConstraintProps})
  when is_atom(DependencyId), is_list(ConstraintProps) ->
    {ok, DependencyId};
dependency_id(_Other) ->
    {error, invalid_dependency_spec}.

discover_auxiliary_targets(MainTree, Motherlode) ->
    discover_auxiliary_targets(tree_node_order(MainTree), Motherlode, []).

discover_auxiliary_targets([], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
discover_auxiliary_targets([NuggetId | Rest], Motherlode, Acc) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    case normalize_auxiliary_targets(
        NuggetId,
        maps:get(auxiliary_products, Nugget, []),
        []
    ) of
        {ok, AuxiliaryTargets} ->
            discover_auxiliary_targets(
                Rest,
                Motherlode,
                lists:reverse(AuxiliaryTargets) ++ Acc
            );
        {error, _} = Error ->
            Error
    end.

normalize_auxiliary_targets(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
normalize_auxiliary_targets(NuggetId, [Entry | Rest], Acc) ->
    case normalize_auxiliary_target(NuggetId, Entry) of
        {ok, AuxiliaryTarget} ->
            normalize_auxiliary_targets(NuggetId, Rest, [AuxiliaryTarget | Acc]);
        {error, _} = Error ->
            Error
    end;
normalize_auxiliary_targets(NuggetId, InvalidValue, _Acc) ->
    {error, {invalid_auxiliary_products, NuggetId, InvalidValue}}.

normalize_auxiliary_target(_NuggetId, RootNugget)
  when is_atom(RootNugget) ->
    {ok, #{id => RootNugget, root_nugget => RootNugget, constraints => []}};
normalize_auxiliary_target(_NuggetId, {AuxId, RootNugget})
  when is_atom(AuxId), is_atom(RootNugget) ->
    {ok, #{id => AuxId, root_nugget => RootNugget, constraints => []}};
normalize_auxiliary_target(_NuggetId, {AuxId, RootNugget, Version})
  when is_atom(AuxId), is_atom(RootNugget), is_binary(Version) ->
    {ok,
        #{
            id => AuxId,
            root_nugget => RootNugget,
            constraints => [{version, Version}]
        }};
normalize_auxiliary_target(_NuggetId, {AuxId, RootNugget, ConstraintProps})
  when is_atom(AuxId), is_atom(RootNugget), is_list(ConstraintProps) ->
    {ok,
        #{
            id => AuxId,
            root_nugget => RootNugget,
            constraints => ConstraintProps
        }};
normalize_auxiliary_target(NuggetId, Entry) ->
    {error, {invalid_auxiliary_product, NuggetId, Entry}}.

build_auxiliary_targets(AuxiliarySpecs, MainTree, Motherlode) ->
    BackboneEdges = backbone_edges(MainTree, Motherlode),
    case build_auxiliary_targets(AuxiliarySpecs, BackboneEdges, Motherlode, []) of
        {ok, AuxiliaryTargets} ->
            {ok, #{main => MainTree, auxiliaries => lists:reverse(AuxiliaryTargets)}};
        {error, _} = Error ->
            Error
    end.

build_auxiliary_targets([], _BackboneEdges, _Motherlode, Acc) ->
    {ok, Acc};
build_auxiliary_targets(
    [AuxiliarySpec | Rest],
    BackboneEdges,
    Motherlode,
    Acc
) ->
    AuxiliaryId = maps:get(id, AuxiliarySpec),
    RootNugget = maps:get(root_nugget, AuxiliarySpec),
    case build(RootNugget, Motherlode) of
        {ok, SpecificTree} ->
            EffectiveTree = compose_effective_auxiliary_tree(SpecificTree, BackboneEdges),
            AuxiliaryTarget = AuxiliarySpec#{
                specific_tree => SpecificTree,
                tree => EffectiveTree
            },
            build_auxiliary_targets(
                Rest,
                BackboneEdges,
                Motherlode,
                [AuxiliaryTarget | Acc]
            );
        {error, {product_not_found, _MissingRoot}} ->
            {error, {auxiliary_root_not_found, AuxiliaryId, RootNugget}};
        {error, _} = Error ->
            Error
    end.

backbone_edges(MainTree, Motherlode) ->
    NodeOrder = tree_node_order(MainTree),
    BackboneSeeds = [
        NuggetId
     || NuggetId <- NodeOrder,
        is_backbone_category(nugget_category(NuggetId, Motherlode))
    ],
    BackboneIds = reachable_ids(BackboneSeeds, maps:get(edges, MainTree), []),
    filter_edges(BackboneIds, maps:get(edges, MainTree)).

compose_effective_auxiliary_tree(SpecificTree, BackboneEdges) ->
    EffectiveEdges = merge_edge_maps(maps:get(edges, SpecificTree), BackboneEdges),
    #{root => maps:get(root, SpecificTree), edges => EffectiveEdges}.

merge_edge_maps(LeftEdges, RightEdges) ->
    NodeIds = dedupe_keep_first(maps:keys(LeftEdges) ++ maps:keys(RightEdges)),
    lists:foldl(
        fun(NodeId, Acc) ->
            LeftDeps = maps:get(NodeId, LeftEdges, []),
            RightDeps = maps:get(NodeId, RightEdges, []),
            maps:put(NodeId, dedupe_keep_first(LeftDeps ++ RightDeps), Acc)
        end,
        #{},
        NodeIds
    ).

filter_edges(NodeIds, Edges) ->
    NodeSet = maps:from_list([{NodeId, true} || NodeId <- NodeIds]),
    lists:foldl(
        fun(NodeId, Acc) ->
            case maps:get(NodeId, Edges, undefined) of
                undefined ->
                    Acc;
                Dependencies ->
                    FilteredDependencies = [
                        DependencyId
                     || DependencyId <- Dependencies,
                        maps:is_key(DependencyId, NodeSet)
                    ],
                    maps:put(NodeId, FilteredDependencies, Acc)
            end
        end,
        #{},
        NodeIds
    ).

reachable_ids([], _Edges, Acc) ->
    lists:reverse(Acc);
reachable_ids([NodeId | Rest], Edges, Acc) ->
    case lists:member(NodeId, Acc) of
        true ->
            reachable_ids(Rest, Edges, Acc);
        false ->
            Dependencies = maps:get(NodeId, Edges, []),
            reachable_ids(Dependencies ++ Rest, Edges, [NodeId | Acc])
    end.

tree_node_order(Tree) ->
    {_Visited, NodeOrder} =
        tree_node_order(maps:get(root, Tree), maps:get(edges, Tree), []),
    NodeOrder.

tree_node_order(NodeId, Edges, Visited) ->
    case lists:member(NodeId, Visited) of
        true ->
            {Visited, []};
        false ->
            Dependencies = maps:get(NodeId, Edges, []),
            {Visited1, ChildrenOrder} =
                tree_node_order(Dependencies, Edges, [NodeId | Visited], []),
            {Visited1, [NodeId | ChildrenOrder]}
    end.

tree_node_order([], _Edges, Visited, Acc) ->
    {Visited, lists:reverse(Acc)};
tree_node_order([NodeId | Rest], Edges, Visited, Acc) ->
    {Visited1, NodeOrder} = tree_node_order(NodeId, Edges, Visited),
    tree_node_order(Rest, Edges, Visited1, lists:reverse(NodeOrder) ++ Acc).

cycle_path(DependencyId, Path) ->
    drop_until(DependencyId, Path) ++ [DependencyId].

drop_until(Target, [Target | Rest]) ->
    [Target | Rest];
drop_until(Target, [_Other | Rest]) ->
    drop_until(Target, Rest).

dedupe_keep_first(Items) ->
    dedupe_keep_first(Items, #{}).

dedupe_keep_first([], _Seen) ->
    [];
dedupe_keep_first([Item | Rest], Seen) ->
    case maps:is_key(Item, Seen) of
        true ->
            dedupe_keep_first(Rest, Seen);
        false ->
            [Item | dedupe_keep_first(Rest, maps:put(Item, true, Seen))]
    end.

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode), undefined).

nugget_category(NuggetId, Motherlode) ->
    maps:get(category, lookup_nugget(NuggetId, Motherlode), undefined).

is_backbone_category(builder) ->
    true;
is_backbone_category(toolchain) ->
    true;
is_backbone_category(platform) ->
    true;
is_backbone_category(system) ->
    true;
is_backbone_category(_Other) ->
    false.
