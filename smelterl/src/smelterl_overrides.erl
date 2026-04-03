%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_overrides).
-moduledoc """
Apply Smelterl override metadata to validated target trees.

Overrides are collected from the main target in topology order, then applied in
three phases: auxiliary remaps, nugget replacements, and config overrides.
The result is a target set plus target-local motherlode views ready for later
planning stages.
""".

%=== EXPORTS ===================================================================

-export([apply_overrides/3]).


%=== API FUNCTIONS =============================================================

-doc """
Apply override metadata collected from the main target tree.

Returns updated targets, recomputed topology orders, and target-specific
motherlode views carrying effective config overrides.
""".
-spec apply_overrides(
    smelterl:target_trees(),
    smelterl:topology_orders(),
    smelterl:motherlode()
) ->
    {ok,
        smelterl:target_trees(),
        smelterl:topology_orders(),
        smelterl:target_motherlodes()} |
        {error, term()}.
apply_overrides(Targets, TopologyOrders, Motherlode) ->
    maybe
        {ok, Overrides} ?= collect_overrides(Targets, TopologyOrders, Motherlode),
        {ok, Targets1, TopologyOrders1} ?= apply_auxiliary_remaps(
            Overrides,
            Targets,
            TopologyOrders,
            Motherlode
        ),
        {ok, Targets2, TopologyOrders2, Motherlode1} ?= apply_nugget_overrides(
            Overrides,
            Targets1,
            TopologyOrders1,
            Motherlode
        ),
        {ok, TargetMotherlodes} ?= apply_config_overrides(
            Overrides,
            Targets2,
            Motherlode1
        ),
        {ok, Targets2, TopologyOrders2, TargetMotherlodes}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

collect_overrides(Targets, TopologyOrders, Motherlode) ->
    MainTree = maps:get(main, Targets),
    MainOrder = maps:get(main, TopologyOrders),
    MainNodeSet =
        maps:from_list([{NodeId, true} || NodeId <- maps:keys(maps:get(edges, MainTree))]),
    collect_overrides(MainOrder, MainNodeSet, Motherlode, []).

