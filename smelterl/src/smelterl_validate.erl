%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_validate).
-moduledoc """
Validate Smelterl target trees before later planning stages consume them.

The validator enforces category cardinality, dependency constraints, version
and flavor requirements, auxiliary-target restrictions, and hook-scope rules
against the pre-built target trees returned by `smelterl_tree`.
""".

%=== EXPORTS ===================================================================

-export([validate_tree/2]).
-export([validate_replacement/4]).
-export([resolved_flavors/2]).
-export([validate_targets/2]).


%=== MACROS ====================================================================

-define(EXACTLY_ONE_CATEGORIES, [builder, toolchain, platform, system]).
-define(FORBIDDEN_AUXILIARY_CATEGORIES, [builder, toolchain, platform, system, bootflow]).
-define(SDK_HOOK_TYPES, [pre_build, post_build, post_image, post_fakeroot]).
-define(FIRMWARE_HOOK_TYPES, [pre_firmware, firmware_build, post_firmware]).


%=== TYPES =====================================================================

-type flavor_map() :: #{smelterl:nugget_id() => atom()}.
-type category_map() :: #{atom() => [smelterl:nugget_id()]}.
-type capability_map() :: #{atom() => [smelterl:nugget_id()]}.
-type tree_context() :: #{
    node_ids := [smelterl:nugget_id()],
    node_set := #{smelterl:nugget_id() => true},
    categories := category_map(),
    capabilities := capability_map()
}.


%=== API FUNCTIONS =============================================================

-doc """
Validate one target tree against the loaded motherlode metadata.

This entry point enforces category cardinality, dependency constraints,
conflicts, and version/flavor requirements for a single tree.
""".
-spec validate_tree(smelterl:nugget_tree(), smelterl:motherlode()) ->
    ok | {error, term()}.
validate_tree(Tree, Motherlode) ->
    maybe
        {ok, _FlavorMap} ?= resolved_flavors(Tree, Motherlode),
        ok
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Validate one target tree and return the resolved nugget flavors.

This is the validator-backed flavor resolution used by later planning stages
that need the effective flavor choices without re-implementing dependency
constraint handling.
""".
-spec resolved_flavors(smelterl:nugget_tree(), smelterl:motherlode()) ->
    {ok, flavor_map()} | {error, term()}.
resolved_flavors(Tree, Motherlode) ->
    validate_tree_with_flavors(Tree, Motherlode, #{}).

-doc """
Validate one nugget replacement against the current target tree.

The replacement must keep the category stable and must not introduce missing
dependencies after the replaced nugget is removed from the tree.
""".
-spec validate_replacement(
    smelterl:nugget_id(),
    smelterl:nugget_id(),
    smelterl:nugget_tree(),
    smelterl:motherlode()
) ->
    ok | {error, term()}.
validate_replacement(NewNuggetId, ReplacedNuggetId, Tree, Motherlode) ->
    maybe
        ok ?= validate_replacement_category(
            NewNuggetId,
            ReplacedNuggetId,
            Motherlode
        ),
        {ok, CandidateTree} ?= replacement_tree(
            NewNuggetId,
            ReplacedNuggetId,
            Tree,
            Motherlode
        ),
        RewrittenMotherlode = rewrite_motherlode_nugget_refs(
            ReplacedNuggetId,
            NewNuggetId,
            Motherlode
        ),
        validate_tree(CandidateTree, RewrittenMotherlode)
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Validate the full main-plus-auxiliary target set returned by `smelterl_tree`.

In addition to per-tree validation, this entry point checks auxiliary target id
rules, auxiliary-specific subtree restrictions, shared-flavor consistency
between main and auxiliaries, and hook-scope validity against the declared
auxiliary ids.
""".
-spec validate_targets(smelterl:target_trees(), smelterl:motherlode()) ->
    ok | {error, term()}.
validate_targets(Targets, Motherlode) ->
    MainTree = maps:get(main, Targets),
    Auxiliaries = maps:get(auxiliaries, Targets, []),
    maybe
        {ok, MainFlavors} ?= validate_tree_with_flavors(
            MainTree,
            Motherlode,
            #{}
        ),
        ok ?= validate_auxiliary_ids(Auxiliaries),
        ok ?= validate_auxiliaries(
            Auxiliaries,
            MainFlavors,
            MainTree,
            Motherlode
        ),
        ok ?= validate_target_hook_scopes(
            Targets,
            Motherlode,
            auxiliary_ids(Auxiliaries)
        )
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec validate_auxiliaries(
    [smelterl:auxiliary_target()],
    flavor_map(),
    smelterl:nugget_tree(),
    smelterl:motherlode()
) ->
    ok | {error, term()}.
validate_auxiliaries([], _MainFlavors, _MainTree, _Motherlode) ->
    ok;
validate_auxiliaries([Auxiliary | Rest], MainFlavors, MainTree, Motherlode) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    maybe
        ok ?= validate_auxiliary_specific_tree(Auxiliary, Motherlode),
        {ok, RootFlavorMap} ?= validate_auxiliary_constraints(Auxiliary, Motherlode),
        {ok, AuxiliaryFlavors} ?= validate_tree_with_flavors(
            maps:get(tree, Auxiliary),
            Motherlode,
            RootFlavorMap
        ),
        ok ?= validate_shared_flavors(
            AuxiliaryId,
            MainFlavors,
            AuxiliaryFlavors,
            MainTree,
            maps:get(tree, Auxiliary)
        ),
        validate_auxiliaries(Rest, MainFlavors, MainTree, Motherlode)
    else
        {error, _} = Error ->
            Error
    end.

