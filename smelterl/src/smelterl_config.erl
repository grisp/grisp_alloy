%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_config).
-moduledoc """
Consolidate target-local nugget config and exports for the plan pipeline.

This module consumes one overridden target tree, topology order, and
target-local motherlode view, then resolves immediate values plus deferred
`computed` and `exec` entries into the unified environment-variable map used by
later plan and generate stages.
""".


%=== EXPORTS ===================================================================

-export([consolidate/4]).


%=== TYPES =====================================================================

-type deferred_item() :: #{
    index := pos_integer(),
    key := atom(),
    slot_nugget_id := smelterl:nugget_id(),
    origin_nugget_id := smelterl:nugget_id(),
    global_env_key := binary(),
    nugget_env_key := binary(),
    value := term()
}.

-type resolved_entry() :: {pos_integer(), smelterl:config_entry()}.
-type resolved_entries() :: #{binary() => [resolved_entry()]}.
-type state() :: #{
    next_index := non_neg_integer(),
    resolved := resolved_entries(),
    config_owner_by_key := #{atom() => smelterl:nugget_id()},
    export_owner_by_key := #{atom() => smelterl:nugget_id()},
    computed := [deferred_item()],
    exec := [deferred_item()]
}.


%=== API FUNCTIONS =============================================================

-doc """
Consolidate config and exports for one overridden target.

Immediate values are resolved during the initial topology walk, while
`computed` and `exec` values are resolved later against the already-available
configuration context. The result is keyed by full shell environment variable
name.
""".
-spec consolidate(
    smelterl:nugget_tree(),
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    #{binary() => binary()}
) ->
    {ok, smelterl:config()} | {error, term()}.
consolidate(Tree, Topology, Motherlode, ExtraConfig) ->
    maybe
        {ok, Flavors} ?= resolve_flavors(Tree, Motherlode),
        {ok, State1} ?= collect_entries(
            Topology,
            maps:from_list([{NuggetId, true} || NuggetId <- maps:keys(maps:get(edges, Tree))]),
            Motherlode,
            Flavors,
            initial_state()
        ),
        {ok, State2} ?= resolve_computed(State1, ExtraConfig),
        {ok, State3} ?= resolve_exec(State2, Motherlode, ExtraConfig),
        {ok, final_config(maps:get(resolved, State3))}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec initial_state() -> state().
initial_state() ->
    #{
        next_index => 0,
        resolved => #{},
        config_owner_by_key => #{},
        export_owner_by_key => #{},
        computed => [],
        exec => []
    }.

resolve_flavors(Tree, Motherlode) ->
    case smelterl_validate:resolved_flavors(Tree, Motherlode) of
        {ok, Flavors} ->
            {ok, Flavors};
        {error, {invalid_flavor, NuggetId, Flavor}} ->
            {error, {invalid_flavor, NuggetId, Flavor}};
        {error, {flavor_mismatch, NuggetId, Flavor}} ->
            {error, {invalid_flavor, NuggetId, {flavor_mismatch, Flavor}}};
        {error, Reason} ->
            {error, {invalid_flavor, maps:get(root, Tree), Reason}}
    end.

collect_entries([], _NodeSet, _Motherlode, _Flavors, State) ->
    {ok, State};
collect_entries([NuggetId | Rest], NodeSet, Motherlode, Flavors, State0) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, State1} ?= collect_nugget_entries(
            NuggetId,
            config,
            maps:get(config, Nugget, []),
            NodeSet,
            Motherlode,
            Flavors,
            State0
        ),
        {ok, State2} ?= collect_nugget_entries(
            NuggetId,
            exports,
            maps:get(exports, Nugget, []),
            NodeSet,
            Motherlode,
            Flavors,
            State1
        ),
        collect_entries(Rest, NodeSet, Motherlode, Flavors, State2)
    else
        {error, _} = Error ->
            Error
    end.

collect_nugget_entries(_NuggetId, _EntryKind, [], _NodeSet, _Motherlode, _Flavors, State) ->
    {ok, State};