collect_overrides([], _MainNodeSet, _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
collect_overrides([NuggetId | Rest], MainNodeSet, Motherlode, Acc) ->
    case maps:is_key(NuggetId, MainNodeSet) of
        false ->
            collect_overrides(Rest, MainNodeSet, Motherlode, Acc);
        true ->
            Nugget = lookup_nugget(NuggetId, Motherlode),
            case maps:get(overrides, Nugget, []) of
                Overrides when is_list(Overrides) ->
                    TaggedOverrides = [{NuggetId, Override} || Override <- Overrides],
                    collect_overrides(
                        Rest,
                        MainNodeSet,
                        Motherlode,
                        lists:reverse(TaggedOverrides) ++ Acc
                    );
                InvalidOverrides ->
                    {error, {invalid_overrides_metadata, NuggetId, InvalidOverrides}}
            end
    end.

apply_auxiliary_remaps(Overrides, Targets, TopologyOrders, Motherlode) ->
    SourceAuxiliaries = maps:get(auxiliaries, Targets, []),
    SourceMap = maps:from_list([
        {maps:get(id, Auxiliary), Auxiliary}
     || Auxiliary <- SourceAuxiliaries
    ]),
    apply_auxiliary_remaps(
        Overrides,
        Targets,
        TopologyOrders,
        SourceMap,
        Motherlode
    ).

apply_auxiliary_remaps([], Targets, TopologyOrders, _SourceMap, _Motherlode) ->
    {ok, Targets, TopologyOrders};
apply_auxiliary_remaps(
    [{OwnerNuggetId, {auxiliary_product, TargetAuxId, ReplacementAuxId}} | Rest],
    Targets0,
    _TopologyOrders,
    SourceMap,
    Motherlode
)
  when is_atom(TargetAuxId), is_atom(ReplacementAuxId) ->
    Auxiliaries0 = maps:get(auxiliaries, Targets0, []),
    maybe
        ok ?= ensure_auxiliary_target_exists(
            OwnerNuggetId,
            TargetAuxId,
            Auxiliaries0
        ),
        {ok, ReplacementAuxiliary} ?= source_auxiliary(
            OwnerNuggetId,
            ReplacementAuxId,
            SourceMap
        ),
        Auxiliaries1 = remap_auxiliaries(
            Auxiliaries0,
            TargetAuxId,
            ReplacementAuxiliary
        ),
        Targets1 = Targets0#{auxiliaries := Auxiliaries1},
        ok ?= revalidate_targets(Targets1, Motherlode),
        {ok, TopologyOrders1} ?= topology_orders(Targets1),
        apply_auxiliary_remaps(
            Rest,
            Targets1,
            TopologyOrders1,
            SourceMap,
            Motherlode
        )
    else
        {error, _} = Error ->
            Error
    end;
apply_auxiliary_remaps(
    [{OwnerNuggetId, {auxiliary_product, _, _} = Override} | _Rest],
    _Targets,
    _TopologyOrders,
    _SourceMap,
    _Motherlode
) ->
    {error, {invalid_override, OwnerNuggetId, Override}};
apply_auxiliary_remaps(
    [_OtherOverride | Rest],
    Targets,
    TopologyOrders,
    SourceMap,
    Motherlode
) ->
    apply_auxiliary_remaps(Rest, Targets, TopologyOrders, SourceMap, Motherlode).

apply_nugget_overrides(Overrides, Targets, TopologyOrders, Motherlode) ->
    apply_nugget_overrides(Overrides, Targets, TopologyOrders, Motherlode, false).

apply_nugget_overrides([], Targets, TopologyOrders, Motherlode, _AnyApplied) ->
    {ok, Targets, TopologyOrders, Motherlode};
apply_nugget_overrides(
    [{_OwnerNuggetId, {auxiliary_product, _, _}} | Rest],
    Targets,
    TopologyOrders,
    Motherlode,
    AnyApplied
) ->
    apply_nugget_overrides(Rest, Targets, TopologyOrders, Motherlode, AnyApplied);
apply_nugget_overrides(
    [{OwnerNuggetId, {nugget, TargetNuggetId, ReplacementNuggetId}} | Rest],
    Targets0,
    _TopologyOrders,
    Motherlode,
    _AnyApplied
)
  when is_atom(TargetNuggetId), is_atom(ReplacementNuggetId) ->
    maybe
        ok ?= ensure_replacement_exists(TargetNuggetId, ReplacementNuggetId, Motherlode),
        {ok, Targets1, Applied} ?= replace_nugget_in_targets(
            Targets0,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode
        ),
        ok ?= ensure_override_applied(OwnerNuggetId, TargetNuggetId, Applied),
        Motherlode1 = rewrite_motherlode_nugget_refs(
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode
        ),
        ok ?= revalidate_targets(Targets1, Motherlode1),
        {ok, TopologyOrders1} ?= topology_orders(Targets1),
        apply_nugget_overrides(
            Rest,
            Targets1,
            TopologyOrders1,
            Motherlode1,
            true
        )
    else
        {error, _} = Error ->
            Error
    end;
apply_nugget_overrides(
    [{OwnerNuggetId, {nugget, _, _} = Override} | _Rest],
    _Targets,
    _TopologyOrders,
    _Motherlode,
    _AnyApplied
) ->
    {error, {invalid_override, OwnerNuggetId, Override}};
apply_nugget_overrides(
    [_OtherOverride | Rest],
    Targets,
    TopologyOrders,
    Motherlode,
    AnyApplied
) ->
    apply_nugget_overrides(Rest, Targets, TopologyOrders, Motherlode, AnyApplied).

apply_config_overrides(Overrides, Targets, Motherlode) ->
    Views0 = initial_target_views(Targets, Motherlode),
    apply_config_overrides_in_views(Overrides, Targets, Views0).

apply_config_overrides_in_views([], _Targets, Views) ->
    {ok, Views};
apply_config_overrides_in_views(
    [{_OwnerNuggetId, {auxiliary_product, _, _}} | Rest],
    Targets,
    Views
) ->
    apply_config_overrides_in_views(Rest, Targets, Views);
apply_config_overrides_in_views(
    [{_OwnerNuggetId, {nugget, _, _}} | Rest],
    Targets,
    Views
) ->
    apply_config_overrides_in_views(Rest, Targets, Views);
apply_config_overrides_in_views(
    [{OwnerNuggetId, {config, ConfigKey, ConfigValue}} | Rest],
    Targets,
    Views0
)
  when is_atom(ConfigKey) ->
    maybe
        {ok, Views1} ?= apply_config_override_to_targets(
            [main],
            OwnerNuggetId,
            ConfigKey,
            ConfigValue,
            Targets,
            Views0
        ),
        apply_config_overrides_in_views(Rest, Targets, Views1)
    else
        {error, _} = Error ->
            Error
    end;
apply_config_overrides_in_views(
    [{OwnerNuggetId, {config, Scope, ConfigKey, ConfigValue}} | Rest],
    Targets,
    Views0
)
  when is_atom(Scope), is_atom(ConfigKey) ->
    maybe
        {ok, TargetIds} ?= config_target_ids(OwnerNuggetId, Scope, Targets),
        {ok, Views1} ?= apply_config_override_to_targets(
            TargetIds,
            OwnerNuggetId,
            ConfigKey,
            ConfigValue,
            Targets,
            Views0
        ),
        apply_config_overrides_in_views(Rest, Targets, Views1)
    else
        {error, _} = Error ->
            Error
    end;
apply_config_overrides_in_views(
    [{OwnerNuggetId, {config, _, _} = Override} | _Rest],
    _Targets,
    _Views
) ->
    {error, {invalid_override, OwnerNuggetId, Override}};
apply_config_overrides_in_views(
    [{OwnerNuggetId, {config, _, _, _} = Override} | _Rest],
    _Targets,
    _Views
) ->
    {error, {invalid_override, OwnerNuggetId, Override}};
apply_config_overrides_in_views([_OtherOverride | Rest], Targets, Views) ->
    apply_config_overrides_in_views(Rest, Targets, Views).

ensure_auxiliary_target_exists(_OwnerNuggetId, TargetAuxId, Auxiliaries) ->
    case lists:any(
        fun(Auxiliary) -> maps:get(id, Auxiliary) =:= TargetAuxId end,
        Auxiliaries
    ) of
        true ->
            ok;
        false ->
            {error, {unknown_auxiliary_override_target, TargetAuxId}}
    end.

source_auxiliary(_OwnerNuggetId, ReplacementAuxId, SourceMap) ->
    case maps:get(ReplacementAuxId, SourceMap, undefined) of
        undefined ->
            {error, {unknown_auxiliary_override_replacement, ReplacementAuxId}};
        Auxiliary ->
            {ok, Auxiliary}
    end.

remap_auxiliaries(Auxiliaries, TargetAuxId, ReplacementAuxiliary) ->
    [
        case maps:get(id, Auxiliary) of
            TargetAuxId -> ReplacementAuxiliary;
            _OtherAuxId -> Auxiliary
        end
     || Auxiliary <- Auxiliaries
    ].

ensure_replacement_exists(TargetNuggetId, ReplacementNuggetId, Motherlode) ->
    case maps:is_key(ReplacementNuggetId, maps:get(nuggets, Motherlode)) of
        true ->
            ok;
        false ->
            {error, {replacement_not_found, TargetNuggetId, ReplacementNuggetId}}
    end.

ensure_override_applied(_OwnerNuggetId, _TargetNuggetId, true) ->
    ok;
ensure_override_applied(OwnerNuggetId, TargetNuggetId, false) ->
    {error, {override_target_missing, OwnerNuggetId, TargetNuggetId}}.

replace_nugget_in_targets(Targets, TargetNuggetId, ReplacementNuggetId, Motherlode) ->
    MainTree0 = maps:get(main, Targets),
    Auxiliaries0 = maps:get(auxiliaries, Targets, []),
    maybe
        {ok, MainTree1, MainApplied} ?= maybe_replace_tree(
            MainTree0,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode
        ),
        {ok, Auxiliaries1, AuxApplied} ?= replace_nugget_in_auxiliaries(
            Auxiliaries0,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode,
            [],
            false
        ),
        {ok, #{main => MainTree1, auxiliaries => Auxiliaries1}, MainApplied orelse AuxApplied}
    else
        {error, _} = Error ->
            Error
    end.

maybe_replace_tree(Tree, TargetNuggetId, ReplacementNuggetId, Motherlode) ->
    case tree_contains_nugget(Tree, TargetNuggetId) of
        false ->
            {ok, Tree, false};
        true ->
            case smelterl_validate:validate_replacement(
                ReplacementNuggetId,
                TargetNuggetId,
                Tree,
                Motherlode
            ) of
                ok ->
                    case replace_nugget_in_tree(
                        Tree,
                        TargetNuggetId,
                        ReplacementNuggetId,
                        Motherlode
                    ) of
                        {ok, UpdatedTree} ->
                            {ok, UpdatedTree, true};
                        {error, Reason} ->
                            {error, {validation_failed, Reason}}
                    end;
                {error, Reason} ->
                    {error, {validation_failed, Reason}}
            end
    end.

replace_nugget_in_auxiliaries(
    [],
    _TargetNuggetId,
    _ReplacementNuggetId,
    _Motherlode,
    Acc,
    AnyApplied
) ->
    {ok, lists:reverse(Acc), AnyApplied};
replace_nugget_in_auxiliaries(
    [Auxiliary0 | Rest],
    TargetNuggetId,
    ReplacementNuggetId,
    Motherlode,
    Acc,
    AnyApplied0
) ->
    Tree0 = maps:get(tree, Auxiliary0),
    SpecificTree0 = maps:get(specific_tree, Auxiliary0),
    maybe
        {ok, Tree1, TreeApplied} ?= maybe_replace_tree(
            Tree0,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode
        ),
        {ok, SpecificTree1, _SpecificApplied} ?= maybe_replace_tree(
            SpecificTree0,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode
        ),
        RootNugget1 =
            case maps:get(root_nugget, Auxiliary0) of
                TargetNuggetId -> ReplacementNuggetId;
                RootNugget -> RootNugget
            end,
        Auxiliary1 = Auxiliary0#{
            root_nugget := RootNugget1,
            specific_tree := SpecificTree1,
            tree := Tree1
        },
        replace_nugget_in_auxiliaries(
            Rest,
            TargetNuggetId,
            ReplacementNuggetId,
            Motherlode,
            [Auxiliary1 | Acc],
            AnyApplied0 orelse TreeApplied
        )
    else
        {error, _} = Error ->
            Error
    end.

replace_nugget_in_tree(Tree, TargetNuggetId, ReplacementNuggetId, Motherlode) ->
    Edges0 = maps:get(edges, Tree),
    AvailableNodes =
        maps:remove(
            TargetNuggetId,
            maps:from_list([{NodeId, true} || NodeId <- maps:keys(Edges0)])
        ),
    maybe
        {ok, ReplacementDeps} ?= replacement_dependency_ids(
            ReplacementNuggetId,
            maps:get(
                depends_on,
                lookup_nugget(ReplacementNuggetId, Motherlode),
                []
            ),
            AvailableNodes
        ),
        Edges1 = maps:remove(TargetNuggetId, Edges0),
        Edges2 = rewrite_dependencies(
            maps:to_list(Edges1),
            TargetNuggetId,
            ReplacementNuggetId,
            #{}
        ),
        Root =
            case maps:get(root, Tree) of
                TargetNuggetId -> ReplacementNuggetId;
                OtherRoot -> OtherRoot
            end,
        {ok,
            #{
                root => Root,
                edges => maps:put(ReplacementNuggetId, ReplacementDeps, Edges2)
            }}
    else
        {error, _} = Error ->
            Error
    end.