-spec validate_replacement_category(
    smelterl:nugget_id(),
    smelterl:nugget_id(),
    smelterl:motherlode()
) ->
    ok | {error, term()}.
validate_replacement_category(NewNuggetId, ReplacedNuggetId, Motherlode) ->
    NewCategory = nugget_category(NewNuggetId, Motherlode),
    ReplacedCategory = nugget_category(ReplacedNuggetId, Motherlode),
    case NewCategory =:= ReplacedCategory of
        true ->
            ok;
        false ->
            {error,
                {category_mismatch,
                    NewNuggetId,
                    ReplacedNuggetId,
                    ReplacedCategory}}
    end.

-spec validate_auxiliary_ids([smelterl:auxiliary_target()]) -> ok | {error, term()}.
validate_auxiliary_ids(Auxiliaries) ->
    validate_auxiliary_ids(Auxiliaries, #{}).

validate_auxiliary_ids([], _Seen) ->
    ok;
validate_auxiliary_ids([Auxiliary | Rest], Seen) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    case AuxiliaryId of
        main ->
            {error, {reserved_auxiliary_id, AuxiliaryId}};
        all ->
            {error, {reserved_auxiliary_id, AuxiliaryId}};
        _ ->
            case maps:is_key(AuxiliaryId, Seen) of
                true ->
                    {error, {duplicate_auxiliary_id, AuxiliaryId}};
                false ->
                    validate_auxiliary_ids(Rest, maps:put(AuxiliaryId, true, Seen))
            end
    end.

validate_auxiliary_specific_tree(Auxiliary, Motherlode) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    NodeIds = tree_node_ids(maps:get(specific_tree, Auxiliary)),
    validate_auxiliary_specific_nodes(AuxiliaryId, NodeIds, Motherlode).

validate_auxiliary_specific_nodes(_AuxiliaryId, [], _Motherlode) ->
    ok;
validate_auxiliary_specific_nodes(AuxiliaryId, [NuggetId | Rest], Motherlode) ->
    Category = nugget_category(NuggetId, Motherlode),
    case lists:member(Category, ?FORBIDDEN_AUXILIARY_CATEGORIES) of
        true ->
            {error, {auxiliary_forbidden_category, AuxiliaryId, NuggetId, Category}};
        false ->
            validate_auxiliary_specific_nodes(AuxiliaryId, Rest, Motherlode)
    end.

-spec validate_auxiliary_constraints(
    smelterl:auxiliary_target(),
    smelterl:motherlode()
) ->
    {ok, flavor_map()} | {error, term()}.
validate_auxiliary_constraints(Auxiliary, Motherlode) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    RootNugget = maps:get(root_nugget, Auxiliary),
    maybe
        {ok, #{versions := Versions, flavor := Flavor}} ?= parse_auxiliary_constraints(
            maps:get(constraints, Auxiliary, []),
            #{versions => [], flavor => undefined}
        ),
        ok ?= validate_version_constraints(
            AuxiliaryId,
            RootNugget,
            Versions,
            Motherlode,
            incompatible_auxiliary_version
        ),
        resolve_auxiliary_flavor(RootNugget, Flavor, Motherlode)
    else
        {error, _} = Error ->
            Error
    end.

resolve_auxiliary_flavor(_RootNugget, undefined, _Motherlode) ->
    {ok, #{}};
resolve_auxiliary_flavor(RootNugget, Flavor, Motherlode) ->
    ensure_flavor(RootNugget, Flavor, Motherlode, #{}).

parse_auxiliary_constraints([], Acc) ->
    {ok, Acc};
parse_auxiliary_constraints([{version, Version} | Rest], Acc)
  when is_binary(Version) ->
    Versions = maps:get(versions, Acc),
    parse_auxiliary_constraints(Rest, Acc#{versions := [Version | Versions]});
parse_auxiliary_constraints([{flavor, Flavor} | Rest], Acc)
  when is_atom(Flavor) ->
    case maps:get(flavor, Acc) of
        undefined ->
            parse_auxiliary_constraints(Rest, Acc#{flavor := Flavor});
        Flavor ->
            parse_auxiliary_constraints(Rest, Acc);
        _Other ->
            {error, {invalid_auxiliary_constraint, {flavor, Flavor}}}
    end;
parse_auxiliary_constraints([Constraint | _Rest], _Acc) ->
    {error, {invalid_auxiliary_constraint, Constraint}};
parse_auxiliary_constraints(InvalidConstraints, _Acc) ->
    {error, {invalid_auxiliary_constraint, InvalidConstraints}}.

validate_shared_flavors(AuxiliaryId, MainFlavors, AuxiliaryFlavors, MainTree, AuxiliaryTree) ->
    MainNodeSet = maps:from_list([{NodeId, true} || NodeId <- tree_node_ids(MainTree)]),
    SharedIds = [
        NodeId
     || NodeId <- tree_node_ids(AuxiliaryTree),
        maps:is_key(NodeId, MainNodeSet)
    ],
    validate_shared_flavors(SharedIds, AuxiliaryId, MainFlavors, AuxiliaryFlavors).

validate_shared_flavors([], _AuxiliaryId, _MainFlavors, _AuxiliaryFlavors) ->
    ok;
validate_shared_flavors([NuggetId | Rest], AuxiliaryId, MainFlavors, AuxiliaryFlavors) ->
    MainFlavor = maps:get(NuggetId, MainFlavors, undefined),
    AuxiliaryFlavor = maps:get(NuggetId, AuxiliaryFlavors, undefined),
    case {MainFlavor, AuxiliaryFlavor} of
        {undefined, undefined} ->
            validate_shared_flavors(Rest, AuxiliaryId, MainFlavors, AuxiliaryFlavors);
        {Flavor, Flavor} ->
            validate_shared_flavors(Rest, AuxiliaryId, MainFlavors, AuxiliaryFlavors);
        _ ->
            {error,
                {shared_flavor_mismatch,
                    AuxiliaryId,
                    NuggetId,
                    MainFlavor,
                    AuxiliaryFlavor}}
    end.

validate_target_hook_scopes(Targets, Motherlode, AuxiliaryIds) ->
    AuxiliaryIdSet = maps:from_list([{Id, true} || Id <- AuxiliaryIds]),
    NuggetIds = target_nugget_ids(Targets),
    validate_hook_scopes(NuggetIds, Motherlode, AuxiliaryIdSet).

-spec validate_hook_scopes(
    [smelterl:nugget_id()],
    smelterl:motherlode(),
    #{smelterl:nugget_id() => true}
) ->
    ok | {error, term()}.
validate_hook_scopes([], _Motherlode, _AuxiliaryIdSet) ->
    ok;
validate_hook_scopes([NuggetId | Rest], Motherlode, AuxiliaryIdSet) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    case validate_nugget_hooks(NuggetId, maps:get(hooks, Nugget, []), AuxiliaryIdSet) of
        ok ->
            validate_hook_scopes(Rest, Motherlode, AuxiliaryIdSet);
        {error, _} = Error ->
            Error
    end.

validate_nugget_hooks(_NuggetId, [], _AuxiliaryIdSet) ->
    ok;
validate_nugget_hooks(NuggetId, Hooks, AuxiliaryIdSet) when is_list(Hooks) ->
    validate_hook_entries(NuggetId, Hooks, AuxiliaryIdSet);
validate_nugget_hooks(NuggetId, Hooks, _AuxiliaryIdSet) ->
    {error, {invalid_hooks_metadata, NuggetId, Hooks}}.

validate_hook_entries(_NuggetId, [], _AuxiliaryIdSet) ->
    ok;
validate_hook_entries(NuggetId, [Hook | Rest], AuxiliaryIdSet) ->
    case validate_hook_entry(NuggetId, Hook, AuxiliaryIdSet) of
        ok ->
            validate_hook_entries(NuggetId, Rest, AuxiliaryIdSet);
        {error, _} = Error ->
            Error
    end.

validate_hook_entry(NuggetId, {HookType, _ScriptPath}, AuxiliaryIdSet) ->
    validate_hook_scope(NuggetId, HookType, main, AuxiliaryIdSet);
validate_hook_entry(NuggetId, {HookType, _ScriptPath, Scope}, AuxiliaryIdSet) ->
    validate_hook_scope(NuggetId, HookType, Scope, AuxiliaryIdSet);
validate_hook_entry(NuggetId, Hook, _AuxiliaryIdSet) ->
    {error, {invalid_hook, NuggetId, Hook}}.

validate_hook_scope(NuggetId, HookType, Scope, AuxiliaryIdSet) ->
    case valid_hook_type(HookType) of
        false ->
            {error, {invalid_hook_type, NuggetId, HookType}};
        true ->
            case Scope of
                main ->
                    ok;
                all ->
                    ok;
                auxiliary ->
                    case firmware_hook_type(HookType) of
                        true ->
                            {error, {invalid_firmware_hook_scope, NuggetId, HookType, Scope}};
                        false ->
                            ok
                    end;
                _ when is_atom(Scope) ->
                    case maps:is_key(Scope, AuxiliaryIdSet) of
                        true ->
                            case firmware_hook_type(HookType) of
                                true ->
                                    {error,
                                        {invalid_firmware_hook_scope,
                                            NuggetId,
                                            HookType,
                                            Scope}};
                                false ->
                                    ok
                            end;
                        false ->
                            {error, {unknown_hook_scope, NuggetId, HookType, Scope}}
                    end;
                _ ->
                    {error, {invalid_hook_scope, NuggetId, HookType, Scope}}
            end
    end.

valid_hook_type(HookType) ->
    lists:member(HookType, ?SDK_HOOK_TYPES ++ ?FIRMWARE_HOOK_TYPES).

firmware_hook_type(HookType) ->
    lists:member(HookType, ?FIRMWARE_HOOK_TYPES).

-spec replacement_tree(
    smelterl:nugget_id(),
    smelterl:nugget_id(),
    smelterl:nugget_tree(),
    smelterl:motherlode()
) ->
    {ok, smelterl:nugget_tree()} | {error, term()}.
replacement_tree(NewNuggetId, ReplacedNuggetId, Tree, Motherlode) ->
    Edges0 = maps:get(edges, Tree),
    AvailableNodes =
        maps:remove(
            ReplacedNuggetId,
            maps:from_list([{NodeId, true} || NodeId <- maps:keys(Edges0)])
        ),
    maybe
        {ok, ReplacementDeps} ?= replacement_dependency_ids(
            NewNuggetId,
            maps:get(depends_on, lookup_nugget(NewNuggetId, Motherlode), []),
            AvailableNodes
        ),
        Edges1 = maps:remove(ReplacedNuggetId, Edges0),
        Edges2 = rewrite_edge_dependencies(
            maps:to_list(Edges1),
            ReplacedNuggetId,
            NewNuggetId,
            #{}
        ),
        Root =
            case maps:get(root, Tree) of
                ReplacedNuggetId -> NewNuggetId;
                OtherRoot -> OtherRoot
            end,
        {ok,
            #{
                root => Root,
                edges => maps:put(NewNuggetId, ReplacementDeps, Edges2)
            }}
    else
        {error, _} = Error ->
            Error
    end.

replacement_dependency_ids(_NewNuggetId, [], _AvailableNodes) ->
    {ok, []};
replacement_dependency_ids(NewNuggetId, DependsOn, AvailableNodes)
  when is_list(DependsOn) ->
    replacement_dependency_ids(NewNuggetId, DependsOn, AvailableNodes, []);
replacement_dependency_ids(NewNuggetId, DependsOn, _AvailableNodes) ->
    {error, {invalid_dependency_constraints, NewNuggetId, DependsOn}}.

replacement_dependency_ids(_NewNuggetId, [], _AvailableNodes, Acc) ->
    {ok, lists:reverse(Acc)};
replacement_dependency_ids(NewNuggetId, [Constraint | Rest], AvailableNodes, Acc) ->
    case replacement_constraint_ids(NewNuggetId, Constraint, AvailableNodes) of
        {ok, DependencyIds} ->
            replacement_dependency_ids(
                NewNuggetId,
                Rest,
                AvailableNodes,
                lists:reverse(DependencyIds) ++ Acc
            );
        {error, _} = Error ->
            Error
    end.

replacement_constraint_ids(NewNuggetId, {required, nugget, Spec}, AvailableNodes) ->
    required_replacement_dependency(
        NewNuggetId,
        Spec,
        required,
        AvailableNodes
    );
replacement_constraint_ids(NewNuggetId, {optional, nugget, Spec}, AvailableNodes) ->
    optional_replacement_dependency(NewNuggetId, Spec, AvailableNodes);
replacement_constraint_ids(NewNuggetId, {one_of, nugget, Specs}, AvailableNodes)
  when is_list(Specs) ->
    multi_replacement_dependencies(NewNuggetId, Specs, one_of, AvailableNodes);
replacement_constraint_ids(NewNuggetId, {any_of, nugget, Specs}, AvailableNodes)
  when is_list(Specs) ->
    multi_replacement_dependencies(NewNuggetId, Specs, any_of, AvailableNodes);
replacement_constraint_ids(_NewNuggetId, {conflicts_with, nugget, _Spec}, _AvailableNodes) ->
    {ok, []};
replacement_constraint_ids(_NewNuggetId, {_Type, category, _Spec}, _AvailableNodes) ->
    {ok, []};
replacement_constraint_ids(_NewNuggetId, {_Type, capability, _Spec}, _AvailableNodes) ->
    {ok, []};
replacement_constraint_ids(NewNuggetId, Constraint, _AvailableNodes) ->
    {error, {invalid_dependency_constraint, NewNuggetId, Constraint}}.

required_replacement_dependency(NewNuggetId, Spec, ConstraintType, AvailableNodes) ->
    case parse_dependency_spec(Spec) of
        {ok, #{id := DependencyId}} ->
            case maps:is_key(DependencyId, AvailableNodes) of
                true ->
                    {ok, [DependencyId]};
                false ->
                    {error,
                        {missing_nugget_dependency,
                            NewNuggetId,
                            DependencyId,
                            ConstraintType}}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NewNuggetId, Spec}}
    end.

optional_replacement_dependency(NewNuggetId, Spec, AvailableNodes) ->
    case parse_dependency_spec(Spec) of
        {ok, #{id := DependencyId}} ->
            case maps:is_key(DependencyId, AvailableNodes) of
                true ->
                    {ok, [DependencyId]};
                false ->
                    {ok, []}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NewNuggetId, Spec}}
    end.

multi_replacement_dependencies(NewNuggetId, Specs, ConstraintType, AvailableNodes) ->
    case parse_dependency_specs(Specs, []) of
        {ok, ParsedSpecs} ->
            DependencyIds = [maps:get(id, ParsedSpec) || ParsedSpec <- ParsedSpecs],
            PresentIds = [
                DependencyId
             || DependencyId <- DependencyIds,
                maps:is_key(DependencyId, AvailableNodes)
            ],
            case PresentIds of
                [] ->
                    {error,
                        {missing_nugget_dependency,
                            NewNuggetId,
                            hd(DependencyIds),
                            ConstraintType}};
                _ ->
                    {ok, PresentIds}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NewNuggetId, Specs}}
    end.

