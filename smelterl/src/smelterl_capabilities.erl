%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_capabilities).
-moduledoc """
Discover plan-stage firmware capabilities and SDK output declarations.

This module consumes the overridden target trees produced earlier in the plan
pipeline and derives the metadata needed later for context and manifest
generation: firmware variants, variant-to-nugget declarations, selectable
firmware outputs, merged firmware parameters, and target-local `sdk_outputs`.
""".


%=== EXPORTS ===================================================================

-export([discover/3]).


%=== API FUNCTIONS =============================================================

-doc """
Derive firmware capabilities from the overridden target set.

The returned map includes main-target firmware capabilities and target-local
SDK output declarations for the main target and every auxiliary target.
""".
-spec discover(
    smelterl:target_trees(),
    smelterl:topology_orders(),
    smelterl:target_motherlodes()
) ->
    {ok, smelterl:firmware_capabilities()} | {error, term()}.
discover(Targets, TopologyOrders, TargetMotherlodes) ->
    TargetIds = [main] ++ [maps:get(id, Auxiliary) || Auxiliary <- maps:get(auxiliaries, Targets, [])],
    MainOrder = maps:get(main, TopologyOrders),
    MainMotherlode = maps:get(main, TargetMotherlodes),
    maybe
        {ok, FirmwareVariants, VariantNuggets} ?= discover_variants(
            MainOrder,
            MainMotherlode
        ),
        ok ?= validate_bootflow_coverage(
            FirmwareVariants,
            MainOrder,
            MainMotherlode
        ),
        {ok, SelectableOutputs} ?= discover_selectable_outputs(
            MainOrder,
            MainMotherlode
        ),
        {ok, FirmwareParameters} ?= discover_firmware_parameters(
            MainOrder,
            MainMotherlode
        ),
        {ok, SdkOutputsByTarget} ?= discover_sdk_outputs(
            TargetIds,
            TopologyOrders,
            TargetMotherlodes
        ),
        {ok,
            #{
                firmware_variants => FirmwareVariants,
                variant_nuggets => VariantNuggets,
                selectable_outputs => SelectableOutputs,
                firmware_parameters => FirmwareParameters,
                sdk_outputs_by_target => SdkOutputsByTarget
            }}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

discover_variants(MainOrder, Motherlode) ->
    maybe
        {ok, Variants0, VariantNuggets0, SeenVariants} ?= discover_variants(
            MainOrder,
            Motherlode,
            [],
            #{},
            #{}
        ),
        {ok, Variants1, VariantNuggets1} = ensure_plain_variant(
            Variants0,
            VariantNuggets0,
            SeenVariants
        ),
        {ok, Variants1, VariantNuggets1}
    else
        {error, _} = Error ->
            Error
    end.

discover_variants([], _Motherlode, Variants, VariantNuggets, SeenVariants) ->
    {ok, Variants, VariantNuggets, SeenVariants};
discover_variants([NuggetId | Rest], Motherlode, Variants0, VariantNuggets0, SeenVariants0) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, NuggetVariants} ?= parse_firmware_variants(
            NuggetId,
            maps:get(firmware_variant, Nugget, undefined)
        ),
        {Variants1, VariantNuggets1, SeenVariants1} = add_declared_variants(
            NuggetId,
            NuggetVariants,
            Variants0,
            VariantNuggets0,
            SeenVariants0
        ),
        discover_variants(
            Rest,
            Motherlode,
            Variants1,
            VariantNuggets1,
            SeenVariants1
        )
    else
        {error, _} = Error ->
            Error
    end.

parse_firmware_variants(_NuggetId, undefined) ->
    {ok, []};
