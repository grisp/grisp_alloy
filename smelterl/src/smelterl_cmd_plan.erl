%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_cmd_plan).
-moduledoc """
`smelterl plan` command implementation.

This module exposes the command metadata consumed by `smelterl_cli` and owns
the current `plan` execution stub, including required-option validation and
motherlode loading error formatting.
""".

-behaviour(smelterl_command).

%=== EXPORTS ===================================================================

-export([actions/0]).
-export([help/1]).
-export([options_spec/1]).
-export([run/2]).


%=== BEHAVIOUR smelterl_command CALLBACKS ======================================

actions() ->
    [plan].

options_spec(plan) ->
    [
        #{name => product, long => "product", type => value},
        #{name => motherlode, long => "motherlode", type => value},
        #{name => output_plan, long => "output-plan", type => value},
        #{name => output_plan_env, long => "output-plan-env", type => value},
        #{name => extra_config, long => "extra-config", type => accum},
        #{name => log, long => "log", type => value},
        #{name => verbose, long => "verbose", type => flag},
        #{name => debug, long => "debug", type => flag}
    ].

help(plan) ->
    [
        "Usage: smelterl plan [OPTIONS]\n\n",
        "Required:\n",
        "  --product ID           Main product nugget identifier\n",
        "  --motherlode PATH      Staged nugget repository directory\n",
        "  --output-plan PATH     Output path for build_plan.term\n\n",
        "Optional:\n",
        "  --output-plan-env PATH Output path for build_plan.env\n",
        "  --extra-config K=V     Repeatable plan-time extra config\n",
        "  --log LEVEL            Logging level\n",
        "  --verbose              Enable verbose logging\n",
        "  --debug                Enable debug logging\n",
        "  --help, -h             Show this help text\n"
    ].

run(plan, Opts) ->
    case require_options(Opts) of
        ok ->
            run_plan(Opts);
        {error, Message} ->
            smelterl_log:error("~ts~n", [Message]),
            2
    end.


%=== INTERNAL FUNCTIONS ========================================================

run_plan(Opts) ->
    ProductId = list_to_atom(maps:get(product, Opts)),
    case smelterl_motherlode:load(maps:get(motherlode, Opts)) of
        {ok, Motherlode} ->
            case smelterl_tree:build_targets(ProductId, Motherlode) of
                {ok, Targets} ->
                    case smelterl_validate:validate_targets(Targets, Motherlode) of
                        ok ->
                            smelterl_log:error("plan execution not implemented yet.~n", []),
                            1;
                        {error, Reason} ->
                            smelterl_log:error("~ts~n", [format_validation_error(Reason)]),
                            1
                    end;
                {error, Reason} ->
                    smelterl_log:error("~ts~n", [format_tree_error(Reason)]),
                    1
            end;
        {error, Reason} ->
            smelterl_log:error("~ts~n", [format_load_error(Reason)]),
            1
    end.

require_options(Opts) ->
    case maps:get(product, Opts, undefined) of
        undefined ->
            {error, "plan requires --product."};
        [] ->
            {error, "plan requires --product."};
        _ ->
            case maps:get(motherlode, Opts, undefined) of
                undefined ->
                    {error, "plan requires --motherlode."};
                [] ->
                    {error, "plan requires --motherlode."};
                _ ->
                    case maps:get(output_plan, Opts, undefined) of
                        undefined ->
                            {error, "plan requires --output-plan."};
                        [] ->
                            {error, "plan requires --output-plan."};
                        _ ->
                            ok
                    end
            end
    end.

format_load_error({invalid_path, Path, Posix}) ->
    io_lib:format("plan: invalid motherlode path '~ts': ~tp", [Path, Posix]);
format_load_error({invalid_registry, RepoPath, Detail}) ->
    io_lib:format(
        "plan: invalid nugget registry in '~ts': ~ts",
        [RepoPath, format_detail(Detail)]
    );
format_load_error({missing_metadata, RepoPath, NuggetRelPath}) ->
    io_lib:format(
        "plan: nugget metadata '~ts' listed by '~ts/.nuggets' does not exist",
        [NuggetRelPath, RepoPath]
    );
format_load_error({invalid_metadata, RepoPath, NuggetRelPath, Detail}) ->
    io_lib:format(
        "plan: invalid nugget metadata '~ts/~ts': ~ts",
        [RepoPath, NuggetRelPath, format_detail(Detail)]
    );