rewrite_edge_dependencies([], _ReplacedNuggetId, _NewNuggetId, Acc) ->
    Acc;
rewrite_edge_dependencies(
    [{NodeId, Dependencies0} | Rest],
    ReplacedNuggetId,
    NewNuggetId,
    Acc
) ->
    Dependencies = dedupe_keep_first([
        case DependencyId of
            ReplacedNuggetId -> NewNuggetId;
            _Other -> DependencyId
        end
     || DependencyId <- Dependencies0
    ]),
    rewrite_edge_dependencies(
        Rest,
        ReplacedNuggetId,
        NewNuggetId,
        maps:put(NodeId, Dependencies, Acc)
    ).

-spec validate_tree_with_flavors(
    smelterl:nugget_tree(),
    smelterl:motherlode(),
    flavor_map()
) ->
    {ok, flavor_map()} | {error, term()}.
validate_tree_with_flavors(Tree, Motherlode, InitialFlavors) ->
    case validate_category_cardinality(Tree, Motherlode) of
        ok ->
            Context = build_tree_context(Tree, Motherlode),
            validate_tree_nodes(maps:get(node_ids, Context), Motherlode, Context, InitialFlavors);
        {error, _} = Error ->
            Error
    end.

validate_category_cardinality(Tree, Motherlode) ->
    validate_category_cardinality(?EXACTLY_ONE_CATEGORIES, Tree, Motherlode).