parse_firmware_variants(NuggetId, Variants) when is_list(Variants) ->
    parse_firmware_variants(NuggetId, Variants, #{}, []);
parse_firmware_variants(NuggetId, Value) ->
    {error, {invalid_firmware_variant_metadata, NuggetId, Value}}.

parse_firmware_variants(_NuggetId, [], _Seen, Acc) ->
    {ok, lists:reverse(Acc)};
parse_firmware_variants(NuggetId, [Variant | Rest], Seen, Acc) when is_atom(Variant) ->
    case maps:is_key(Variant, Seen) of
        true ->
            {error, {duplicate_firmware_variant, NuggetId, Variant}};
        false ->
            parse_firmware_variants(
                NuggetId,
                Rest,
                maps:put(Variant, true, Seen),
                [Variant | Acc]
            )
    end;
parse_firmware_variants(NuggetId, Invalid, _Seen, _Acc) ->
    {error, {invalid_firmware_variant_metadata, NuggetId, Invalid}}.

ensure_plain_variant(Variants, VariantNuggets, SeenVariants) ->
    case maps:is_key(plain, SeenVariants) of
        true ->
            {ok, Variants, ensure_variant_nugget_keys(Variants, VariantNuggets)};
        false ->
            {ok, [plain | Variants], maps:put(plain, [], VariantNuggets)}
    end.

ensure_variant_nugget_keys([], VariantNuggets) ->
    VariantNuggets;
ensure_variant_nugget_keys([Variant | Rest], VariantNuggets0) ->
    VariantNuggets1 =
        case maps:is_key(Variant, VariantNuggets0) of
            true -> VariantNuggets0;
            false -> maps:put(Variant, [], VariantNuggets0)
        end,
    ensure_variant_nugget_keys(Rest, VariantNuggets1).

add_declared_variants(_NuggetId, [], Variants, VariantNuggets, SeenVariants) ->
    {Variants, VariantNuggets, SeenVariants};
add_declared_variants(
    NuggetId,
    [Variant | Rest],
    Variants0,
    VariantNuggets0,
    SeenVariants0
) ->
    {Variants1, SeenVariants1} =
        case maps:is_key(Variant, SeenVariants0) of
            true ->
                {Variants0, SeenVariants0};
            false ->
                {Variants0 ++ [Variant], maps:put(Variant, true, SeenVariants0)}
        end,
    DeclaringNuggets0 = maps:get(Variant, VariantNuggets0, []),
    VariantNuggets1 = maps:put(
        Variant,
        DeclaringNuggets0 ++ [NuggetId],
        VariantNuggets0
    ),
    add_declared_variants(
        NuggetId,
        Rest,
        Variants1,
        VariantNuggets1,
        SeenVariants1
    ).

validate_bootflow_coverage([], _MainOrder, _Motherlode) ->
    ok;
validate_bootflow_coverage([Variant | Rest], MainOrder, Motherlode) ->
    Bootflows = bootflows_for_variant(Variant, MainOrder, Motherlode),
    case Bootflows of
        [_BootflowId] ->
            validate_bootflow_coverage(Rest, MainOrder, Motherlode);
        _ ->
            {error, {bootflow_variant_coverage, Variant, Bootflows}}
    end.

bootflows_for_variant(Variant, MainOrder, Motherlode) ->
    [
        NuggetId
     || NuggetId <- MainOrder,
        nugget_category(NuggetId, Motherlode) =:= bootflow,
        nugget_participates_in_variant(
            lookup_nugget(NuggetId, Motherlode),
            Variant
        )
    ].

nugget_participates_in_variant(Nugget, Variant) ->
    case maps:get(firmware_variant, Nugget, undefined) of
        undefined ->
            true;
        Variants when is_list(Variants) ->
            lists:member(Variant, Variants);
        _Other ->
            false
    end.

discover_selectable_outputs(MainOrder, Motherlode) ->
    discover_selectable_outputs(MainOrder, Motherlode, #{}, []).

discover_selectable_outputs([], _Motherlode, _SeenOutputs, Acc) ->
    {ok, lists:reverse(Acc)};
discover_selectable_outputs([NuggetId | Rest], Motherlode, SeenOutputs0, Acc0) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, Outputs} ?= parse_firmware_outputs(
            NuggetId,
            maps:get(firmware_outputs, Nugget, undefined)
        ),
        {ok, SeenOutputs1, Acc1} ?= collect_selectable_outputs(
            NuggetId,
            Outputs,
            SeenOutputs0,
            Acc0
        ),
        discover_selectable_outputs(Rest, Motherlode, SeenOutputs1, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

collect_selectable_outputs(_NuggetId, [], SeenOutputs, Acc) ->
    {ok, SeenOutputs, Acc};
collect_selectable_outputs(NuggetId, [Output | Rest], SeenOutputs0, Acc0) ->
    OutputId = maps:get(id, Output),
    maybe
        ok ?= ensure_unique_firmware_output(
            OutputId,
            NuggetId,
            SeenOutputs0
        ),
        SeenOutputs1 = maps:put(OutputId, NuggetId, SeenOutputs0),
        Acc1 =
            case maps:get(selectable, Output) of
                true ->
                    [selectable_output_spec(Output) | Acc0];
                false ->
                    Acc0
            end,
        collect_selectable_outputs(NuggetId, Rest, SeenOutputs1, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

ensure_unique_firmware_output(OutputId, NuggetId, SeenOutputs) ->
    case maps:get(OutputId, SeenOutputs, undefined) of
        undefined ->
            ok;
        PreviousNugget ->
            {error,
                {duplicate_firmware_output,
                    OutputId,
                    PreviousNugget,
                    NuggetId}}
    end.

selectable_output_spec(Output) ->
    Spec0 = #{
        id => maps:get(id, Output),
        default => maps:get(default, Output)
    },
    maybe_put(
        description,
        maps:get(description, Output, undefined),
        maybe_put(name, maps:get(name, Output, undefined), Spec0)
    ).

parse_firmware_outputs(_NuggetId, undefined) ->
    {ok, []};
parse_firmware_outputs(NuggetId, Outputs) when is_list(Outputs) ->
    parse_firmware_outputs(NuggetId, Outputs, []);
parse_firmware_outputs(NuggetId, Value) ->
    {error, {invalid_firmware_outputs_metadata, NuggetId, Value}}.

parse_firmware_outputs(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
parse_firmware_outputs(NuggetId, [Output | Rest], Acc) ->
    maybe
        {ok, Parsed} ?= parse_firmware_output(NuggetId, Output),
        parse_firmware_outputs(NuggetId, Rest, [Parsed | Acc])
    else
        {error, _} = Error ->
            Error
    end;
parse_firmware_outputs(NuggetId, Value, _Acc) ->
    {error, {invalid_firmware_outputs_metadata, NuggetId, Value}}.

parse_firmware_output(NuggetId, {OutputId, Fields})
  when is_atom(OutputId), is_list(Fields) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Fields,
        #{id => OutputId, selectable => false, default => true}
    );
parse_firmware_output(NuggetId, Output) ->
    {error, {invalid_firmware_output, NuggetId, Output}}.

parse_firmware_output_fields(_NuggetId, _OutputId, [], Output) ->
    {ok, Output};
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{selectable, Selectable} | Rest],
    Output
)
  when is_boolean(Selectable) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{selectable := Selectable}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{default, Default} | Rest],
    Output
)
  when is_boolean(Default) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{default := Default}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{display_name, Name} | Rest],
    Output
)
  when is_binary(Name) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{name => Name}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{description, Description} | Rest],
    Output
)
  when is_binary(Description) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{description => Description}
    );
