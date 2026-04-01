%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_motherlode).
-moduledoc """
Motherlode loader for staged nugget repositories.

The loader scans repository directories under the motherlode root, reads
`.nuggets` and `.nugget` term files, normalizes supported metadata, and
returns one deterministic in-memory structure for the later planning stages.
""".

%=== EXPORTS ===================================================================

-export([load/1]).


%=== MACROS ====================================================================

-define(
    ALLOWED_DEFAULT_KEYS,
    [license, license_files, author, maintainer, homepage, security_contact]
).


%=== API FUNCTIONS =============================================================

-doc """
Load a motherlode directory into the canonical Smelterl map structure.

The returned map currently contains `nuggets` and `repositories` keys. Failures
preserve enough path/context detail for command-level error reporting.
""".
-spec load(string() | binary()) -> {ok, map()} | {error, term()}.
load(MotherlodePath) ->
    MotherlodePathString = to_list(MotherlodePath),
    case file:list_dir_all(MotherlodePathString) of
        {ok, Entries} ->
            RootPath = filename:absname(MotherlodePathString),
            RepoDirs = [
                Entry
             || Entry <- lists:sort(Entries),
                filelib:is_dir(filename:join(RootPath, Entry))
            ],
            load_repositories(
                RootPath,
                RepoDirs,
                #{nuggets => #{}, repositories => #{}}
            );
        {error, Posix} ->
            {error, {invalid_path, to_binary(MotherlodePathString), Posix}}
    end.


%=== INTERNAL FUNCTIONS ========================================================

load_repositories(_RootPath, [], Motherlode) ->
    {ok, Motherlode};
load_repositories(RootPath, [RepoName | Rest], Motherlode0) ->
    RepoPath = filename:join(RootPath, RepoName),
    case load_repository(RepoPath, RepoName, Motherlode0) of
        {ok, Motherlode1} ->
            load_repositories(RootPath, Rest, Motherlode1);
        {error, _} = Error ->
            Error
    end.

load_repository(RepoPath, RepoName, Motherlode0) ->
    RegistryPath = filename:join(RepoPath, ".nuggets"),
    case filelib:is_regular(RegistryPath) of
        false ->
            {ok, Motherlode0};
        true ->
            case parse_registry(RepoPath, RegistryPath) of
                {ok, Registry} ->
                    RepoId = list_to_atom(RepoName),
                    load_nuggets(
                        RepoPath,
                        RepoId,
                        maps:get(defaults, Registry),
                        maps:get(nuggets, Registry),
                        Motherlode0
                    );
                {error, _} = Error ->
                    Error
            end
    end.

load_nuggets(_RepoPath, _RepoId, _Defaults, [], Motherlode) ->
    {ok, Motherlode};
load_nuggets(RepoPath, RepoId, Defaults, [NuggetRelPath | Rest], Motherlode0) ->
    MetadataPath = filename:join(RepoPath, NuggetRelPath),
    case filelib:is_regular(MetadataPath) of
        false ->
            {error, {missing_metadata, to_binary(RepoPath), to_binary(NuggetRelPath)}};
        true ->
            case parse_nugget(
                RepoPath,
                RepoId,
                NuggetRelPath,
                MetadataPath,
                Defaults
            ) of
                {ok, NuggetId, Nugget} ->
                    case add_nugget(NuggetId, Nugget, Motherlode0) of
                        {ok, Motherlode1} ->
                            load_nuggets(
                                RepoPath,
                                RepoId,
                                Defaults,
                                Rest,
                                Motherlode1
                            );
                        {error, _} = Error ->
                            Error
                    end;
                {error, _} = Error ->
                    Error
            end
    end.