validate_category_cardinality([], _Tree, _Motherlode) ->
    ok;
validate_category_cardinality([Category | Rest], Tree, Motherlode) ->
    NuggetIds = category_ids(Category, Tree, Motherlode),
    case length(NuggetIds) of
        1 ->
            validate_category_cardinality(Rest, Tree, Motherlode);
        Count ->
            {error, {bad_category_cardinality, Category, Count, NuggetIds}}
    end.

validate_tree_nodes([], _Motherlode, _Context, FlavorMap) ->
    {ok, FlavorMap};
validate_tree_nodes([NuggetId | Rest], Motherlode, Context, FlavorMap0) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    case validate_nugget_dependencies(
        NuggetId,
        maps:get(depends_on, Nugget, []),
        Motherlode,
        Context,
        FlavorMap0
    ) of
        {ok, FlavorMap1} ->
            validate_tree_nodes(Rest, Motherlode, Context, FlavorMap1);
        {error, _} = Error ->
            Error
    end.

validate_nugget_dependencies(_NuggetId, [], _Motherlode, _Context, FlavorMap) ->
    {ok, FlavorMap};
validate_nugget_dependencies(NuggetId, DependsOn, Motherlode, Context, FlavorMap)
  when is_list(DependsOn) ->
    validate_dependency_constraints(NuggetId, DependsOn, Motherlode, Context, FlavorMap);
