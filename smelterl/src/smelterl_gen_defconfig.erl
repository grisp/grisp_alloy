%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_defconfig).
-moduledoc """
Build plan-stage merged defconfig models from nugget fragments.

The plan pipeline calls this module after config consolidation. It resolves the
selected defconfig fragment for each nugget, applies single-pass `[[KEY]]`
substitution from the consolidated/extra config environment, merges regular
keys with last-wins semantics, accumulates configured cumulative keys, and
appends the deterministic target-local Buildroot wrapper hooks.
""".


%=== EXPORTS ===================================================================

-export([build_model/5]).


%=== TYPES =====================================================================

-type cumulative_key_kind() :: path | plain.
-type cumulative_key_spec() :: #{binary() => cumulative_key_kind()}.
-type merge_state() :: #{
    next_index := non_neg_integer(),
    regular := #{binary() => {non_neg_integer(), binary()}},
    cumulative := #{binary() => {non_neg_integer(), [binary()]}}
}.


%=== API FUNCTIONS =============================================================

-doc """
Build the plan-storable defconfig model for one selected target.

The returned model contains the merged regular keys and cumulative keys for the
selected target. The caller is expected to persist the model in the later plan
serialization task.
""".
-spec build_model(
    smelterl:target_id(),
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    smelterl:config(),
    smelterl:nugget_id()
) ->
    {ok, smelterl:defconfig_model()} | {error, term()}.
build_model(TargetId, Topology, Motherlode, Config, ProductId) ->
    maybe
        {ok, CumulativeSpec} ?= load_cumulative_key_spec(),
        {ok, Flavors} ?= resolve_flavors(ProductId, Topology, Motherlode),
        Substitutions = substitution_values(
            TargetId,
            ProductId,
            Motherlode,
            Config
        ),
        {ok, State1} ?= merge_fragments(
            Topology,
            Motherlode,
            Flavors,
            CumulativeSpec,
            Substitutions,
            initial_state()
        ),
        {ok, State2} ?= inject_target_wrappers(TargetId, State1),
        {ok, final_model(State2)}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec initial_state() -> merge_state().
initial_state() ->
    #{
        next_index => 0,
        regular => #{},
        cumulative => #{}
    }.

resolve_flavors(ProductId, Topology, Motherlode) ->
    Tree = #{
        root => ProductId,
        edges => maps:from_list([{NuggetId, []} || NuggetId <- Topology])
    },
    smelterl_validate:resolved_flavors(Tree, Motherlode).

merge_fragments([], _Motherlode, _Flavors, _CumulativeSpec, _Substitutions, State) ->
    {ok, State};
merge_fragments(
    [NuggetId | Rest],
    Motherlode,
    Flavors,
    CumulativeSpec,
    Substitutions,
    State0
) ->
    maybe
        {ok, State1} ?= merge_fragment(
            NuggetId,
            Motherlode,
            Flavors,
            CumulativeSpec,
            Substitutions,
            State0
        ),
        merge_fragments(
            Rest,
            Motherlode,
            Flavors,
            CumulativeSpec,
            Substitutions,
            State1
        )
    else
        {error, _} = Error ->
            Error
    end.

merge_fragment(
    NuggetId,
    Motherlode,
    Flavors,
    CumulativeSpec,
    Substitutions,
    State0
) ->
    Nugget = lookup_nugget(NuggetId, Motherlode),
    maybe
        {ok, FragmentPath} ?= defconfig_fragment_path(NuggetId, Nugget, Flavors),
        case FragmentPath of
            undefined ->
                {ok, State0};
            _ ->
                maybe
                    {ok, Fragment} ?= read_fragment(NuggetId, FragmentPath),
                    {ok, Expanded} ?= expand_fragment(
                        NuggetId,
                        Fragment,
                        Substitutions
                    ),
                    merge_fragment_lines(
                        NuggetId,
                        binary:split(Expanded, <<"\n">>, [global]),
                        Nugget,
                        Motherlode,
                        CumulativeSpec,
                        State0
                    )
                else
                    {error, _} = NestedError ->
                        NestedError
                end
        end
    else
        {error, _} = Error ->
            Error
    end.