add_nugget(NuggetId, Nugget, Motherlode0) ->
    Nuggets0 = maps:get(nuggets, Motherlode0),
    case maps:get(NuggetId, Nuggets0, undefined) of
        undefined ->
            {ok, Motherlode0#{nuggets := maps:put(NuggetId, Nugget, Nuggets0)}};
        Existing ->
            {error,
                {duplicated_nugget_id,
                    NuggetId,
                    maps:get(repo_path, Existing),
                    maps:get(repo_path, Nugget)}}
    end.

parse_registry(RepoPath, RegistryPath) ->
    case read_term(RegistryPath) of
        {ok, {nugget_registry, Version, Fields}}
        when is_binary(Version), is_list(Fields) ->
            validate_registry_fields(RepoPath, Fields);
        {ok, _Other} ->
            {error, {invalid_registry, to_binary(RepoPath), invalid_root}};
        {error, Detail} ->
            {error, {invalid_registry, to_binary(RepoPath), Detail}}
    end.

validate_registry_fields(RepoPath, Fields) ->
    case fields_valid(Fields) of
        false ->
            {error, {invalid_registry, to_binary(RepoPath), invalid_fields}};
        true ->
            case validate_defaults(
                RepoPath,
                proplists:get_value(defaults, Fields, [])
            ) of
                {ok, Defaults} ->
                    case validate_nugget_paths(
                        proplists:get_value(nuggets, Fields, undefined)
                    ) of
                        {ok, NuggetPaths} ->
                            {ok, #{defaults => Defaults, nuggets => NuggetPaths}};
                        {error, Detail} ->
                            {error, {invalid_registry, to_binary(RepoPath), Detail}}
                    end;
                {error, _} = Error ->
                    Error
            end
    end.

validate_nugget_paths(undefined) ->
    {error, missing_nuggets};
validate_nugget_paths(Paths) when is_list(Paths) ->
    case lists:all(fun(Path) -> is_binary(Path) end, Paths) of
        true ->
            {ok, [to_list(Path) || Path <- Paths]};
        false ->
            {error, invalid_nuggets}
    end;
validate_nugget_paths(_Other) ->
    {error, invalid_nuggets}.

validate_defaults(RepoPath, Defaults) when is_list(Defaults) ->
    validate_defaults(RepoPath, Defaults, #{});
validate_defaults(RepoPath, _Defaults) ->
    {error, {invalid_registry, to_binary(RepoPath), invalid_defaults}}.

validate_defaults(_RepoPath, [], Acc) ->
    {ok, Acc};
validate_defaults(RepoPath, [{Key, Value} | Rest], Acc) ->
    case lists:member(Key, ?ALLOWED_DEFAULT_KEYS) of
        false ->
            {error,
                {invalid_registry, to_binary(RepoPath), {unsupported_default, Key}}};
        true ->
            case normalize_sbom_value(
                registry,
                RepoPath,
                <<".nuggets">>,
                Key,
                Value
            ) of
                {ok, Normalized} ->
                    validate_defaults(
                        RepoPath,
                        Rest,
                        maps:put(Key, Normalized, Acc)
                    );
                {error, _} = Error ->
                    Error
            end
    end;
validate_defaults(RepoPath, [_Invalid | _], _Acc) ->
    {error, {invalid_registry, to_binary(RepoPath), invalid_defaults}}.

parse_nugget(RepoPath, RepoId, NuggetRelPath, MetadataPath, Defaults) ->
    case read_term(MetadataPath) of
        {ok, {nugget, Version, Fields}}
        when is_binary(Version), is_list(Fields) ->
            validate_nugget_fields(
                RepoPath,
                RepoId,
                NuggetRelPath,
                Fields,
                Defaults
            );
        {ok, _Other} ->
            {error,
                {invalid_metadata,
                    to_binary(RepoPath),
                    to_binary(NuggetRelPath),
                    invalid_root}};
        {error, Detail} ->
            {error,
                {invalid_metadata, to_binary(RepoPath), to_binary(NuggetRelPath), Detail}}
    end.

validate_nugget_fields(RepoPath, RepoId, NuggetRelPath, Fields, Defaults) ->
    case fields_valid(Fields) of
        false ->
            {error,
                {invalid_metadata,
                    to_binary(RepoPath),
                    to_binary(NuggetRelPath),
                    invalid_fields}};
        true ->
            case proplists:get_value(id, Fields, undefined) of
                NuggetId when is_atom(NuggetId), NuggetId =/= undefined ->
                    build_nugget(
                        RepoPath,
                        RepoId,
                        NuggetRelPath,
                        NuggetId,
                        fields_to_map(Fields),
                        Defaults
                    );
                _ ->
                    {error,
                        {invalid_metadata,
                            to_binary(RepoPath),
                            to_binary(NuggetRelPath),
                            missing_id}}
            end
    end.

build_nugget(RepoPath, RepoId, NuggetRelPath, NuggetId, FieldMap0, Defaults) ->
    case normalize_config_entries(
        NuggetId,
        maps:get(config, FieldMap0, undefined),
        config
    ) of
        {ok, ConfigEntries} ->
            case normalize_config_entries(
                NuggetId,
                maps:get(exports, FieldMap0, undefined),
                exports
            ) of
                {ok, ExportEntries} ->
                    case merge_sbom_fields(
                        RepoPath,
                        NuggetRelPath,
                        FieldMap0,
                        Defaults
                    ) of
                        {ok, SbomFields} ->
                            NuggetRelDir =
                                normalize_rel_dir(filename:dirname(NuggetRelPath)),
                            FieldMap1 = maps:remove(
                                config,
                                maps:remove(
                                    exports,
                                    maps:remove(license_file, FieldMap0)
                                )
                            ),
                            Nugget = FieldMap1#{
                                id => NuggetId,
                                config => ConfigEntries,
                                exports => ExportEntries,
                                repo_path => to_binary(RepoPath),
                                nugget_relpath => to_binary(NuggetRelDir),
                                repository => RepoId
                            },
                            {ok, NuggetId, maps:merge(Nugget, SbomFields)};
                        {error, _} = Error ->
                            Error
                    end;
                {error, Detail} ->
                    {error,
                        {invalid_metadata,
                            to_binary(RepoPath),
                            to_binary(NuggetRelPath),
                            Detail}}
            end;
        {error, Detail} ->
            {error,
                {invalid_metadata, to_binary(RepoPath), to_binary(NuggetRelPath), Detail}}
    end.

merge_sbom_fields(RepoPath, NuggetRelPath, FieldMap, Defaults) ->
    merge_sbom_fields(
        RepoPath,
        NuggetRelPath,
        FieldMap,
        Defaults,
        ?ALLOWED_DEFAULT_KEYS,
        #{}
    ).

merge_sbom_fields(_RepoPath, _NuggetRelPath, _FieldMap, _Defaults, [], Acc) ->
    {ok, Acc};
merge_sbom_fields(
    RepoPath,
    NuggetRelPath,
    FieldMap,
    Defaults,
    [Key | Rest],
    Acc
) ->
    case sbom_field_value(Key, FieldMap) of
        {nugget, Value} ->
            case normalize_sbom_value(
                nugget,
                RepoPath,
                to_binary(NuggetRelPath),
                Key,
                Value
            ) of
                {ok, Normalized} ->
                    merge_sbom_fields(
                        RepoPath,
                        NuggetRelPath,
                        FieldMap,
                        Defaults,
                        Rest,
                        maps:put(Key, {nugget, Normalized}, Acc)
                    );
                {error, _} = Error ->
                    Error
            end;
        undefined ->
            case maps:get(Key, Defaults, undefined) of
                undefined ->
                    merge_sbom_fields(
                        RepoPath,
                        NuggetRelPath,
                        FieldMap,
                        Defaults,
                        Rest,
                        Acc
                    );
                DefaultValue ->
                    merge_sbom_fields(
                        RepoPath,
                        NuggetRelPath,
                        FieldMap,
                        Defaults,
                        Rest,
                        maps:put(Key, {registry, DefaultValue}, Acc)
                    )
            end
    end.

sbom_field_value(license_files, FieldMap) ->
    case maps:get(license_files, FieldMap, undefined) of
        undefined ->
            case maps:get(license_file, FieldMap, undefined) of
                undefined -> undefined;
                Value -> {nugget, [Value]}
            end;
        Value ->
            {nugget, Value}
    end;
sbom_field_value(Key, FieldMap) ->
    case maps:get(Key, FieldMap, undefined) of
        undefined -> undefined;
        Value -> {nugget, Value}
    end.

normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, license, Value)
  when is_binary(Value) ->
    {ok, Value};
normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, author, Value)
  when is_binary(Value) ->
    {ok, Value};
normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, maintainer, Value)
  when is_binary(Value) ->
    {ok, Value};
normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, homepage, Value)
  when is_binary(Value) ->
    {ok, Value};
normalize_sbom_value(
    _Source,
    _RepoPath,
    _DeclaringRelPath,
    security_contact,
    Value
)
  when is_binary(Value) ->
    {ok, Value};
normalize_sbom_value(
    _Source,
    RepoPath,
    DeclaringRelPath,
    license_files,
    Value
)
  when is_list(Value) ->
    resolve_license_files(RepoPath, DeclaringRelPath, Value);
normalize_sbom_value(_Source, _RepoPath, _DeclaringRelPath, Key, _Value) ->
    {error, {invalid_sbom_value, Key}}.

resolve_license_files(RepoPath, DeclaringRelPath, Values) ->
    case lists:all(fun(Value) -> is_binary(Value) end, Values) of
        false ->
            {error, {invalid_sbom_value, license_files}};
        true ->
            resolve_license_files(RepoPath, DeclaringRelPath, Values, [])
    end.

resolve_license_files(_RepoPath, _DeclaringRelPath, [], Acc) ->
    {ok, lists:reverse(Acc)};
resolve_license_files(RepoPath, DeclaringRelPath, [Value | Rest], Acc) ->
    BaseDir = declaring_base_dir(RepoPath, DeclaringRelPath),
    ValueString = to_list(Value),
    ResolvedPath =
        case filename:pathtype(ValueString) of
            absolute -> ValueString;
            _ -> filename:join(BaseDir, ValueString)
        end,
    case filelib:is_regular(ResolvedPath) of
        true ->
            resolve_license_files(
                RepoPath,
                DeclaringRelPath,
                Rest,
                [to_binary(filename:absname(ResolvedPath)) | Acc]
            );
        false ->
            {error,
                {missing_file,
                    to_binary(RepoPath),
                    DeclaringRelPath,
                    Value,
                    enoent}}
    end.

