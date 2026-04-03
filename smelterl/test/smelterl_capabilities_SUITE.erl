-module(smelterl_capabilities_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    discover_collects_capabilities_and_sdk_outputs/1,
    discover_rejects_duplicate_variant_in_one_nugget/1,
    discover_rejects_missing_bootflow_for_variant/1,
    discover_rejects_duplicate_firmware_output_ids/1,
    discover_rejects_firmware_parameter_type_conflicts/1,
    discover_rejects_firmware_parameter_default_conflicts/1,
    discover_rejects_duplicate_sdk_output_ids_within_target/1
]).

all() ->
    [
        discover_collects_capabilities_and_sdk_outputs,
        discover_rejects_duplicate_variant_in_one_nugget,
        discover_rejects_missing_bootflow_for_variant,
        discover_rejects_duplicate_firmware_output_ids,
        discover_rejects_firmware_parameter_type_conflicts,
        discover_rejects_firmware_parameter_default_conflicts,
        discover_rejects_duplicate_sdk_output_ids_within_target
    ].

discover_collects_capabilities_and_sdk_outputs(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain},
            {required, nugget, feature_secure},
            {required, nugget, bootflow_secure},
            {required, nugget, fwup_feature},
            {required, nugget, image_feature},
            {required, nugget, params_a},
            {required, nugget, params_b},
            {required, nugget, main_output_feature}
        ], [
            {auxiliary_products, [{aux_bundle, aux_root}]}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(feature_secure, feature, [], [
            {firmware_variant, [secure]}
        ]),
        nugget(bootflow_secure, bootflow, [], [
            {firmware_variant, [secure]},
            {firmware_outputs, [
                {signed_boot_image, [
                    {display_name, <<"Signed boot image">>},
                    {description, <<"Secure-boot artefact">>}
                ]}
            ]}
        ]),
        nugget(fwup_feature, feature, [], [
            {firmware_outputs, [
                {fwup_firmware, [
                    {selectable, true},
                    {display_name, <<"FWUP firmware">>},
                    {description, <<"OTA package">>}
                ]}
            ]}
        ]),
        nugget(image_feature, feature, [], [
            {firmware_outputs, [
                {image, [
                    {selectable, true},
                    {default, false},
                    {display_name, <<"Disk image">>},
                    {description, <<"Raw flash image">>}
                ]}
            ]}
        ]),
        nugget(params_a, feature, [], [
            {firmware_parameters, [
                {serial_number, [
                    {type, string},
                    {required, true},
                    {name, <<"Serial Number">>},
                    {description, <<"Device serial">>}
                ]},
                {factory_mode, [
                    {type, boolean},
                    {default, false},
                    {name, <<"Factory Mode">>}
                ]}
            ]}
        ]),
        nugget(params_b, feature, [], [
            {firmware_parameters, [
                {serial_number, [
                    {type, string},
                    {description, <<"Later description should not win">>}
                ]},
                {batch_id, [
                    {type, integer},
                    {default, 7},
                    {name, <<"Batch ID">>}
                ]}
            ]}
        ]),
        nugget(main_output_feature, feature, [], [
            {sdk_outputs, [
                {debug_symbols, [
                    {display_name, <<"Debug symbols">>},
                    {description, <<"Main-target symbol archive">>}
                ]}
            ]}
        ]),
        nugget(aux_root, feature, [
            {required, nugget, aux_payload}
        ], [
            {sdk_outputs, [
                {initramfs, [
                    {display_name, <<"Encrypted initramfs">>},
                    {description, <<"Auxiliary payload">>}
                ]}
            ]}
        ]),
        nugget(aux_payload, feature, [])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    {ok, Capabilities} = smelterl_capabilities:discover(
        Targets,
        TopologyOrders,
        TargetMotherlodes
    ),
    assert_equal(
        [plain, secure],
        maps:get(firmware_variants, Capabilities)
    ),
    assert_equal(
        #{plain => [bootflow_plain], secure => [feature_secure, bootflow_secure]},
        maps:get(variant_nuggets, Capabilities)
    ),
    assert_equal(
        [
            #{
                id => fwup_firmware,
                default => true,
                name => <<"FWUP firmware">>,
                description => <<"OTA package">>
            },
            #{
                id => image,
                default => false,
                name => <<"Disk image">>,
                description => <<"Raw flash image">>
            }
        ],
        maps:get(selectable_outputs, Capabilities)
    ),
    assert_equal(
        [
            #{
                id => serial_number,
                type => string,
                required => true,
                name => <<"Serial Number">>,
                description => <<"Device serial">>
            },
            #{
                id => factory_mode,
                type => boolean,
                name => <<"Factory Mode">>,
                default => false
            },
            #{
                id => batch_id,
                type => integer,
                name => <<"Batch ID">>,
                default => 7
            }
        ],
        maps:get(firmware_parameters, Capabilities)
    ),
    assert_equal(
        #{
            main => [
                #{
                    id => debug_symbols,
                    nugget => main_output_feature,
                    name => <<"Debug symbols">>,
                    description => <<"Main-target symbol archive">>
                }
            ],
            aux_bundle => [
                #{
                    id => initramfs,
                    nugget => aux_root,
                    name => <<"Encrypted initramfs">>,
                    description => <<"Auxiliary payload">>
                }
            ]
        },
        maps:get(sdk_outputs_by_target, Capabilities)
    ).