format_load_error({duplicated_nugget_id, NuggetId, RepoPath1, RepoPath2}) ->
    io_lib:format(
        "plan: duplicated nugget id '~ts' in '~ts' and '~ts'",
        [atom_to_list(NuggetId), RepoPath1, RepoPath2]
    );
format_load_error({missing_file, RepoPath, NuggetRelPath, FileRelPath, Detail}) ->
    io_lib:format(
        "plan: missing referenced file '~ts' for '~ts/~ts': ~ts",
        [FileRelPath, RepoPath, NuggetRelPath, format_detail(Detail)]
    );
format_load_error(Reason) ->
    io_lib:format("plan: motherlode loading failed: ~tp", [Reason]).

format_detail({parse_error, FileError}) ->
    io_lib:format("~tp", [FileError]);
format_detail(Detail) when is_atom(Detail) ->
    atom_to_list(Detail);
format_detail(Detail) ->
    io_lib:format("~tp", [Detail]).

format_tree_error({product_not_found, ProductId}) ->
    io_lib:format(
        "plan: product '~ts' not found in motherlode",
        [atom_to_list(ProductId)]
    );
format_tree_error({auxiliary_root_not_found, AuxId, RootNugget}) ->
    io_lib:format(
        "plan: auxiliary target '~ts' references missing root nugget '~ts'",
        [atom_to_list(AuxId), atom_to_list(RootNugget)]
    );
format_tree_error({circular_dependency, Cycle}) ->
    io_lib:format(
        "plan: circular dependency detected: ~ts",
        [string:join([atom_to_list(Id) || Id <- Cycle], " -> ")]
    );
format_tree_error({dependency_not_found, RequesterId, MissingId, Constraint}) ->
    io_lib:format(
        "plan: nugget '~ts' requires missing dependency '~ts' (~ts)",
        [atom_to_list(RequesterId), atom_to_list(MissingId), atom_to_list(Constraint)]
    );