collect_nugget_entries(
    NuggetId,
    EntryKind,
    [Entry | Rest],
    NodeSet,
    Motherlode,
    Flavors,
    State0
) ->
    maybe
        {ok, Key, Value, OriginNuggetId} ?= parse_entry(NuggetId, Entry),
        ok ?= check_conflicts(NuggetId, EntryKind, Key, State0),
        {ok, State1} ?= collect_entry(
            NuggetId,
            OriginNuggetId,
            Key,
            Value,
            NodeSet,
            Motherlode,
            Flavors,
            State0
        ),
        State2 = remember_owner(NuggetId, EntryKind, Key, State1),
        collect_nugget_entries(
            NuggetId,
            EntryKind,
            Rest,
            NodeSet,
            Motherlode,
            Flavors,
            State2
        )
    else
        {error, _} = Error ->
            Error
    end.

parse_entry(_NuggetId, {Key, Value, OriginNuggetId})
  when is_atom(Key), is_atom(OriginNuggetId) ->
    {ok, Key, Value, OriginNuggetId};
parse_entry(NuggetId, Entry) ->
    {error, {template_error, NuggetId, invalid_entry, Entry}}.

check_conflicts(NuggetId, config, Key, State) ->
    ExportOwners = maps:get(export_owner_by_key, State),
    case maps:get(Key, ExportOwners, undefined) of
        undefined ->
            ok;
        ExportNuggetId ->
            {error, {export_config_conflict, Key, ExportNuggetId, NuggetId}}
    end;
check_conflicts(NuggetId, exports, Key, State) ->
    ConfigOwners = maps:get(config_owner_by_key, State),
    ExportOwners = maps:get(export_owner_by_key, State),
    case {maps:get(Key, ConfigOwners, undefined), maps:get(Key, ExportOwners, undefined)} of
        {NuggetId, undefined} ->
            {error, {config_export_conflict, NuggetId, Key}};
        {ConfigNuggetId, undefined} when ConfigNuggetId =/= undefined ->
            {error, {export_config_conflict, Key, NuggetId, ConfigNuggetId}};
        {_ConfigNuggetId, NuggetId} ->
            ok;
        {_ConfigNuggetId, ExportNuggetId} when ExportNuggetId =/= undefined ->
            {error, {duplicate_export, Key, ExportNuggetId, NuggetId}};
        {undefined, undefined} ->
            ok
    end.

remember_owner(NuggetId, config, Key, State0) ->
    ConfigOwners0 = maps:get(config_owner_by_key, State0),
    State0#{config_owner_by_key := maps:put(Key, NuggetId, ConfigOwners0)};
remember_owner(NuggetId, exports, Key, State0) ->
    ExportOwners0 = maps:get(export_owner_by_key, State0),
    State0#{export_owner_by_key := maps:put(Key, NuggetId, ExportOwners0)}.

collect_entry(
    SlotNuggetId,
    OriginNuggetId,
    Key,
    Value,
    NodeSet,
    Motherlode,
    Flavors,
    State0
) ->
    Index = maps:get(next_index, State0) + 1,
    GlobalEnvKey = global_env_key(Key),
    NuggetEnvKey = nugget_env_key(SlotNuggetId, Key),
    maybe
        {ok, ResolvedValue} ?= resolve_value(
            OriginNuggetId,
            Key,
            Value,
            NodeSet,
            Motherlode,
            Flavors
        ),
        State1 = State0#{next_index := Index},
        store_resolution(
            Index,
            SlotNuggetId,
            OriginNuggetId,
            Key,
            ResolvedValue,
            GlobalEnvKey,
            NuggetEnvKey,
            State1
        )
    else
        {error, _} = Error ->
            Error
    end.

resolve_value(_OriginNuggetId, _Key, Value, _NodeSet, _Motherlode, _Flavors)
  when is_binary(Value); is_atom(Value); is_integer(Value) ->
    {ok, {resolved, value_to_binary(Value)}};
resolve_value(OriginNuggetId, _Key, {path, PathSpec}, NodeSet, Motherlode, _Flavors)
  when is_binary(PathSpec) ->
    resolve_path(OriginNuggetId, PathSpec, NodeSet, Motherlode);
resolve_value(_OriginNuggetId, _Key, {computed, Template}, _NodeSet, _Motherlode, _Flavors)
  when is_binary(Template) ->
    {ok, {computed, Template}};
resolve_value(_OriginNuggetId, _Key, {exec, ScriptPath}, _NodeSet, _Motherlode, _Flavors)
  when is_binary(ScriptPath) ->
    {ok, {exec, ScriptPath}};