declaring_base_dir(RepoPath, <<".nuggets">>) ->
    RepoPath;
declaring_base_dir(RepoPath, DeclaringRelPath) ->
    DeclaringPath = to_list(DeclaringRelPath),
    filename:join(
        RepoPath,
        normalize_rel_dir(filename:dirname(DeclaringPath))
    ).

normalize_config_entries(_NuggetId, undefined, _FieldName) ->
    {ok, []};
normalize_config_entries(NuggetId, Entries, _FieldName) when is_list(Entries) ->
    normalize_config_entries_acc(NuggetId, Entries, []);
normalize_config_entries(_NuggetId, _Entries, FieldName) ->
    {error, {invalid_config_entries, FieldName}}.

normalize_config_entries_acc(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
normalize_config_entries_acc(
    NuggetId,
    [{Key, Value} | Rest],
    Acc
)
  when is_atom(Key) ->
    normalize_config_entries_acc(
        NuggetId,
        Rest,
        [{Key, Value, NuggetId} | Acc]
    );
normalize_config_entries_acc(_NuggetId, [_Invalid | _], _Acc) ->
    {error, invalid_config_entry}.

read_term(Path) ->
    case file:consult(Path) of
        {ok, [Term]} ->
            {ok, Term};
        {ok, _Terms} ->
            {error, multiple_terms};
        {error, FileError} ->
            {error, {parse_error, FileError}}
    end.

fields_valid(Fields) ->
    lists:all(
        fun(Field) ->
            is_tuple(Field) andalso tuple_size(Field) =:= 2
        end,
        Fields
    ).

fields_to_map(Fields) ->
    lists:foldl(
        fun({Key, Value}, Acc) ->
            maps:put(Key, Value, Acc)
        end,
        #{},
        Fields
    ).

normalize_rel_dir(".") ->
    "";
normalize_rel_dir(Dir) ->
    Dir.

to_list(Path) when is_binary(Path) ->
    binary_to_list(Path);
to_list(Path) when is_list(Path) ->
    Path.

to_binary(Path) when is_binary(Path) ->
    Path;
to_binary(Path) when is_list(Path) ->
    unicode:characters_to_binary(Path).