replacement_dependency_ids(_ReplacementNuggetId, [], _AvailableNodes) ->
    {ok, []};
replacement_dependency_ids(ReplacementNuggetId, DependsOn, AvailableNodes)
  when is_list(DependsOn) ->
    replacement_dependency_ids(
        ReplacementNuggetId,
        DependsOn,
        AvailableNodes,
        []
    );
replacement_dependency_ids(ReplacementNuggetId, DependsOn, _AvailableNodes) ->
    {error, {invalid_dependency_constraints, ReplacementNuggetId, DependsOn}}.

replacement_dependency_ids(_ReplacementNuggetId, [], _AvailableNodes, Acc) ->
    {ok, lists:reverse(Acc)};
replacement_dependency_ids(
    ReplacementNuggetId,
    [Constraint | Rest],
    AvailableNodes,
    Acc
) ->
    case replacement_constraint_ids(
        ReplacementNuggetId,
        Constraint,
        AvailableNodes
    ) of
        {ok, DependencyIds} ->
            replacement_dependency_ids(
                ReplacementNuggetId,
                Rest,
                AvailableNodes,
                lists:reverse(DependencyIds) ++ Acc
            );
        {error, _} = Error ->
            Error
    end.

replacement_constraint_ids(
    ReplacementNuggetId,
    {required, nugget, Spec},
    AvailableNodes
) ->
    required_dependency(ReplacementNuggetId, Spec, required, AvailableNodes);