resolve_value(OriginNuggetId, Key, {flavor_map, FlavorMap}, NodeSet, Motherlode, Flavors)
  when is_list(FlavorMap) ->
    case select_flavor_value(OriginNuggetId, FlavorMap, Flavors) of
        {ok, SelectedValue} ->
            resolve_value(
                OriginNuggetId,
                Key,
                SelectedValue,
                NodeSet,
                Motherlode,
                Flavors
            );
        {error, _} = Error ->
            Error
    end;
resolve_value(OriginNuggetId, Key, Value, _NodeSet, _Motherlode, _Flavors) ->
    {error, {template_error, OriginNuggetId, Key, {invalid_value, Value}}}.

select_flavor_value(OriginNuggetId, FlavorMap, Flavors) ->
    Flavor = maps:get(OriginNuggetId, Flavors, undefined),
    case [Value || {CandidateFlavor, Value} <- FlavorMap, CandidateFlavor =:= Flavor] of
        [SelectedValue] ->
            {ok, SelectedValue};
        _ ->
            {error, {invalid_flavor, OriginNuggetId, Flavor}}
    end.

resolve_path(_OriginNuggetId, <<"/", _/binary>> = PathSpec, _NodeSet, _Motherlode) ->
    {ok, {resolved, PathSpec}};
resolve_path(OriginNuggetId, <<"@", Rest/binary>>, NodeSet, Motherlode) ->
    case split_nugget_path(Rest) of
        {ok, RefNuggetId, RefPath} ->
            case maps:is_key(RefNuggetId, NodeSet) of
                true ->
                    {ok, {resolved, motherlode_path(RefNuggetId, RefPath, Motherlode)}};
                false ->
                    {error,
                        {path_resolution_failed,
                            OriginNuggetId,
                            <<"@", Rest/binary>>,
                            {unknown_path_nugget, RefNuggetId}}}
            end;
        {error, Detail} ->
            {error, {path_resolution_failed, OriginNuggetId, <<"@", Rest/binary>>, Detail}}
    end;
resolve_path(OriginNuggetId, PathSpec, _NodeSet, Motherlode) ->
    {ok, {resolved, motherlode_path(OriginNuggetId, PathSpec, Motherlode)}}.

split_nugget_path(PathSpec) ->
    case binary:match(PathSpec, <<"/">>) of
        nomatch ->
            {error, invalid_nugget_reference};
        {0, _Len} ->
            {error, invalid_nugget_reference};
        {Pos, _Len} when Pos =:= byte_size(PathSpec) - 1 ->
            {error, invalid_nugget_reference};
        {Pos, _Len} ->
            NuggetIdBinary = binary:part(PathSpec, 0, Pos),
            Rest = binary:part(PathSpec, Pos + 1, byte_size(PathSpec) - Pos - 1),
            {ok, binary_to_atom(NuggetIdBinary, utf8), Rest}
    end.

motherlode_path(NuggetId, RelativePath, Motherlode) ->
    Prefix = nugget_motherlode_prefix(NuggetId, Motherlode),
    <<Prefix/binary, "/", RelativePath/binary>>.

nugget_motherlode_prefix(NuggetId, Motherlode) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    Repo = atom_to_binary(maps:get(repository, Nugget), utf8),
    case maps:get(nugget_relpath, Nugget, <<>>) of
        <<>> ->
            <<"${ALLOY_MOTHERLODE}/", Repo/binary>>;
        RelPath ->
            <<"${ALLOY_MOTHERLODE}/", Repo/binary, "/", RelPath/binary>>
    end.

store_resolution(
    Index,
    SlotNuggetId,
    _OriginNuggetId,
    _Key,
    {resolved, Value},
    GlobalEnvKey,
    NuggetEnvKey,
    State0
) ->
    {ok,
        store_resolved_entries(
            Index,
            SlotNuggetId,
            Value,
            GlobalEnvKey,
            NuggetEnvKey,
            State0
        )};