parse_firmware_output_fields(NuggetId, OutputId, [Field | _Rest], _Output) ->
    {error, {invalid_firmware_output_field, NuggetId, OutputId, Field}}.

discover_firmware_parameters(MainOrder, Motherlode) ->
    maybe
        {ok, ParameterIds, ParametersById} ?= discover_firmware_parameters(
            MainOrder,
            Motherlode,
            [],
            #{}
        ),
        {ok, [finalize_firmware_parameter(maps:get(Id, ParametersById)) || Id <- ParameterIds]}
    else
        {error, _} = Error ->
            Error
    end.

discover_firmware_parameters([], _Motherlode, ParameterIds, ParametersById) ->
    {ok, ParameterIds, ParametersById};
discover_firmware_parameters(
    [NuggetId | Rest],
    Motherlode,
    ParameterIds0,
    ParametersById0
) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, Parameters} ?= parse_firmware_parameters(
            NuggetId,
            maps:get(firmware_parameters, Nugget, undefined)
        ),
        {ok, ParameterIds1, ParametersById1} ?= merge_firmware_parameters(
            NuggetId,
            Parameters,
            ParameterIds0,
            ParametersById0
        ),
        discover_firmware_parameters(
            Rest,
            Motherlode,
            ParameterIds1,
            ParametersById1
        )
    else
        {error, _} = Error ->
            Error
    end.