replacement_constraint_ids(
    ReplacementNuggetId,
    {optional, nugget, Spec},
    AvailableNodes
) ->
    optional_dependency(ReplacementNuggetId, Spec, AvailableNodes);
replacement_constraint_ids(
    ReplacementNuggetId,
    {one_of, nugget, Specs},
    AvailableNodes
)
  when is_list(Specs) ->
    multi_dependencies(ReplacementNuggetId, Specs, one_of, AvailableNodes);
replacement_constraint_ids(
    ReplacementNuggetId,
    {any_of, nugget, Specs},
    AvailableNodes
)
  when is_list(Specs) ->
    multi_dependencies(ReplacementNuggetId, Specs, any_of, AvailableNodes);
replacement_constraint_ids(
    _ReplacementNuggetId,
    {conflicts_with, nugget, _Spec},
    _AvailableNodes
) ->
    {ok, []};
replacement_constraint_ids(
    _ReplacementNuggetId,
    {_Type, category, _Spec},
    _AvailableNodes
) ->
    {ok, []};
replacement_constraint_ids(
    _ReplacementNuggetId,
    {_Type, capability, _Spec},
    _AvailableNodes
) ->
    {ok, []};
replacement_constraint_ids(ReplacementNuggetId, Constraint, _AvailableNodes) ->
    {error, {invalid_dependency_constraint, ReplacementNuggetId, Constraint}}.