format_tree_error({invalid_dependency_constraints, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid depends_on metadata: ~tp",
        [atom_to_list(NuggetId), Detail]
    );
format_tree_error({invalid_dependency_constraint, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid dependency constraint: ~tp",
        [atom_to_list(NuggetId), Detail]
    );
format_tree_error({invalid_auxiliary_products, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid auxiliary_products metadata: ~tp",
        [atom_to_list(NuggetId), Detail]
    );
format_tree_error({invalid_auxiliary_product, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid auxiliary_products entry: ~tp",
        [atom_to_list(NuggetId), Detail]
    ).

format_validation_error({bad_category_cardinality, Category, Count, NuggetIds}) ->
    io_lib:format(
        "plan: target tree must contain exactly one '~ts' nugget; found ~B (~ts)",
        [
            atom_to_list(Category),
            Count,
            string:join([atom_to_list(Id) || Id <- NuggetIds], ", ")
        ]
    );
format_validation_error({missing_category_dependency, NuggetId, Category, Constraint}) ->
    io_lib:format(
        "plan: nugget '~ts' is missing category dependency '~ts' (~ts)",
        [atom_to_list(NuggetId), atom_to_list(Category), atom_to_list(Constraint)]
    );
format_validation_error({missing_capability_dependency, NuggetId, Capability}) ->
    io_lib:format(
        "plan: nugget '~ts' is missing capability dependency '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Capability)]
    );
format_validation_error({missing_nugget_dependency, NuggetId, DependencyId, Constraint}) ->
    io_lib:format(
        "plan: nugget '~ts' is missing nugget dependency '~ts' (~ts)",
        [atom_to_list(NuggetId), atom_to_list(DependencyId), atom_to_list(Constraint)]
    );
format_validation_error({invalid_dependency_match_count, NuggetId, Constraint, Target, Values, Count}) ->
    io_lib:format(
        "plan: nugget '~ts' dependency constraint '~ts' on ~ts expected a different match count; matched ~B for ~tp",
        [atom_to_list(NuggetId), atom_to_list(Constraint), atom_to_list(Target), Count, Values]
    );
format_validation_error({nugget_conflict, NuggetIdA, NuggetIdB}) ->
    io_lib:format(
        "plan: nugget '~ts' conflicts with nugget '~ts'",
        [atom_to_list(NuggetIdA), atom_to_list(NuggetIdB)]
    );
format_validation_error({capability_conflict, NuggetId, capability, Capability}) ->
    io_lib:format(
        "plan: nugget '~ts' conflicts with capability '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Capability)]
    );
format_validation_error({incompatible_version, RequesterId, TargetId, Required, Actual}) ->
    io_lib:format(
        "plan: nugget '~ts' requires '~ts' version '~ts' but found ~ts",
        [
            atom_to_list(RequesterId),
            atom_to_list(TargetId),
            Required,
            format_version(Actual)
        ]
    );
format_validation_error({incompatible_auxiliary_version, AuxId, TargetId, Required, Actual}) ->
    io_lib:format(
        "plan: auxiliary target '~ts' requires root nugget '~ts' version '~ts' but found ~ts",
        [atom_to_list(AuxId), atom_to_list(TargetId), Required, format_version(Actual)]
    );
format_validation_error({invalid_flavor, NuggetId, Flavor}) ->
    io_lib:format(
        "plan: nugget '~ts' does not declare requested flavor '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Flavor)]
    );
format_validation_error({flavor_mismatch, NuggetId, Flavor}) ->
    io_lib:format(
        "plan: nugget '~ts' has conflicting flavor requirements including '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Flavor)]
    );
format_validation_error({duplicate_auxiliary_id, AuxId}) ->
    io_lib:format(
        "plan: duplicate auxiliary target id '~ts'",
        [atom_to_list(AuxId)]
    );
format_validation_error({reserved_auxiliary_id, AuxId}) ->
    io_lib:format(
        "plan: auxiliary target id '~ts' is reserved",
        [atom_to_list(AuxId)]
    );
format_validation_error({auxiliary_forbidden_category, AuxId, NuggetId, Category}) ->
    io_lib:format(
        "plan: auxiliary target '~ts' introduces forbidden category '~ts' via nugget '~ts'",
        [atom_to_list(AuxId), atom_to_list(Category), atom_to_list(NuggetId)]
    );
format_validation_error({invalid_auxiliary_constraint, Constraint}) ->
    io_lib:format(
        "plan: invalid auxiliary target constraint: ~tp",
        [Constraint]
    );
format_validation_error({shared_flavor_mismatch, AuxId, NuggetId, MainFlavor, AuxFlavor}) ->
    io_lib:format(
        "plan: shared nugget '~ts' resolves to different flavors in main vs auxiliary '~ts' (~ts vs ~ts)",
        [
            atom_to_list(NuggetId),
            atom_to_list(AuxId),
            format_flavor(MainFlavor),
            format_flavor(AuxFlavor)
        ]
    );
format_validation_error({invalid_hooks_metadata, NuggetId, Hooks}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid hooks metadata: ~tp",
        [atom_to_list(NuggetId), Hooks]
    );
format_validation_error({invalid_hook, NuggetId, Hook}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid hook entry: ~tp",
        [atom_to_list(NuggetId), Hook]
    );
format_validation_error({invalid_hook_type, NuggetId, HookType}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid hook type '~ts'",
        [atom_to_list(NuggetId), atom_to_list(HookType)]
    );
format_validation_error({unknown_hook_scope, NuggetId, HookType, Scope}) ->
    io_lib:format(
        "plan: nugget '~ts' uses unknown scope '~ts' for hook '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Scope), atom_to_list(HookType)]
    );
format_validation_error({invalid_hook_scope, NuggetId, HookType, Scope}) ->
    io_lib:format(
        "plan: nugget '~ts' uses invalid scope '~tp' for hook '~ts'",
        [atom_to_list(NuggetId), Scope, atom_to_list(HookType)]
    );
format_validation_error({invalid_firmware_hook_scope, NuggetId, HookType, Scope}) ->
    io_lib:format(
        "plan: nugget '~ts' uses auxiliary-only scope '~ts' for firmware hook '~ts'",
        [atom_to_list(NuggetId), atom_to_list(Scope), atom_to_list(HookType)]
    );
format_validation_error({invalid_dependency_constraints, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid depends_on metadata: ~tp",
        [atom_to_list(NuggetId), Detail]
    );
format_validation_error({invalid_dependency_constraint, NuggetId, Detail}) ->
    io_lib:format(
        "plan: nugget '~ts' has invalid dependency constraint: ~tp",
        [atom_to_list(NuggetId), Detail]
    );
format_validation_error(Reason) ->
    io_lib:format("plan: target validation failed: ~tp", [Reason]).

format_version(undefined) ->
    "undefined";
format_version(Version) when is_binary(Version) ->
    binary_to_list(Version);
format_version(Version) ->
    io_lib:format("~tp", [Version]).

format_flavor(undefined) ->
    "undefined";
format_flavor(Flavor) ->
    atom_to_list(Flavor).