validate_nugget_dependencies(NuggetId, DependsOn, _Motherlode, _Context, _FlavorMap) ->
    {error, {invalid_dependency_constraints, NuggetId, DependsOn}}.

validate_dependency_constraints(_NuggetId, [], _Motherlode, _Context, FlavorMap) ->
    {ok, FlavorMap};
validate_dependency_constraints(NuggetId, [Constraint | Rest], Motherlode, Context, FlavorMap0) ->
    case validate_dependency_constraint(NuggetId, Constraint, Motherlode, Context, FlavorMap0) of
        {ok, FlavorMap1} ->
            validate_dependency_constraints(NuggetId, Rest, Motherlode, Context, FlavorMap1);
        {error, _} = Error ->
            Error
    end.

validate_dependency_constraint(NuggetId, {required, category, Category}, _Motherlode, Context, FlavorMap)
  when is_atom(Category) ->
    case match_count(category, Category, Context) of
        0 ->
            {error, {missing_category_dependency, NuggetId, Category, required}};
        _ ->
            {ok, FlavorMap}
    end;
validate_dependency_constraint(_NuggetId, {optional, category, Category}, _Motherlode, _Context, FlavorMap)
  when is_atom(Category) ->
    {ok, FlavorMap};
validate_dependency_constraint(NuggetId, {one_of, category, Categories}, _Motherlode, Context, FlavorMap)
  when is_list(Categories) ->
    validate_list_constraint_count(NuggetId, one_of, category, Categories, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {any_of, category, Categories}, _Motherlode, Context, FlavorMap)
  when is_list(Categories) ->
    validate_list_constraint_count(NuggetId, any_of, category, Categories, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {required, capability, Capability}, _Motherlode, Context, FlavorMap)
  when is_atom(Capability) ->
    case match_count(capability, Capability, Context) of
        0 ->
            {error, {missing_capability_dependency, NuggetId, Capability}};
        _ ->
            {ok, FlavorMap}
    end;
validate_dependency_constraint(_NuggetId, {optional, capability, Capability}, _Motherlode, _Context, FlavorMap)
  when is_atom(Capability) ->
    {ok, FlavorMap};
validate_dependency_constraint(NuggetId, {one_of, capability, Capabilities}, _Motherlode, Context, FlavorMap)
  when is_list(Capabilities) ->
    validate_list_constraint_count(
        NuggetId,
        one_of,
        capability,
        Capabilities,
        Context,
        FlavorMap
    );
validate_dependency_constraint(NuggetId, {any_of, capability, Capabilities}, _Motherlode, Context, FlavorMap)
  when is_list(Capabilities) ->
    validate_list_constraint_count(
        NuggetId,
        any_of,
        capability,
        Capabilities,
        Context,
        FlavorMap
    );
validate_dependency_constraint(NuggetId, {required, nugget, Spec}, Motherlode, Context, FlavorMap) ->
    validate_present_dependency_spec(NuggetId, required, Spec, Motherlode, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {optional, nugget, Spec}, Motherlode, Context, FlavorMap) ->
    validate_optional_dependency_spec(NuggetId, Spec, Motherlode, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {one_of, nugget, Specs}, Motherlode, Context, FlavorMap)
  when is_list(Specs) ->
    validate_multi_dependency_specs(NuggetId, one_of, Specs, Motherlode, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {any_of, nugget, Specs}, Motherlode, Context, FlavorMap)
  when is_list(Specs) ->
    validate_multi_dependency_specs(NuggetId, any_of, Specs, Motherlode, Context, FlavorMap);
validate_dependency_constraint(NuggetId, {conflicts_with, nugget, Spec}, _Motherlode, Context, FlavorMap) ->
    case parse_dependency_spec(Spec) of
        {ok, #{id := TargetId}} ->
            case maps:is_key(TargetId, maps:get(node_set, Context)) of
                true ->
                    {error, {nugget_conflict, NuggetId, TargetId}};
                false ->
                    {ok, FlavorMap}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Spec}}
    end;
validate_dependency_constraint(NuggetId, {conflicts_with, capability, Capability}, _Motherlode, Context, FlavorMap)
  when is_atom(Capability) ->
    case match_count(capability, Capability, Context) of
        0 ->
            {ok, FlavorMap};
        _ ->
            {error, {capability_conflict, NuggetId, capability, Capability}}
    end;
validate_dependency_constraint(NuggetId, Constraint, _Motherlode, _Context, _FlavorMap) ->
    {error, {invalid_dependency_constraint, NuggetId, Constraint}}.