parse_firmware_parameters(_NuggetId, undefined) ->
    {ok, []};
parse_firmware_parameters(NuggetId, Parameters) when is_list(Parameters) ->
    parse_firmware_parameters(NuggetId, Parameters, []);
parse_firmware_parameters(NuggetId, Value) ->
    {error, {invalid_firmware_parameters_metadata, NuggetId, Value}}.

parse_firmware_parameters(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
parse_firmware_parameters(NuggetId, [Parameter | Rest], Acc) ->
    maybe
        {ok, Parsed} ?= parse_firmware_parameter(NuggetId, Parameter),
        parse_firmware_parameters(NuggetId, Rest, [Parsed | Acc])
    else
        {error, _} = Error ->
            Error
    end;
parse_firmware_parameters(NuggetId, Value, _Acc) ->
    {error, {invalid_firmware_parameters_metadata, NuggetId, Value}}.

parse_firmware_parameter(NuggetId, {ParamId, Fields})
  when is_atom(ParamId), is_list(Fields) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Fields,
        #{id => ParamId, required => false, owner => NuggetId}
    );
parse_firmware_parameter(NuggetId, Parameter) ->
    {error, {invalid_firmware_parameter, NuggetId, Parameter}}.

parse_firmware_parameter_fields(NuggetId, ParamId, [], Parameter) ->
    maybe
        Type ?= maps:get(type, Parameter, undefined),
        ok ?= validate_firmware_parameter_type(NuggetId, ParamId, Type),
        ok ?= validate_firmware_parameter_default(
            NuggetId,
            ParamId,
            Type,
            maps:get(default, Parameter, undefined)
        ),
        {ok, Parameter}
    else
        undefined ->
            {error, {missing_firmware_parameter_type, NuggetId, ParamId}};
        {error, _} = Error ->
            Error
    end;
parse_firmware_parameter_fields(
    NuggetId,
    ParamId,
    [{type, Type} | Rest],
    Parameter
) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Rest,
        Parameter#{type => Type}
    );
parse_firmware_parameter_fields(
    NuggetId,
    ParamId,
    [{name, Name} | Rest],
    Parameter
)
  when is_binary(Name) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Rest,
        Parameter#{name => Name}
    );
parse_firmware_parameter_fields(
    NuggetId,
    ParamId,
    [{description, Description} | Rest],
    Parameter
)
  when is_binary(Description) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Rest,
        Parameter#{description => Description}
    );
parse_firmware_parameter_fields(
    NuggetId,
    ParamId,
    [{required, Required} | Rest],
    Parameter
)
  when is_boolean(Required) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Rest,
        Parameter#{required := Required}
    );
parse_firmware_parameter_fields(
    NuggetId,
    ParamId,
    [{default, Default} | Rest],
    Parameter
) ->
    parse_firmware_parameter_fields(
        NuggetId,
        ParamId,
        Rest,
        Parameter#{default => Default}
    );
parse_firmware_parameter_fields(NuggetId, ParamId, [Field | _Rest], _Parameter) ->
    {error, {invalid_firmware_parameter_field, NuggetId, ParamId, Field}}.

validate_firmware_parameter_type(_NuggetId, _ParamId, string) ->
    ok;
validate_firmware_parameter_type(_NuggetId, _ParamId, integer) ->
    ok;
