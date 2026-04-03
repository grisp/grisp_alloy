%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl).
-moduledoc """
Main `smelterl` escript entrypoint.

This module loads the application configuration needed by the CLI and then
delegates argument handling to `smelterl_cli`.
""".

%=== EXPORTS ===================================================================

-export([main/1]).
-export_type([
    smelterl_config/0,
    target_id/0,
    nugget_id/0,
    motherlode/0,
    nugget_tree/0,
    auxiliary_constraint_prop/0,
    auxiliary_target/0,
    target_trees/0,
    nugget_topology_order/0,
    topology_orders/0,
    target_motherlodes/0,
    config_entry_kind/0,
    config_entry/0,
    config/0,
    target_configs/0,
    firmware_output_spec/0,
    firmware_parameter_spec/0,
    sdk_output_spec/0,
    firmware_capabilities/0
]).


%=== TYPES =====================================================================

-doc """
Runtime configuration passed into the CLI dispatcher.

The command-handlers map selects the module that owns each top-level command,
and the version string is shown by `--version`.
""".
-type smelterl_config() :: #{
    command_handlers := #{atom() => module()},
    version := string()
}.

-doc "Identifier for one planned build target (`main` or an auxiliary id).".
-type target_id() :: atom().

-doc "Canonical nugget identifier used across the plan and generate pipelines.".
-type nugget_id() :: atom().

-doc "Loaded motherlode structure keyed by nugget id plus repository metadata.".
-type motherlode() :: #{
    nuggets := #{nugget_id() => map()},
    repositories := map()
}.

-doc "Dependency tree for one target, with the root nugget and nugget-only edges.".
-type nugget_tree() :: #{
    root := nugget_id(),
    edges := #{nugget_id() => [nugget_id()]}
}.

-doc "One auxiliary-target constraint property preserved from nugget metadata.".
-type auxiliary_constraint_prop() :: {version, binary()} | {flavor, atom()}.

-doc "Resolved auxiliary target metadata plus its specific and effective trees.".
-type auxiliary_target() :: #{
    id := nugget_id(),
    root_nugget := nugget_id(),
    constraints := [auxiliary_constraint_prop()],
    specific_tree := nugget_tree(),
    tree := nugget_tree()
}.

-doc "Full target set produced during plan: one main target and zero or more auxiliaries.".
-type target_trees() :: #{
    main := nugget_tree(),
    auxiliaries := [auxiliary_target()]
}.

-doc "Deterministic dependency-before-dependent nugget order for one target.".
-type nugget_topology_order() :: [nugget_id()].

-doc "Per-target topology orders keyed by `main` or auxiliary id.".
-type topology_orders() :: #{target_id() => nugget_topology_order()}.

-doc "Target-local motherlode views after overrides have been applied.".
-type target_motherlodes() :: #{target_id() => motherlode()}.

-doc "Source kind for one consolidated config entry.".
-type config_entry_kind() :: extra | nugget | global.

-doc "One resolved config entry as exported into generated shell environments.".
-type config_entry() :: {config_entry_kind(), nugget_id() | undefined, binary()}.

-doc "Resolved config map keyed by full environment variable name.".
-type config() :: #{binary() => config_entry()}.

-doc "Per-target consolidated configs keyed by `main` or auxiliary id.".
-type target_configs() :: #{target_id() => config()}.

-doc "Plan-stage selectable firmware output metadata carried into later generators.".
-type firmware_output_spec() :: #{
    id := atom(),
    default := boolean(),
    name => binary(),
    description => binary()
}.

-doc "Merged firmware parameter declaration produced during capability discovery.".
-type firmware_parameter_spec() :: #{
    id := atom(),
    type := atom(),
    required => boolean(),
    name => binary(),
    description => binary(),
    default => term()
}.

-doc "One target-local SDK output declaration with declaring nugget metadata.".
-type sdk_output_spec() :: #{
    id := atom(),
    nugget := nugget_id(),
    name => binary(),
    description => binary()
}.

-doc "Capability payload produced by plan-stage discovery for context and manifest generation.".
-type firmware_capabilities() :: #{
    firmware_variants := [atom()],
    variant_nuggets := #{atom() => [nugget_id()]},
    selectable_outputs := [firmware_output_spec()],
    firmware_parameters := [firmware_parameter_spec()],
    sdk_outputs_by_target := #{target_id() => [sdk_output_spec()]}
}.


%=== API FUNCTIONS =============================================================

-doc """
Run the `smelterl` command-line entrypoint for one argv list.

Returns the process exit status that the outer escript wrapper should use.
""".
-spec main([string()]) -> integer().
main(Argv) ->
    ok = ensure_application_loaded(),
    Config = #{
        command_handlers => command_handlers(),
        version => version()
    },
    smelterl_cli:run(Argv, Config).


%=== INTERNAL FUNCTIONS ========================================================

ensure_application_loaded() ->
    case application:load(smelterl) of
        ok -> ok;
        {error, {already_loaded, smelterl}} -> ok
    end.

command_handlers() ->
    {ok, Handlers} = application:get_env(smelterl, command_handlers),
    maps:from_list(Handlers).

version() ->
    case application:get_env(smelterl, version) of
        {ok, Version} ->
            Version;
        undefined ->
            case application:get_key(smelterl, vsn) of
                {ok, Version} -> Version;
                undefined -> "dev"
            end
    end.