validate_list_constraint_count(NuggetId, ConstraintType, TargetType, Values, Context, FlavorMap) ->
    Count = list_constraint_match_count(TargetType, Values, Context),
    case dependency_count_valid(ConstraintType, Count) of
        true ->
            {ok, FlavorMap};
        false ->
            {error,
                {invalid_dependency_match_count,
                    NuggetId,
                    ConstraintType,
                    TargetType,
                    Values,
                    Count}}
    end.

validate_present_dependency_spec(NuggetId, ConstraintType, Spec, Motherlode, Context, FlavorMap0) ->
    case parse_dependency_spec(Spec) of
        {ok, ParsedSpec = #{id := TargetId}} ->
            case maps:is_key(TargetId, maps:get(node_set, Context)) of
                false ->
                    {error, {missing_nugget_dependency, NuggetId, TargetId, ConstraintType}};
                true ->
                    validate_dependency_spec(NuggetId, ParsedSpec, Motherlode, FlavorMap0)
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Spec}}
    end.

validate_optional_dependency_spec(NuggetId, Spec, Motherlode, Context, FlavorMap0) ->
    case parse_dependency_spec(Spec) of
        {ok, ParsedSpec = #{id := TargetId}} ->
            case maps:is_key(TargetId, maps:get(node_set, Context)) of
                false ->
                    {ok, FlavorMap0};
                true ->
                    validate_dependency_spec(NuggetId, ParsedSpec, Motherlode, FlavorMap0)
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Spec}}
    end.

validate_multi_dependency_specs(NuggetId, ConstraintType, Specs, Motherlode, Context, FlavorMap0) ->
    case parse_dependency_specs(Specs, []) of
        {ok, ParsedSpecs} ->
            PresentSpecs = [
                ParsedSpec
             || ParsedSpec = #{id := TargetId} <- ParsedSpecs,
                maps:is_key(TargetId, maps:get(node_set, Context))
            ],
            Count = length(PresentSpecs),
            case dependency_count_valid(ConstraintType, Count) of
                false ->
                    {error,
                        {invalid_dependency_match_count,
                            NuggetId,
                            ConstraintType,
                            nugget,
                            [maps:get(id, ParsedSpec) || ParsedSpec <- ParsedSpecs],
                            Count}};
                true ->
                    validate_dependency_specs(NuggetId, PresentSpecs, Motherlode, FlavorMap0)
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, NuggetId, Specs}}
    end.