required_dependency(ReplacementNuggetId, Spec, ConstraintType, AvailableNodes) ->
    case dependency_id(Spec) of
        {ok, DependencyId} ->
            case maps:is_key(DependencyId, AvailableNodes) of
                true ->
                    {ok, [DependencyId]};
                false ->
                    {error,
                        {missing_nugget_dependency,
                            ReplacementNuggetId,
                            DependencyId,
                            ConstraintType}}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, ReplacementNuggetId, Spec}}
    end.

optional_dependency(ReplacementNuggetId, Spec, AvailableNodes) ->
    case dependency_id(Spec) of
        {ok, DependencyId} ->
            case maps:is_key(DependencyId, AvailableNodes) of
                true ->
                    {ok, [DependencyId]};
                false ->
                    {ok, []}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, ReplacementNuggetId, Spec}}
    end.

multi_dependencies(ReplacementNuggetId, Specs, ConstraintType, AvailableNodes) ->
    case dependency_ids(Specs, []) of
        {ok, DependencyIds} ->
            PresentIds = [
                DependencyId
             || DependencyId <- DependencyIds,
                maps:is_key(DependencyId, AvailableNodes)
            ],
            case PresentIds of
                [] ->
                    {error,
                        {missing_nugget_dependency,
                            ReplacementNuggetId,
                            hd(DependencyIds),
                            ConstraintType}};
                _ ->
                    {ok, PresentIds}
            end;
        {error, _} ->
            {error, {invalid_dependency_constraint, ReplacementNuggetId, Specs}}
    end.

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