validate_firmware_parameter_type(_NuggetId, _ParamId, boolean) ->
    ok;
validate_firmware_parameter_type(NuggetId, ParamId, Type) ->
    {error, {invalid_firmware_parameter_type, NuggetId, ParamId, Type}}.

validate_firmware_parameter_default(_NuggetId, _ParamId, _Type, undefined) ->
    ok;
validate_firmware_parameter_default(_NuggetId, _ParamId, string, Default)
  when is_binary(Default) ->
    ok;
validate_firmware_parameter_default(_NuggetId, _ParamId, integer, Default)
  when is_integer(Default) ->
    ok;
validate_firmware_parameter_default(_NuggetId, _ParamId, boolean, true) ->
    ok;
validate_firmware_parameter_default(_NuggetId, _ParamId, boolean, false) ->
    ok;
validate_firmware_parameter_default(NuggetId, ParamId, Type, Default) ->
    {error, {invalid_firmware_parameter_default, NuggetId, ParamId, Type, Default}}.

merge_firmware_parameters(_NuggetId, [], ParameterIds, ParametersById) ->
    {ok, ParameterIds, ParametersById};
merge_firmware_parameters(
    NuggetId,
    [Parameter | Rest],
    ParameterIds0,
    ParametersById0
) ->
    ParamId = maps:get(id, Parameter),
    Existing = maps:get(ParamId, ParametersById0, undefined),
    maybe
        {ok, ParameterIds1, ParametersById1} ?= merge_firmware_parameter(
            NuggetId,
            Parameter,
            Existing,
            ParameterIds0,
            ParametersById0
        ),
        merge_firmware_parameters(
            NuggetId,
            Rest,
            ParameterIds1,
            ParametersById1
        )
    else
        {error, _} = Error ->
            Error
    end.

merge_firmware_parameter(
    _NuggetId,
    Parameter,
    undefined,
    ParameterIds,
    ParametersById
) ->
    ParamId = maps:get(id, Parameter),
    {ok, ParameterIds ++ [ParamId], maps:put(ParamId, initialize_parameter_state(Parameter), ParametersById)};
merge_firmware_parameter(
    NuggetId,
    Parameter,
    Existing,
    ParameterIds,
    ParametersById
) ->
    maybe
        ok ?= ensure_parameter_type_matches(Existing, Parameter),
        ok ?= ensure_parameter_default_matches(Existing, Parameter),
        Merged = merge_parameter_state(Existing, Parameter, NuggetId),
        {ok, ParameterIds, maps:put(maps:get(id, Parameter), Merged, ParametersById)}
    else
        {error, _} = Error ->
            Error
    end.

initialize_parameter_state(Parameter) ->
    maybe_put(
        description,
        maps:get(description, Parameter, undefined),
        maybe_put(
            name,
            maps:get(name, Parameter, undefined),
            maybe_put(
                default_owner,
                case maps:is_key(default, Parameter) of
                    true -> maps:get(owner, Parameter);
                    false -> undefined
                end,
                maybe_put(
                    default,
                    maps:get(default, Parameter, undefined),
                    Parameter#{
                        type_owner => maps:get(owner, Parameter)
                    }
                )
            )
        )
    ).

ensure_parameter_type_matches(Existing, Parameter) ->
    ExistingType = maps:get(type, Existing),
    NewType = maps:get(type, Parameter),
    case ExistingType =:= NewType of
        true ->
            ok;
        false ->
            {error,
                {parameter_type_conflict,
                    maps:get(id, Existing),
                    maps:get(type_owner, Existing),
                    ExistingType,
                    maps:get(owner, Parameter),
                    NewType}}
    end.

ensure_parameter_default_matches(Existing, Parameter) ->
    case {maps:is_key(default, Existing), maps:is_key(default, Parameter)} of
        {true, true} ->
            ExistingDefault = maps:get(default, Existing),
            NewDefault = maps:get(default, Parameter),
            case ExistingDefault =:= NewDefault of
                true ->
                    ok;
                false ->
                    {error,
                        {parameter_default_conflict,
                            maps:get(id, Existing),
                            maps:get(default_owner, Existing),
                            ExistingDefault,
                            maps:get(owner, Parameter),
                            NewDefault}}
            end;
        _ ->
            ok
    end.