parse_dependency_specs([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_dependency_specs([Spec | Rest], Acc) ->
    case parse_dependency_spec(Spec) of
        {ok, ParsedSpec} ->
            parse_dependency_specs(Rest, [ParsedSpec | Acc]);
        {error, _} = Error ->
            Error
    end.

validate_dependency_specs(_NuggetId, [], _Motherlode, FlavorMap) ->
    {ok, FlavorMap};
validate_dependency_specs(NuggetId, [ParsedSpec | Rest], Motherlode, FlavorMap0) ->
    case validate_dependency_spec(NuggetId, ParsedSpec, Motherlode, FlavorMap0) of
        {ok, FlavorMap1} ->
            validate_dependency_specs(NuggetId, Rest, Motherlode, FlavorMap1);
        {error, _} = Error ->
            Error
    end.

validate_dependency_spec(NuggetId, ParsedSpec, Motherlode, FlavorMap0) ->
    TargetId = maps:get(id, ParsedSpec),
    case validate_version_constraints(
        NuggetId,
        TargetId,
        maps:get(versions, ParsedSpec, []),
        Motherlode,
        incompatible_version
    ) of
        ok ->
            case maps:get(flavor, ParsedSpec, undefined) of
                undefined ->
                    {ok, FlavorMap0};
                Flavor ->
                    ensure_flavor(TargetId, Flavor, Motherlode, FlavorMap0)
            end;
        {error, _} = Error ->
            Error
    end.

validate_version_constraints(_RequesterId, _TargetId, [], _Motherlode, _ErrorTag) ->
    ok;
validate_version_constraints(RequesterId, TargetId, [Required | Rest], Motherlode, ErrorTag) ->
    Actual = maps:get(version, lookup_nugget(TargetId, Motherlode), undefined),
    case version_satisfies(Required, Actual) of
        true ->
            validate_version_constraints(RequesterId, TargetId, Rest, Motherlode, ErrorTag);
        false ->
            {error, version_error(ErrorTag, RequesterId, TargetId, Required, Actual)}
    end.

version_error(incompatible_auxiliary_version, RequesterId, TargetId, Required, Actual) ->
    {incompatible_auxiliary_version, RequesterId, TargetId, Required, Actual};
version_error(incompatible_version, RequesterId, TargetId, Required, Actual) ->
    {incompatible_version, RequesterId, TargetId, Required, Actual}.

ensure_flavor(TargetId, Flavor, Motherlode, FlavorMap0) ->
    Flavors = maps:get(flavors, lookup_nugget(TargetId, Motherlode), []),
    case lists:member(Flavor, Flavors) of
        false ->
            {error, {invalid_flavor, TargetId, Flavor}};
        true ->
            case maps:get(TargetId, FlavorMap0, undefined) of
                undefined ->
                    {ok, maps:put(TargetId, Flavor, FlavorMap0)};
                Flavor ->
                    {ok, FlavorMap0};
                _Other ->
                    {error, {flavor_mismatch, TargetId, Flavor}}
            end
    end.

parse_dependency_spec(DependencyId) when is_atom(DependencyId) ->
    {ok, #{id => DependencyId, versions => [], flavor => undefined}};
parse_dependency_spec({DependencyId, Version}) when is_atom(DependencyId), is_binary(Version) ->
    {ok, #{id => DependencyId, versions => [Version], flavor => undefined}};
parse_dependency_spec({DependencyId, ConstraintProps})
  when is_atom(DependencyId), is_list(ConstraintProps) ->
    case parse_dependency_props(ConstraintProps, #{versions => [], flavor => undefined}) of
        {ok, ParsedProps} ->
            {ok, ParsedProps#{id => DependencyId}};
        {error, _} = Error ->
            Error
    end;
parse_dependency_spec(_Spec) ->
    {error, invalid_dependency_spec}.

parse_dependency_props([], ParsedProps) ->
    {ok, ParsedProps};
parse_dependency_props([{version, Version} | Rest], ParsedProps) when is_binary(Version) ->
    Versions = maps:get(versions, ParsedProps),
    parse_dependency_props(Rest, ParsedProps#{versions := [Version | Versions]});
parse_dependency_props([{flavor, Flavor} | Rest], ParsedProps) when is_atom(Flavor) ->
    case maps:get(flavor, ParsedProps) of
        undefined ->
            parse_dependency_props(Rest, ParsedProps#{flavor := Flavor});
        Flavor ->
            parse_dependency_props(Rest, ParsedProps);
        _Other ->
            {error, invalid_dependency_spec}
    end;
parse_dependency_props([_Invalid | _], _ParsedProps) ->
    {error, invalid_dependency_spec}.

rewrite_motherlode_nugget_refs(ReplacedNuggetId, NewNuggetId, Motherlode) ->
    Nuggets0 = maps:get(nuggets, Motherlode),
    Nuggets1 = maps:map(
        fun(_NuggetId, Nugget) ->
            Nugget#{
                depends_on := rewrite_dependency_constraints(
                    maps:get(depends_on, Nugget, []),
                    ReplacedNuggetId,
                    NewNuggetId
                )
            }
        end,
        Nuggets0
    ),
    Motherlode#{nuggets := Nuggets1}.

rewrite_dependency_constraints(DependsOn, _ReplacedNuggetId, _NewNuggetId)
  when not is_list(DependsOn) ->
    DependsOn;
rewrite_dependency_constraints(DependsOn, ReplacedNuggetId, NewNuggetId) ->
    [
        rewrite_dependency_constraint(
            Constraint,
            ReplacedNuggetId,
            NewNuggetId
        )
     || Constraint <- DependsOn
    ].

rewrite_dependency_constraint(
    {ConstraintType, nugget, Specs},
    ReplacedNuggetId,
    NewNuggetId
)
  when ConstraintType =:= one_of; ConstraintType =:= any_of ->
    {ConstraintType,
        nugget,
        [
            rewrite_dependency_spec(Spec, ReplacedNuggetId, NewNuggetId)
         || Spec <- Specs
        ]};
rewrite_dependency_constraint(
    {ConstraintType, nugget, Spec},
    ReplacedNuggetId,
    NewNuggetId
) ->
    {ConstraintType,
        nugget,
        rewrite_dependency_spec(Spec, ReplacedNuggetId, NewNuggetId)};
rewrite_dependency_constraint(Constraint, _ReplacedNuggetId, _NewNuggetId) ->
    Constraint.

rewrite_dependency_spec(ReplacedNuggetId, ReplacedNuggetId, NewNuggetId) ->
    NewNuggetId;
rewrite_dependency_spec(
    {ReplacedNuggetId, Version},
    ReplacedNuggetId,
    NewNuggetId
) ->
    {NewNuggetId, Version};
rewrite_dependency_spec(
    {ReplacedNuggetId, ConstraintProps},
    ReplacedNuggetId,
    NewNuggetId
) ->
    {NewNuggetId, ConstraintProps};
rewrite_dependency_spec(Spec, _ReplacedNuggetId, _NewNuggetId) ->
    Spec.

-spec build_tree_context(smelterl:nugget_tree(), smelterl:motherlode()) ->
    tree_context().
build_tree_context(Tree, Motherlode) ->
    NodeIds = tree_node_ids(Tree),
    #{
        node_ids => NodeIds,
        node_set => maps:from_list([{NodeId, true} || NodeId <- NodeIds]),
        categories => category_map(NodeIds, Motherlode),
        capabilities => capability_map(NodeIds, Motherlode)
    }.

category_map(NodeIds, Motherlode) ->
    lists:foldl(
        fun(NuggetId, Acc) ->
            Category = nugget_category(NuggetId, Motherlode),
            Existing = maps:get(Category, Acc, []),
            maps:put(Category, Existing ++ [NuggetId], Acc)
        end,
        #{},
        NodeIds
    ).

capability_map(NodeIds, Motherlode) ->
    lists:foldl(
        fun(NuggetId, Acc0) ->
            lists:foldl(
                fun(Capability, Acc1) ->
                    Existing = maps:get(Capability, Acc1, []),
                    maps:put(Capability, Existing ++ [NuggetId], Acc1)
                end,
                Acc0,
                maps:get(provides, lookup_nugget(NuggetId, Motherlode), [])
            )
        end,
        #{},
        NodeIds
    ).

match_count(category, Category, Context) ->
    length(maps:get(Category, maps:get(categories, Context), []));
match_count(capability, Capability, Context) ->
    length(maps:get(Capability, maps:get(capabilities, Context), [])).

list_constraint_match_count(category, Categories, Context) ->
    length([Category || Category <- Categories, match_count(category, Category, Context) > 0]);
list_constraint_match_count(capability, Capabilities, Context) ->
    length([
        Capability
     || Capability <- Capabilities,
        match_count(capability, Capability, Context) > 0
    ]).

dependency_count_valid(one_of, Count) ->
    Count =:= 1;
dependency_count_valid(any_of, Count) ->
    Count >= 1.

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

target_nugget_ids(Targets) ->
    lists:usort(
        tree_node_ids(maps:get(main, Targets)) ++
            lists:append([
                tree_node_ids(maps:get(tree, Auxiliary))
             || Auxiliary <- maps:get(auxiliaries, Targets, [])
            ])
    ).

auxiliary_ids(Auxiliaries) ->
    [maps:get(id, Auxiliary) || Auxiliary <- Auxiliaries].

category_ids(Category, Tree, Motherlode) ->
    [
        NuggetId
     || NuggetId <- tree_node_ids(Tree),
        nugget_category(NuggetId, Motherlode) =:= Category
    ].

tree_node_ids(Tree) ->
    lists:sort(maps:keys(maps:get(edges, Tree))).

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode)).

nugget_category(NuggetId, Motherlode) ->
    maps:get(category, lookup_nugget(NuggetId, Motherlode), undefined).

version_satisfies(_Required, undefined) ->
    false;
version_satisfies(Required, Actual) when is_binary(Required), is_binary(Actual) ->
    case {
        parse_version_constraint(Required),
        parse_version(Actual)
    } of
        {{ok, Constraint}, {ok, ActualVersion, _Count}} ->
            evaluate_version_constraint(Constraint, ActualVersion);
        _ ->
            false
    end;
version_satisfies(_Required, _Actual) ->
    false.

parse_version_constraint(Required) ->
    Trimmed = trim_binary(Required),
    case Trimmed of
        <<$~, $>, Rest/binary>> ->
            case parse_version(trim_binary(Rest)) of
                {ok, Version, Count} ->
                    {ok, {pessimistic, Version, Count}};
                {error, _} = Error ->
                    Error
            end;
        <<$>, $=, Rest/binary>> ->
            parse_binary_constraint(ge, Rest);
        <<$<, $=, Rest/binary>> ->
            parse_binary_constraint(le, Rest);
        <<$>, Rest/binary>> ->
            parse_binary_constraint(gt, Rest);
        <<$<, Rest/binary>> ->
            parse_binary_constraint(lt, Rest);
        <<$=, Rest/binary>> ->
            parse_binary_constraint(eq, Rest);
        _ ->
            case parse_version(Trimmed) of
                {ok, Version, _Count} ->
                    {ok, {eq, Version}};
                {error, _} = Error ->
                    Error
            end
    end.

parse_binary_constraint(Op, VersionBinary) ->
    case parse_version(trim_binary(VersionBinary)) of
        {ok, Version, _Count} ->
            {ok, {Op, Version}};
        {error, _} = Error ->
            Error
    end.

evaluate_version_constraint({eq, Required}, Actual) ->
    compare_versions(Actual, Required) =:= eq;
evaluate_version_constraint({ge, Required}, Actual) ->
    compare_versions(Actual, Required) =/= lt;
evaluate_version_constraint({gt, Required}, Actual) ->
    compare_versions(Actual, Required) =:= gt;
evaluate_version_constraint({le, Required}, Actual) ->
    compare_versions(Actual, Required) =/= gt;
evaluate_version_constraint({lt, Required}, Actual) ->
    compare_versions(Actual, Required) =:= lt;
evaluate_version_constraint({pessimistic, Lower, Count}, Actual) ->
    Upper = pessimistic_upper_bound(Lower, Count),
    compare_versions(Actual, Lower) =/= lt andalso
        compare_versions(Actual, Upper) =:= lt.

parse_version(Version) when is_binary(Version) ->
    Parts = binary:split(trim_binary(Version), <<".">>, [global]),
    parse_version_parts(Parts, []).

parse_version_parts([], Acc) ->
    case Acc of
        [] ->
            {error, invalid_version};
        _ ->
            case pad_version(lists:reverse(Acc)) of
                {ok, Padded} ->
                    {ok, list_to_tuple(Padded), length(Acc)};
                {error, _} = Error ->
                    Error
            end
    end;
parse_version_parts([Part | Rest], Acc) ->
    case binary_to_integer_safe(Part) of
        {ok, Value} ->
            parse_version_parts(Rest, [Value | Acc]);
        {error, _} = Error ->
            Error
    end.

pad_version(Values) when length(Values) =:= 1 ->
    {ok, Values ++ [0, 0]};
pad_version(Values) when length(Values) =:= 2 ->
    {ok, Values ++ [0]};
pad_version(Values) when length(Values) =:= 3 ->
    {ok, Values};
pad_version(_Values) ->
    {error, invalid_version}.

binary_to_integer_safe(<<>>) ->
    {error, invalid_version};
binary_to_integer_safe(Binary) ->
    case lists:all(fun(Char) -> Char >= $0 andalso Char =< $9 end, binary_to_list(Binary)) of
        true ->
            {ok, binary_to_integer(Binary)};
        false ->
            {error, invalid_version}
    end.

compare_versions({A1, B1, C1}, {A2, B2, C2}) ->
    compare_lists([A1, B1, C1], [A2, B2, C2]).

compare_lists([Value | Rest1], [Value | Rest2]) ->
    compare_lists(Rest1, Rest2);
compare_lists([Value1 | _Rest1], [Value2 | _Rest2]) when Value1 > Value2 ->
    gt;
compare_lists([_Value1 | _Rest1], [_Value2 | _Rest2]) ->
    lt;
compare_lists([], []) ->
    eq.

pessimistic_upper_bound({Major, _Minor, _Patch}, Count) when Count =< 2 ->
    {Major + 1, 0, 0};
pessimistic_upper_bound({Major, Minor, _Patch}, _Count) ->
    {Major, Minor + 1, 0}.

trim_binary(Binary) ->
    list_to_binary(string:trim(binary_to_list(Binary))).