rewrite_dependencies([], _TargetNuggetId, _ReplacementNuggetId, Acc) ->
    Acc;
rewrite_dependencies(
    [{NodeId, Dependencies0} | Rest],
    TargetNuggetId,
    ReplacementNuggetId,
    Acc
) ->
    Dependencies = dedupe_keep_first([
        case DependencyId of
            TargetNuggetId -> ReplacementNuggetId;
            _Other -> DependencyId
        end
     || DependencyId <- Dependencies0
    ]),
    rewrite_dependencies(
        Rest,
        TargetNuggetId,
        ReplacementNuggetId,
        maps:put(NodeId, Dependencies, Acc)
    ).

config_target_ids(_OwnerNuggetId, main, _Targets) ->
    {ok, [main]};
config_target_ids(_OwnerNuggetId, all, Targets) ->
    {ok, target_ids(Targets)};
config_target_ids(OwnerNuggetId, Scope, Targets) ->
    case lists:member(Scope, auxiliary_ids(maps:get(auxiliaries, Targets, []))) of
        true ->
            {ok, [Scope]};
        false ->
            {error, {unknown_config_override_scope, OwnerNuggetId, Scope}}
    end.

apply_config_override_to_targets([], _OwnerNuggetId, _ConfigKey, _ConfigValue, _Targets, Views) ->
    {ok, Views};
apply_config_override_to_targets(
    [TargetId | Rest],
    OwnerNuggetId,
    ConfigKey,
    ConfigValue,
    Targets,
    Views0
) ->
    TargetTree = target_tree(Targets, TargetId),
    TargetMotherlode0 = maps:get(TargetId, Views0),
    case config_declarers(ConfigKey, TargetTree, TargetMotherlode0) of
        {error, export_conflict} ->
            {error, {config_override_targets_export, TargetId, ConfigKey}};
        {error, missing_key} ->
            {error, {config_override_missing_key, TargetId, ConfigKey}};
        {ok, DeclaringNuggets} ->
            TargetMotherlode1 = update_config_entries(
                DeclaringNuggets,
                ConfigKey,
                ConfigValue,
                OwnerNuggetId,
                TargetMotherlode0
            ),
            apply_config_override_to_targets(
                Rest,
                OwnerNuggetId,
                ConfigKey,
                ConfigValue,
                Targets,
                maps:put(TargetId, TargetMotherlode1, Views0)
            )
    end.

config_declarers(ConfigKey, TargetTree, TargetMotherlode) ->
    config_declarers(
        ConfigKey,
        maps:keys(maps:get(edges, TargetTree)),
        TargetMotherlode,
        [],
        false
    ).

config_declarers(_ConfigKey, [], _TargetMotherlode, Declarers, true) ->
    case Declarers of
        [] ->
            {error, export_conflict};
        _ ->
            {error, export_conflict}
    end;
config_declarers(_ConfigKey, [], _TargetMotherlode, [], false) ->
    {error, missing_key};
config_declarers(_ConfigKey, [], _TargetMotherlode, Declarers, false) ->
    {ok, lists:reverse(Declarers)};