merge_parameter_state(Existing, Parameter, NuggetId) ->
    Required =
        maps:get(required, Existing, false) orelse maps:get(required, Parameter, false),
    State0 = Existing#{required := Required},
    State1 =
        case maps:is_key(default, State0) of
            true ->
                State0;
            false ->
                maybe_put(
                    default_owner,
                    case maps:is_key(default, Parameter) of
                        true -> NuggetId;
                        false -> undefined
                    end,
                    maybe_put(default, maps:get(default, Parameter, undefined), State0)
                )
        end,
    State2 = merge_optional_binary_field(name, State1, maps:get(name, Parameter, undefined)),
    merge_optional_binary_field(
        description,
        State2,
        maps:get(description, Parameter, undefined)
    ).

merge_optional_binary_field(_Field, State, undefined) ->
    State;
merge_optional_binary_field(Field, State, <<>>) ->
    case maps:get(Field, State, undefined) of
        undefined -> State;
        _Value -> State
    end;
merge_optional_binary_field(Field, State, Value) ->
    case maps:get(Field, State, undefined) of
        undefined -> maps:put(Field, Value, State);
        <<>> -> maps:put(Field, Value, State);
        _Existing -> State
    end.

finalize_firmware_parameter(ParameterState) ->
    Base = #{
        id => maps:get(id, ParameterState),
        type => maps:get(type, ParameterState)
    },
    Base1 =
        case maps:get(required, ParameterState, false) of
            true -> Base#{required => true};
            false -> Base
        end,
    Base2 = maybe_put(name, maps:get(name, ParameterState, undefined), Base1),
    Base3 =
        maybe_put(
            description,
            maps:get(description, ParameterState, undefined),
            Base2
        ),
    maybe_put(default, maps:get(default, ParameterState, undefined), Base3).