merge_fragment_lines(
    _NuggetId,
    [],
    _Nugget,
    _Motherlode,
    _CumulativeSpec,
    State
) ->
    {ok, State};
merge_fragment_lines(
    NuggetId,
    [Line | Rest],
    Nugget,
    Motherlode,
    CumulativeSpec,
    State0
) ->
    TrimmedLine = trim_binary(Line),
    case TrimmedLine of
        <<>> ->
            merge_fragment_lines(
                NuggetId,
                Rest,
                Nugget,
                Motherlode,
                CumulativeSpec,
                State0
            );
        <<"#", _/binary>> ->
            merge_fragment_lines(
                NuggetId,
                Rest,
                Nugget,
                Motherlode,
                CumulativeSpec,
                State0
            );
        _ ->
            maybe
                {ok, Key, Value} ?= parse_fragment_line(NuggetId, TrimmedLine),
                {ok, State1} ?= merge_fragment_entry(
                    Key,
                    Value,
                    NuggetId,
                    Nugget,
                    Motherlode,
                    CumulativeSpec,
                    State0
                ),
                merge_fragment_lines(
                    NuggetId,
                    Rest,
                    Nugget,
                    Motherlode,
                    CumulativeSpec,
                    State1
                )
            else
                {error, _} = Error ->
                    Error
            end
    end.

merge_fragment_entry(
    Key,
    Value,
    NuggetId,
    Nugget,
    Motherlode,
    CumulativeSpec,
    State0
) ->
    case maps:get(Key, CumulativeSpec, undefined) of
        undefined ->
            {ok, put_regular(Key, Value, State0)};
        Kind ->
            maybe
                {ok, Tokens} ?= parse_cumulative_tokens(Value),
                {ok, ResolvedTokens} ?= resolve_cumulative_tokens(
                    Tokens,
                    Kind,
                    NuggetId,
                    Nugget,
                    Motherlode
                ),
                {ok, append_cumulative(Key, ResolvedTokens, State0)}
            else
                {error, _} = Error ->
                    Error
            end
    end.

defconfig_fragment_path(NuggetId, Nugget, Flavors) ->
    case maps:get(buildroot, Nugget, undefined) of
        undefined ->
            {ok, undefined};
        Buildroot when is_list(Buildroot) ->
            resolve_fragment_spec(
                NuggetId,
                proplists:get_value(defconfig_fragment, Buildroot, undefined),
                Nugget,
                Flavors
            );
        Invalid ->
            {error, {invalid_buildroot_metadata, NuggetId, Invalid}}
    end.

resolve_fragment_spec(_NuggetId, undefined, _Nugget, _Flavors) ->
    {ok, undefined};
resolve_fragment_spec(_NuggetId, Path, Nugget, _Flavors) when is_binary(Path) ->
    {ok, resolve_fragment_path(Nugget, Path)};
resolve_fragment_spec(
    NuggetId,
    {flavor_map, FlavorEntries},
    Nugget,
    Flavors
) when is_list(FlavorEntries) ->
    case maps:get(NuggetId, Flavors, undefined) of
        undefined ->
            {error, {missing_resolved_flavor, NuggetId}};
        Flavor ->
            resolve_flavor_fragment_path(
                NuggetId,
                Flavor,
                FlavorEntries,
                Nugget
            )
    end;
resolve_fragment_spec(NuggetId, Invalid, _Nugget, _Flavors) ->
    {error, {invalid_defconfig_fragment_spec, NuggetId, Invalid}}.

resolve_flavor_fragment_path(
    _NuggetId,
    Flavor,
    [{Flavor, Path} | _Rest],
    Nugget
) when is_binary(Path) ->
    {ok, resolve_fragment_path(Nugget, Path)};
resolve_flavor_fragment_path(
    NuggetId,
    Flavor,
    [{EntryFlavor, _InvalidPath} | _Rest],
    _Nugget
) when EntryFlavor =:= Flavor ->
    {error, {invalid_defconfig_fragment_spec, NuggetId, {flavor_map, Flavor}}};
resolve_flavor_fragment_path(NuggetId, Flavor, [_Other | Rest], Nugget) ->
    resolve_flavor_fragment_path(NuggetId, Flavor, Rest, Nugget);