config_declarers(ConfigKey, [NuggetId | Rest], TargetMotherlode, Declarers, ExportSeen0) ->
    Nugget = lookup_nugget(NuggetId, TargetMotherlode),
    ConfigEntries = maps:get(config, Nugget, []),
    ExportEntries = maps:get(exports, Nugget, []),
    HasConfig = lists:any(
        fun({Key, _Value, _Origin}) -> Key =:= ConfigKey end,
        ConfigEntries
    ),
    HasExport = lists:any(
        fun({Key, _Value, _Origin}) -> Key =:= ConfigKey end,
        ExportEntries
    ),
    Declarers1 =
        case HasConfig of
            true -> [NuggetId | Declarers];
            false -> Declarers
        end,
    config_declarers(
        ConfigKey,
        Rest,
        TargetMotherlode,
        Declarers1,
        ExportSeen0 orelse HasExport
    ).

update_config_entries([], _ConfigKey, _ConfigValue, _OwnerNuggetId, TargetMotherlode) ->
    TargetMotherlode;
update_config_entries(
    [NuggetId | Rest],
    ConfigKey,
    ConfigValue,
    OwnerNuggetId,
    TargetMotherlode0
) ->
    Nuggets0 = maps:get(nuggets, TargetMotherlode0),
    Nugget0 = maps:get(NuggetId, Nuggets0),
    Nugget1 = Nugget0#{
        config := [
            case Entry of
                {ConfigKey, _OldValue, _OldOrigin} ->
                    {ConfigKey, ConfigValue, OwnerNuggetId};
                _Other ->
                    Entry
            end
         || Entry <- maps:get(config, Nugget0, [])
        ]
    },
    TargetMotherlode1 = TargetMotherlode0#{
        nuggets := maps:put(NuggetId, Nugget1, Nuggets0)
    },
    update_config_entries(
        Rest,
        ConfigKey,
        ConfigValue,
        OwnerNuggetId,
        TargetMotherlode1
    ).

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

revalidate_targets(Targets, Motherlode) ->
    case smelterl_validate:validate_targets(Targets, Motherlode) of
        ok ->
            ok;
        {error, Reason} ->
            {error, {validation_failed, Reason}}
    end.

topology_orders(Targets) ->
    MainTree = maps:get(main, Targets),
    Auxiliaries = maps:get(auxiliaries, Targets, []),
    maybe
        {ok, MainOrder} ?= topology_order(main, MainTree),
        {ok, AuxiliaryOrders} ?= auxiliary_topology_orders(Auxiliaries, #{}),
        {ok, maps:put(main, MainOrder, AuxiliaryOrders)}
    else
        {error, _} = Error ->
            Error
    end.

auxiliary_topology_orders([], Orders) ->
    {ok, Orders};
auxiliary_topology_orders([Auxiliary | Rest], Orders0) ->
    AuxiliaryId = maps:get(id, Auxiliary),
    maybe
        {ok, Order} ?= topology_order(AuxiliaryId, maps:get(tree, Auxiliary)),
        auxiliary_topology_orders(Rest, maps:put(AuxiliaryId, Order, Orders0))
    else
        {error, _} = Error ->
            Error
    end.

topology_order(TargetId, Tree) ->
    case smelterl_topology:topology_order(Tree) of
        {ok, Order} ->
            {ok, Order};
        {error, Reason} ->
            {error, {topology_error, {TargetId, Reason}}}
    end.

initial_target_views(Targets, Motherlode) ->
    maps:from_list([{TargetId, Motherlode} || TargetId <- target_ids(Targets)]).

target_ids(Targets) ->
    [main] ++ auxiliary_ids(maps:get(auxiliaries, Targets, [])).

auxiliary_ids(Auxiliaries) ->
    [maps:get(id, Auxiliary) || Auxiliary <- Auxiliaries].

target_tree(Targets, main) ->
    maps:get(main, Targets);
target_tree(Targets, TargetId) ->
    auxiliary_tree(TargetId, maps:get(auxiliaries, Targets, [])).

auxiliary_tree(TargetId, [Auxiliary | Rest]) ->
    case maps:get(id, Auxiliary) of
        TargetId ->
            maps:get(tree, Auxiliary);
        _OtherId ->
            auxiliary_tree(TargetId, Rest)
    end.

tree_contains_nugget(Tree, NuggetId) ->
    maps:is_key(NuggetId, maps:get(edges, Tree)).

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode)).

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