discover_sdk_outputs(TargetIds, TopologyOrders, TargetMotherlodes) ->
    discover_sdk_outputs(TargetIds, TopologyOrders, TargetMotherlodes, #{}).

discover_sdk_outputs([], _TopologyOrders, _TargetMotherlodes, Acc) ->
    {ok, Acc};
discover_sdk_outputs([TargetId | Rest], TopologyOrders, TargetMotherlodes, Acc0) ->
    TopologyOrder = maps:get(TargetId, TopologyOrders),
    Motherlode = maps:get(TargetId, TargetMotherlodes),
    maybe
        {ok, TargetOutputs} ?= discover_target_sdk_outputs(
            TargetId,
            TopologyOrder,
            Motherlode
        ),
        discover_sdk_outputs(
            Rest,
            TopologyOrders,
            TargetMotherlodes,
            maps:put(TargetId, TargetOutputs, Acc0)
        )
    else
        {error, _} = Error ->
            Error
    end.

discover_target_sdk_outputs(TargetId, TopologyOrder, Motherlode) ->
    discover_target_sdk_outputs(TargetId, TopologyOrder, Motherlode, #{}, []).

discover_target_sdk_outputs(_TargetId, [], _Motherlode, _SeenOutputs, Acc) ->
    {ok, lists:reverse(Acc)};
discover_target_sdk_outputs(
    TargetId,
    [NuggetId | Rest],
    Motherlode,
    SeenOutputs0,
    Acc0
) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, Outputs} ?= parse_sdk_outputs(
            TargetId,
            NuggetId,
            maps:get(sdk_outputs, Nugget, undefined)
        ),
        {ok, SeenOutputs1, Acc1} ?= collect_sdk_outputs(
            TargetId,
            NuggetId,
            Outputs,
            SeenOutputs0,
            Acc0
        ),
        discover_target_sdk_outputs(
            TargetId,
            Rest,
            Motherlode,
            SeenOutputs1,
            Acc1
        )
    else
        {error, _} = Error ->
            Error
    end.

collect_sdk_outputs(_TargetId, _NuggetId, [], SeenOutputs, Acc) ->
    {ok, SeenOutputs, Acc};
collect_sdk_outputs(TargetId, NuggetId, [Output | Rest], SeenOutputs0, Acc0) ->
    OutputId = maps:get(id, Output),
    maybe
        ok ?= ensure_unique_sdk_output(
            TargetId,
            OutputId,
            NuggetId,
            SeenOutputs0
        ),
        SeenOutputs1 = maps:put(OutputId, NuggetId, SeenOutputs0),
        Acc1 = [Output#{nugget => NuggetId} | Acc0],
        collect_sdk_outputs(TargetId, NuggetId, Rest, SeenOutputs1, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

ensure_unique_sdk_output(TargetId, OutputId, NuggetId, SeenOutputs) ->
    case maps:get(OutputId, SeenOutputs, undefined) of
        undefined ->
            ok;
        PreviousNugget ->
            {error,
                {duplicate_sdk_output,
                    TargetId,
                    OutputId,
                    PreviousNugget,
                    NuggetId}}
    end.

parse_sdk_outputs(_TargetId, _NuggetId, undefined) ->
    {ok, []};
parse_sdk_outputs(TargetId, NuggetId, Outputs) when is_list(Outputs) ->
    parse_sdk_outputs(TargetId, NuggetId, Outputs, []);
parse_sdk_outputs(TargetId, NuggetId, Value) ->
    {error, {invalid_sdk_outputs_metadata, TargetId, NuggetId, Value}}.

parse_sdk_outputs(_TargetId, _NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
parse_sdk_outputs(TargetId, NuggetId, [Output | Rest], Acc) ->
    maybe
        {ok, Parsed} ?= parse_sdk_output(TargetId, NuggetId, Output),
        parse_sdk_outputs(TargetId, NuggetId, Rest, [Parsed | Acc])
    else
        {error, _} = Error ->
            Error
    end;
parse_sdk_outputs(TargetId, NuggetId, Value, _Acc) ->
    {error, {invalid_sdk_outputs_metadata, TargetId, NuggetId, Value}}.

parse_sdk_output(TargetId, NuggetId, {OutputId, Fields})
  when is_atom(OutputId), is_list(Fields) ->
    parse_sdk_output_fields(
        TargetId,
        NuggetId,
        OutputId,
        Fields,
        #{id => OutputId}
    );
parse_sdk_output(TargetId, NuggetId, Output) ->
    {error, {invalid_sdk_output, TargetId, NuggetId, Output}}.

parse_sdk_output_fields(_TargetId, _NuggetId, _OutputId, [], Output) ->
    {ok, Output};
parse_sdk_output_fields(
    TargetId,
    NuggetId,
    OutputId,
    [{display_name, Name} | Rest],
    Output
)
  when is_binary(Name) ->
    parse_sdk_output_fields(
        TargetId,
        NuggetId,
        OutputId,
        Rest,
        Output#{name => Name}
    );
parse_sdk_output_fields(
    TargetId,
    NuggetId,
    OutputId,
    [{description, Description} | Rest],
    Output
)
  when is_binary(Description) ->
    parse_sdk_output_fields(
        TargetId,
        NuggetId,
        OutputId,
        Rest,
        Output#{description => Description}
    );
parse_sdk_output_fields(TargetId, NuggetId, OutputId, [Field | _Rest], _Output) ->
    {error, {invalid_sdk_output_field, TargetId, NuggetId, OutputId, Field}}.

maybe_put(_Key, undefined, Map) ->
    Map;
maybe_put(_Key, <<>>, Map) ->
    Map;
maybe_put(Key, Value, Map) ->
    maps:put(Key, Value, Map).

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode)).

nugget_category(NuggetId, Motherlode) ->
    maps:get(category, lookup_nugget(NuggetId, Motherlode), undefined).