resolve_flavor_fragment_path(NuggetId, Flavor, [], _Nugget) ->
    {error, {missing_defconfig_fragment_flavor, NuggetId, Flavor}}.

resolve_fragment_path(Nugget, Path) ->
    PathString = binary_to_list(Path),
    case filename:pathtype(PathString) of
        absolute ->
            Path;
        _ ->
            RepoPath = binary_to_list(maps:get(repo_path, Nugget)),
            NuggetRelpath = binary_to_list(maps:get(nugget_relpath, Nugget)),
            unicode:characters_to_binary(
                filename:join([RepoPath, NuggetRelpath, PathString])
            )
    end.

read_fragment(NuggetId, FragmentPath) ->
    case file:read_file(FragmentPath) of
        {ok, Contents} ->
            {ok, Contents};
        {error, Posix} ->
            {error, {read_defconfig_fragment_failed, NuggetId, FragmentPath, Posix}}
    end.

expand_fragment(NuggetId, Fragment, Substitutions) ->
    expand_fragment(NuggetId, Fragment, Substitutions, []).

expand_fragment(_NuggetId, <<>>, _Substitutions, Acc) ->
    {ok, iolist_to_binary(lists:reverse(Acc))};
expand_fragment(NuggetId, Fragment, Substitutions, Acc) ->
    case binary:match(Fragment, <<"[[">>) of
        nomatch ->
            {ok, iolist_to_binary(lists:reverse([Fragment | Acc]))};
        {Start, _Len} ->
            Prefix = binary:part(Fragment, 0, Start),
            MarkerAndRest = binary:part(
                Fragment,
                Start + 2,
                byte_size(Fragment) - Start - 2
            ),
            case binary:match(MarkerAndRest, <<"]]">>) of
                nomatch ->
                    {error, {unterminated_template_marker, NuggetId}};
                {End, _} ->
                    Marker = binary:part(MarkerAndRest, 0, End),
                    Rest = binary:part(
                        MarkerAndRest,
                        End + 2,
                        byte_size(MarkerAndRest) - End - 2
                    ),
                    case maps:get(Marker, Substitutions, undefined) of
                        undefined ->
                            {error,
                                {unresolved_template_marker,
                                    NuggetId,
                                    Marker}};
                        Value ->
                            expand_fragment(
                                NuggetId,
                                Rest,
                                Substitutions,
                                [Value, Prefix | Acc]
                            )
                    end
            end
    end.

parse_fragment_line(NuggetId, Line) ->
    case binary:split(Line, <<"=">>) of
        [Key, Value] ->
            TrimmedKey = trim_binary(Key),
            case TrimmedKey of
                <<>> ->
                    {error, {invalid_defconfig_line, NuggetId, Line}};
                _ ->
                    {ok, TrimmedKey, trim_binary(Value)}
            end;
        _ ->
            {error, {invalid_defconfig_line, NuggetId, Line}}
    end.

parse_cumulative_tokens(Value) ->
    UnquotedValue = strip_optional_quotes(Value),
    case trim_binary(UnquotedValue) of
        <<>> ->
            {ok, []};
        Trimmed ->
            {ok, re:split(Trimmed, <<"[ \t]+">>, [trim, {return, binary}])}
    end.

resolve_cumulative_tokens([], _Kind, _NuggetId, _Nugget, _Motherlode) ->
    {ok, []};
resolve_cumulative_tokens(
    [Token | Rest],
    Kind,
    NuggetId,
    Nugget,
    Motherlode
) ->
    maybe
        {ok, ResolvedToken} ?= resolve_cumulative_token(
            Token,
            Kind,
            NuggetId,
            Nugget,
            Motherlode
        ),
        {ok, ResolvedRest} ?= resolve_cumulative_tokens(
            Rest,
            Kind,
            NuggetId,
            Nugget,
            Motherlode
        ),
        {ok, [ResolvedToken | ResolvedRest]}
    else
        {error, _} = Error ->
            Error
    end.

resolve_cumulative_token(Token, plain, _NuggetId, _Nugget, _Motherlode) ->
    {ok, Token};