store_resolution(
    Index,
    SlotNuggetId,
    OriginNuggetId,
    Key,
    {computed, Template},
    GlobalEnvKey,
    NuggetEnvKey,
    State0
) ->
    DeferredItem = #{
        index => Index,
        key => Key,
        slot_nugget_id => SlotNuggetId,
        origin_nugget_id => OriginNuggetId,
        global_env_key => GlobalEnvKey,
        nugget_env_key => NuggetEnvKey,
        value => Template
    },
    {ok, State0#{next_index := Index, computed := maps:get(computed, State0) ++ [DeferredItem]}};
store_resolution(
    Index,
    SlotNuggetId,
    OriginNuggetId,
    Key,
    {exec, ScriptPath},
    GlobalEnvKey,
    NuggetEnvKey,
    State0
) ->
    DeferredItem = #{
        index => Index,
        key => Key,
        slot_nugget_id => SlotNuggetId,
        origin_nugget_id => OriginNuggetId,
        global_env_key => GlobalEnvKey,
        nugget_env_key => NuggetEnvKey,
        value => ScriptPath
    },
    {ok, State0#{next_index := Index, exec := maps:get(exec, State0) ++ [DeferredItem]}}.

store_resolved_entries(Index, SlotNuggetId, Value, GlobalEnvKey, NuggetEnvKey, State0) ->
    Resolved0 = maps:get(resolved, State0),
    NuggetEntry = {nugget, SlotNuggetId, Value},
    GlobalEntry = {global, undefined, Value},
    State0#{
        resolved := Resolved0#{
            NuggetEnvKey => maps:get(NuggetEnvKey, Resolved0, []) ++ [{Index, NuggetEntry}],
            GlobalEnvKey => maps:get(GlobalEnvKey, Resolved0, []) ++ [{Index, GlobalEntry}]
        }
    }.

resolve_computed(State0, ExtraConfig) ->
    resolve_computed(maps:get(computed, State0), ExtraConfig, State0).

resolve_computed([], _ExtraConfig, State) ->
    {ok, State};
resolve_computed([Item | Rest], ExtraConfig, State0) ->
    Context = resolved_context(maps:get(index, Item), maps:get(resolved, State0), ExtraConfig),
    Template = maps:get(value, Item),
    case substitute_template(Template, Context) of
        {ok, Value} ->
            State1 = store_resolved_entries(
                maps:get(index, Item),
                maps:get(slot_nugget_id, Item),
                Value,
                maps:get(global_env_key, Item),
                maps:get(nugget_env_key, Item),
                State0
            ),
            resolve_computed(Rest, ExtraConfig, State1);
        {error, Detail} ->
            {error,
                {template_error,
                    maps:get(origin_nugget_id, Item),
                    maps:get(key, Item),
                    Detail}}
    end.

resolve_exec(State0, Motherlode, ExtraConfig) ->
    resolve_exec(maps:get(exec, State0), Motherlode, ExtraConfig, State0).

resolve_exec([], _Motherlode, _ExtraConfig, State) ->
    {ok, State};
resolve_exec([Item | Rest], Motherlode, ExtraConfig, State0) ->
    Context = resolved_context(maps:get(index, Item), maps:get(resolved, State0), ExtraConfig),
    KeyArg = atom_to_binary(maps:get(key, Item), utf8),
    case run_exec(
        maps:get(value, Item),
        maps:get(origin_nugget_id, Item),
        KeyArg,
        Context,
        Motherlode
    ) of
        {ok, Value} ->
            State1 = store_resolved_entries(
                maps:get(index, Item),
                maps:get(slot_nugget_id, Item),
                Value,
                maps:get(global_env_key, Item),
                maps:get(nugget_env_key, Item),
                State0
            ),
            resolve_exec(Rest, Motherlode, ExtraConfig, State1);
        {error, Reason} ->
            {error,
                {exec_failed,
                    maps:get(origin_nugget_id, Item),
                    maps:get(key, Item),
                    Reason}}
    end.

resolved_context(MaxIndex, Resolved, ExtraConfig) ->
    maps:fold(
        fun(EnvKey, Entries, Acc0) ->
            case latest_before(MaxIndex, Entries) of
                undefined ->
                    Acc0;
                {_Index, {_Kind, _NuggetId, Value}} ->
                    maps:put(EnvKey, Value, Acc0)
            end
        end,
        ExtraConfig,
        Resolved
    ).

latest_before(_MaxIndex, []) ->
    undefined;
latest_before(MaxIndex, Entries) ->
    lists:foldl(
        fun
            ({Index, _Entry} = Candidate, undefined) when Index < MaxIndex ->
                Candidate;
            ({Index, _Entry}, Current) when Index >= MaxIndex ->
                Current;
            ({Index, _Entry} = Candidate, {CurrentIndex, _CurrentEntry})
              when Index < MaxIndex, Index > CurrentIndex ->
                Candidate;
            (_Candidate, Current) ->
                Current
        end,
        undefined,
        Entries
    ).

substitute_template(Template, Context) ->
    substitute_template(Template, Context, []).