discover_rejects_duplicate_variant_in_one_nugget(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain, plain]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error, {duplicate_firmware_variant, bootflow_plain, plain}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

discover_rejects_missing_bootflow_for_variant(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain},
            {required, nugget, secure_feature}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(secure_feature, feature, [], [
            {firmware_variant, [secure]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error, {bootflow_variant_coverage, secure, []}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

discover_rejects_duplicate_firmware_output_ids(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain},
            {required, nugget, output_a},
            {required, nugget, output_b}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(output_a, feature, [], [
            {firmware_outputs, [{image, [{selectable, true}]}]}
        ]),
        nugget(output_b, feature, [], [
            {firmware_outputs, [{image, [{selectable, false}]}]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error, {duplicate_firmware_output, image, output_a, output_b}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

discover_rejects_firmware_parameter_type_conflicts(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain},
            {required, nugget, params_a},
            {required, nugget, params_b}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(params_a, feature, [], [
            {firmware_parameters, [{serial_number, [{type, string}]}]}
        ]),
        nugget(params_b, feature, [], [
            {firmware_parameters, [{serial_number, [{type, integer}]}]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error,
            {parameter_type_conflict,
                serial_number,
                params_a,
                string,
                params_b,
                integer}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

discover_rejects_firmware_parameter_default_conflicts(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain},
            {required, nugget, params_a},
            {required, nugget, params_b}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(params_a, feature, [], [
            {firmware_parameters, [{factory_mode, [{type, boolean}, {default, false}]}]}
        ]),
        nugget(params_b, feature, [], [
            {firmware_parameters, [{factory_mode, [{type, boolean}, {default, true}]}]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error,
            {parameter_default_conflict,
                factory_mode,
                params_a,
                false,
                params_b,
                true}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

discover_rejects_duplicate_sdk_output_ids_within_target(_Config) ->
    Motherlode = motherlode([
        nugget(product, feature, [
            {required, nugget, builder_core},
            {required, nugget, toolchain_core},
            {required, nugget, platform_core},
            {required, nugget, system_core},
            {required, nugget, bootflow_plain}
        ], [
            {auxiliary_products, [{aux_bundle, aux_root}]}
        ]),
        nugget(builder_core, builder, []),
        nugget(toolchain_core, toolchain, []),
        nugget(platform_core, platform, []),
        nugget(system_core, system, []),
        nugget(bootflow_plain, bootflow, [], [
            {firmware_variant, [plain]}
        ]),
        nugget(aux_root, feature, [
            {required, nugget, aux_payload}
        ], [
            {sdk_outputs, [{initramfs, []}]}
        ]),
        nugget(aux_payload, feature, [], [
            {sdk_outputs, [{initramfs, []}]}
        ])
    ]),
    {Targets, TopologyOrders, TargetMotherlodes} = planned_targets(product, Motherlode),
    assert_equal(
        {error,
            {duplicate_sdk_output,
                aux_bundle,
                initramfs,
                aux_payload,
                aux_root}},
        smelterl_capabilities:discover(Targets, TopologyOrders, TargetMotherlodes)
    ).

planned_targets(ProductId, Motherlode) ->
    {ok, Targets} = smelterl_tree:build_targets(ProductId, Motherlode),
    ok = smelterl_validate:validate_targets(Targets, Motherlode),
    {ok, TopologyOrders} = topology_orders(Targets),
    {ok, OverriddenTargets, OverriddenTopologies, TargetMotherlodes} =
        smelterl_overrides:apply_overrides(Targets, TopologyOrders, Motherlode),
    {OverriddenTargets, OverriddenTopologies, TargetMotherlodes}.

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