resolve_cumulative_token(Token, path, _NuggetId, Nugget, Motherlode) ->
    case is_absolute_or_runtime_path(Token) of
        true ->
            {ok, Token};
        false ->
            resolve_relative_cumulative_token(Token, Nugget, Motherlode)
    end.

resolve_relative_cumulative_token(<<"@", Rest/binary>>, _Nugget, Motherlode) ->
    case binary:split(Rest, <<"/">>) of
        [TargetNuggetBin, RelativePath] when RelativePath =/= <<>> ->
            TargetNuggetId = binary_to_atom(TargetNuggetBin, utf8),
            case maps:get(TargetNuggetId, maps:get(nuggets, Motherlode), undefined) of
                undefined ->
                    {error, {unknown_nugget_path_reference, TargetNuggetId}};
                TargetNugget ->
                    {ok, motherlode_relative_path(TargetNugget, RelativePath)}
            end;
        _ ->
            {error, {invalid_nugget_path_reference, Rest}}
    end;
resolve_relative_cumulative_token(Token, Nugget, _Motherlode) ->
    {ok, motherlode_relative_path(Nugget, Token)}.

is_absolute_or_runtime_path(<<"/", _/binary>>) ->
    true;
is_absolute_or_runtime_path(<<"$(", _/binary>>) ->
    true;
is_absolute_or_runtime_path(<<"${", _/binary>>) ->
    true;
is_absolute_or_runtime_path(_) ->
    false.

motherlode_relative_path(Nugget, RelativePath) ->
    Repo = atom_to_binary(maps:get(repository, Nugget), utf8),
    NuggetRelpath = maps:get(nugget_relpath, Nugget),
    case NuggetRelpath of
        <<>> ->
            <<<<"${ALLOY_MOTHERLODE}/">>/binary,
                Repo/binary,
                <<"/">>/binary,
                RelativePath/binary>>;
        _ ->
            <<<<"${ALLOY_MOTHERLODE}/">>/binary,
                Repo/binary,
                <<"/">>/binary,
                NuggetRelpath/binary,
                <<"/">>/binary,
                RelativePath/binary>>
    end.

put_regular(Key, Value, State0) ->
    Index = maps:get(next_index, State0) + 1,
    Regular0 = maps:get(regular, State0),
    State0#{
        next_index := Index,
        regular := maps:put(Key, {Index, Value}, Regular0)
    }.

append_cumulative(_Key, [], State0) ->
    State0;
append_cumulative(Key, Values, State0) ->
    Cumulative0 = maps:get(cumulative, State0),
    case maps:get(Key, Cumulative0, undefined) of
        undefined ->
            Index = maps:get(next_index, State0) + 1,
            State0#{
                next_index := Index,
                cumulative := maps:put(Key, {Index, Values}, Cumulative0)
            };
        {Index, ExistingValues} ->
            State0#{
                cumulative := maps:put(
                    Key,
                    {Index, ExistingValues ++ Values},
                    Cumulative0
                )
            }
    end.

inject_target_wrappers(TargetId, State0) ->
    TargetIdBin = atom_to_binary(TargetId, utf8),
    WrapperSpecs = [
        {<<"BR2_ROOTFS_POST_BUILD_SCRIPT">>, <<"post-build.sh">>},
        {<<"BR2_ROOTFS_POST_IMAGE_SCRIPT">>, <<"post-image.sh">>},
        {<<"BR2_ROOTFS_POST_FAKEROOT_SCRIPT">>, <<"post-fakeroot.sh">>}
    ],
    {ok,
        lists:foldl(
            fun({Key, ScriptName}, StateAcc) ->
                WrapperPath =
                    <<<<"$(BR2_EXTERNAL)/board/">>/binary,
                        TargetIdBin/binary,
                        <<"/scripts/">>/binary,
                        ScriptName/binary>>,
                append_cumulative(Key, [WrapperPath], StateAcc)
            end,
            State0,
            WrapperSpecs
        )}.

final_model(State) ->
    #{
        regular => ordered_entries(maps:get(regular, State)),
        cumulative => ordered_cumulative_entries(maps:get(cumulative, State))
    }.

ordered_entries(EntryMap) ->
    [
        {Key, Value}
     || {_Index, Key, Value} <- lists:sort([
            {Index, Key, Value}
         || {Key, {Index, Value}} <- maps:to_list(EntryMap)
        ])
    ].