substitute_template(<<>>, _Context, Acc) ->
    {ok, iolist_to_binary(lists:reverse(Acc))};
substitute_template(Template, Context, Acc) ->
    case binary:match(Template, <<"[[">>) of
        nomatch ->
            {ok, iolist_to_binary(lists:reverse([Template | Acc]))};
        {Pos, _Len} ->
            Prefix = binary:part(Template, 0, Pos),
            Rest0 = binary:part(Template, Pos + 2, byte_size(Template) - Pos - 2),
            case binary:match(Rest0, <<"]]">>) of
                nomatch ->
                    {error, invalid_placeholder};
                {EndPos, _} ->
                    Key = binary:part(Rest0, 0, EndPos),
                    Rest = binary:part(Rest0, EndPos + 2, byte_size(Rest0) - EndPos - 2),
                    case maps:get(Key, Context, undefined) of
                        undefined ->
                            {error, {unknown_key, Key}};
                        Value ->
                            substitute_template(Rest, Context, [Value, Prefix | Acc])
                    end
            end
    end.

run_exec(ScriptPath, OriginNuggetId, KeyArg, Context, Motherlode) ->
    WorkingDir = nugget_abs_dir(OriginNuggetId, Motherlode),
    Script = resolve_script_path(ScriptPath, WorkingDir),
    case filelib:is_regular(Script) of
        false ->
            {error, {script_not_found, unicode:characters_to_binary(Script)}};
        true ->
            run_exec_port(Script, WorkingDir, Context, KeyArg)
    end.

resolve_script_path(<<"/", _/binary>> = ScriptPath, _WorkingDir) ->
    binary_to_list(ScriptPath);
resolve_script_path(ScriptPath, WorkingDir) ->
    filename:join(WorkingDir, binary_to_list(ScriptPath)).

run_exec_port(Script, WorkingDir, Context, KeyArg) ->
    Port =
        open_port(
            {spawn_executable, Script},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                use_stdio,
                hide,
                {cd, WorkingDir},
                {env, env_pairs(Context)},
                {args, [binary_to_list(KeyArg)]}
            ]
        ),
    collect_exec_output(Port, []).

collect_exec_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_exec_output(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            {ok, trim_output(iolist_to_binary(lists:reverse(Acc)))};
        {Port, {exit_status, Status}} ->
            {error, {exit_non_zero, Status, iolist_to_binary(lists:reverse(Acc))}}
    end.

env_pairs(Context) ->
    [
        {binary_to_list(Key), binary_to_list(Value)}
     || {Key, Value} <- maps:to_list(Context)
    ].

trim_output(Output) ->
    unicode:characters_to_binary(string:trim(binary_to_list(Output))).

nugget_abs_dir(NuggetId, Motherlode) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    RepoPath = binary_to_list(maps:get(repo_path, Nugget)),
    case maps:get(nugget_relpath, Nugget, <<>>) of
        <<>> ->
            RepoPath;
        RelPath ->
            filename:join(RepoPath, binary_to_list(RelPath))
    end.

-spec final_config(resolved_entries()) -> smelterl:config().
final_config(Resolved) ->
    maps:from_list([
        {EnvKey, latest_entry(Entries)}
     || {EnvKey, Entries} <- maps:to_list(Resolved)
    ]).

latest_entry(Entries) ->
    {_Index, Entry} =
        lists:foldl(
            fun
                ({_Index, _Entry} = Candidate, undefined) ->
                    Candidate;
                ({Index, _Entry} = Candidate, {CurrentIndex, _CurrentEntry} = _Current)
                  when Index > CurrentIndex ->
                    Candidate;
                (_Candidate, Current) ->
                    Current
            end,
            undefined,
            Entries
        ),
    Entry.

global_env_key(Key) ->
    <<"ALLOY_CONFIG_", (upper_name(Key))/binary>>.

nugget_env_key(NuggetId, Key) ->
    <<"ALLOY_NUGGET_", (upper_name(NuggetId))/binary, "_CONFIG_", (upper_name(Key))/binary>>.

upper_name(Name) when is_atom(Name) ->
    upper_name(atom_to_binary(Name, utf8));
upper_name(Name) when is_binary(Name) ->
    list_to_binary(string:to_upper(binary_to_list(Name))).

value_to_binary(Value) when is_binary(Value) ->
    Value;
value_to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
value_to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value).

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode)).