ordered_cumulative_entries(EntryMap) ->
    [
        {Key, quote_join(Values)}
     || {_Index, Key, Values} <- lists:sort([
            {Index, Key, Values}
         || {Key, {Index, Values}} <- maps:to_list(EntryMap),
            Values =/= []
        ])
    ].

quote_join(Values) ->
    Joined = binary:join(Values, <<" ">>),
    <<<<"\"">>/binary, Joined/binary, <<"\"">>/binary>>.

substitution_values(TargetId, ProductId, Motherlode, Config) ->
    Product = lookup_nugget(ProductId, Motherlode),
    ConfigValues = maps:from_list([
        {Key, Value}
     || {Key, {_Kind, _Origin, Value}} <- maps:to_list(Config)
    ]),
    ProductValues = maps:from_list([
        {<<"ALLOY_PRODUCT">>, atom_to_binary(TargetId, utf8)},
        {<<"ALLOY_PRODUCT_NAME">>, maps:get(name, Product, atom_to_binary(ProductId, utf8))},
        {<<"ALLOY_PRODUCT_DESC">>, maps:get(description, Product, <<>>)},
        {<<"ALLOY_PRODUCT_VERSION">>, maps:get(version, Product, <<>>)}
    ]),
    maps:merge(ConfigValues, ProductValues).

 -spec load_cumulative_key_spec() ->
    {ok, cumulative_key_spec()} | {error, term()}.
load_cumulative_key_spec() ->
    SpecPath = filename:join(priv_dir(), "defconfig-keys.spec"),
    case file:consult(SpecPath) of
        {ok, [Entries]} when is_list(Entries) ->
            normalize_cumulative_key_spec(Entries, #{});
        {ok, [_Other]} ->
            {error, {invalid_defconfig_key_spec, SpecPath, invalid_root}};
        {error, Reason} ->
            {error, {invalid_defconfig_key_spec, SpecPath, Reason}}
    end.

normalize_cumulative_key_spec([], Acc) ->
    {ok, Acc};
normalize_cumulative_key_spec([{Key, Kind} | Rest], Acc0)
  when is_binary(Key), (Kind =:= path orelse Kind =:= plain) ->
    normalize_cumulative_key_spec(Rest, maps:put(Key, Kind, Acc0));
normalize_cumulative_key_spec([{Key, Kind} | Rest], Acc0)
  when is_list(Key), (Kind =:= path orelse Kind =:= plain) ->
    normalize_cumulative_key_spec(
        Rest,
        maps:put(unicode:characters_to_binary(Key), Kind, Acc0)
    );
normalize_cumulative_key_spec(_Entries, _Acc) ->
    {error, invalid_entries}.

priv_dir() ->
    case code:priv_dir(smelterl) of
        {error, bad_name} ->
            BeamDir = filename:dirname(code:which(?MODULE)),
            filename:join([BeamDir, "..", "priv"]);
        Dir ->
            Dir
    end.

lookup_nugget(NuggetId, Motherlode) ->
    maps:get(NuggetId, maps:get(nuggets, Motherlode)).

strip_optional_quotes(<<"\"", Rest/binary>>) ->
    case binary:longest_common_suffix([Rest, <<"\"">>]) of
        1 ->
            binary:part(Rest, 0, byte_size(Rest) - 1);
        _ ->
            <<"\"", Rest/binary>>
    end;
strip_optional_quotes(Value) ->
    Value.

trim_binary(Binary) ->
    trim_trailing_binary(trim_leading_binary(Binary)).

trim_leading_binary(<<Char, Rest/binary>>)
  when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
    trim_leading_binary(Rest);
trim_leading_binary(Binary) ->
    Binary.

trim_trailing_binary(Binary) ->
    trim_trailing_binary(Binary, byte_size(Binary)).

trim_trailing_binary(_Binary, 0) ->
    <<>>;
trim_trailing_binary(Binary, Size) ->
    case binary:at(Binary, Size - 1) of
        Char when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
            trim_trailing_binary(Binary, Size - 1);
        _ ->
            binary:part(Binary, 0, Size)
    end.
