#!/usr/bin/env bash

# argparse.sh - Minimal, robust GNU-like argument parser for Bash 3.2+
#
# Features:
# - Short flags:        -d -ci -o VALUE  and -oVALUE
# - Long options:       --debug, --overlay VALUE, --overlay=VALUE
# - Combined shorts:    -abc (flags may be combined)
# - Terminator:         --   (all following tokens are positional)
# - Defaults:           per-option default value support
# - Presence counters:  for each option, <VAR>_OPT counts occurrences (0 if absent)
# - Storage variable:   per-option destination variable name
# - Cumulative options: values appended in order to an array variable
# - Last-wins:          for non-cumulative, the last occurrence overrides
# - Positional args:    preserved order in POSITIONAL array
# - No external deps:   pure Bash 3.2 compatible (macOS safe)
#
# API
#   args_init                 # reset internal state (call once per script)
#   args_add short long var type [type-specific defaults]
#       short   : single letter short name or '' for no short
#       long    : long name (without --) or '' for no long
#       var     : destination variable name (e.g., ARG_DEBUG)
#       type    : one of 'flag' | 'value' | 'accum'
#
#       Type-specific defaults:
#       - flag  : args_add s long VAR flag <set_when_present> <default_when_absent>
#                 Example: args_add d debug ARG_DEBUG flag 1 0  # sets ARG_DEBUG=1 when provided, else 0
#       - value : args_add s long VAR value <default_value>
#                 Example: args_add s serial ARG_SERIAL value "00000000"
#       - accum : args_add s long VAR accum
#                 (no default; VAR is an array, initialized empty)
#
#   args_parse "$@"          # parse arguments
#   Results:
#       - Variables named by 'var' are exported in caller scope
#       - For 'accum', an array variable with that name is populated in order
#       - Presence counter: for every option, a companion variable <VAR>_OPT is set
#           * Integer count of occurrences (0 if not provided)
#           * For non-cumulative options, >0 simply indicates presence
#       - POSITIONAL array contains remaining args after options
#       - On error, prints message to stderr and returns non-zero

args_init() {
    ARGS_SHORTS=( )
    ARGS_LONGS=( )
    ARGS_VARS=( )
    ARGS_TYPES=( )
    ARGS_DEFAULTS=( )      # for value-type defaults
    ARGS_FLAG_SET=( )      # for flag: value when present
    ARGS_FLAG_DEF=( )      # for flag: value when absent
}

args_add() {
    local short="$1"; shift
    local long="$1"; shift
    local var="$1"; shift
    local type="$1"; shift
    local def_a="$1"; shift || true
    local def_b="$1"; shift || true

    case "$type" in
        flag|value|accum) : ;;
        *) echo "ERROR: args_add: invalid type '$type' for --$long" 1>&2; return 2;;
    esac
    ARGS_SHORTS+=("$short")
    ARGS_LONGS+=("$long")
    ARGS_VARS+=("$var")
    ARGS_TYPES+=("$type")
    if [[ "$type" == "flag" ]]; then
        # def_a = set_when_present, def_b = default_when_absent
        ARGS_FLAG_SET+=("$def_a")
        ARGS_FLAG_DEF+=("$def_b")
        ARGS_DEFAULTS+=("")
    else
        ARGS_DEFAULTS+=("$def_a")
        ARGS_FLAG_SET+=("")
        ARGS_FLAG_DEF+=("")
    fi
}

# --- internal helpers ---

_args_index_by_short() {
    local s="$1"
    local i
    for (( i=0; i<${#ARGS_SHORTS[@]}; i++ )); do
        if [[ "${ARGS_SHORTS[$i]}" == "$s" && -n "$s" ]]; then
            echo "$i"; return 0
        fi
    done
    echo "-1"; return 1
}

_args_index_by_long() {
    local l="$1"
    local i
    for (( i=0; i<${#ARGS_LONGS[@]}; i++ )); do
        if [[ "${ARGS_LONGS[$i]}" == "$l" && -n "$l" ]]; then
            echo "$i"; return 0
        fi
    done
    echo "-1"; return 1
}

_args_set_default_if_unset() {
    local i var type defv
    for (( i=0; i<${#ARGS_VARS[@]}; i++ )); do
        var="${ARGS_VARS[$i]}"
        type="${ARGS_TYPES[$i]}"
        case "$type" in
            flag)
                if [[ -z "${!var+x}" ]]; then
                    eval "$var=\"${ARGS_FLAG_DEF[$i]}\""
                fi
                ;;
            value)
                defv="${ARGS_DEFAULTS[$i]}"
                if [[ -z "${!var+x}" ]]; then
                    eval "$var=\"$defv\""
                fi
                ;;
            accum)
                # ensure array exists without overwriting an existing one
                if [[ -z "${!var+x}" ]]; then
                    eval "$var=()"
                fi
                ;;
        esac
    done
}

_args_assign_value() {
    local i="$1"; shift
    local val="$1"; shift
    local var="${ARGS_VARS[$i]}"
    local type="${ARGS_TYPES[$i]}"
    local seen_var="${var}_OPT"
    case "$type" in
        flag)
            eval "$var=\"${ARGS_FLAG_SET[$i]}\""
            local __count
            eval "__count=\${$seen_var:-0}"
            __count=$(( __count + 1 ))
            eval "$seen_var=$__count"
            ;;
        value)
            eval "$var=\"$val\""
            local __count
            eval "__count=\${$seen_var:-0}"
            __count=$(( __count + 1 ))
            eval "$seen_var=$__count"
            ;;
        accum)
            # append preserving order
            eval "$var+=(\"$val\")"
            local __count
            eval "__count=\${$seen_var:-0}"
            __count=$(( __count + 1 ))
            eval "$seen_var=$__count"
            ;;
    esac
}

args_parse() {
    POSITIONAL=( )
    local argv=("$@")
    local i=0
    local token
    local stop_opts=false

    # initialize presence flags to 0
    local __pi
    for (( __pi=0; __pi<${#ARGS_VARS[@]}; __pi++ )); do
        eval "${ARGS_VARS[$__pi]}_OPT=0"
    done

    while [[ $i -lt ${#argv[@]} ]]; do
        token="${argv[$i]}"
        if [[ "$stop_opts" == true ]]; then
            POSITIONAL+=("$token"); i=$((i+1)); continue
        fi

        if [[ "$token" == "--" ]]; then
            stop_opts=true; i=$((i+1)); continue
        fi

        if [[ "$token" == --* ]]; then
            # Long option
            local name val has_eq
            name="${token#--}"
            has_eq=false
            if [[ "$name" == *=* ]]; then
                val="${name#*=}"
                name="${name%%=*}"
                has_eq=true
            else
                val=""
            fi
            local idx
            idx=$(_args_index_by_long "$name") || idx=-1
            if [[ $idx -lt 0 ]]; then
                echo "ERROR: Unknown option --$name" 1>&2; return 2
            fi
            local type="${ARGS_TYPES[$idx]}"
            if [[ "$type" == "flag" ]]; then
                if [[ "$has_eq" == true ]]; then
                    echo "ERROR: Option --$name does not take a value" 1>&2; return 2
                fi
                _args_assign_value "$idx" "1"
            else
                if [[ "$has_eq" == false ]]; then
                    i=$((i+1))
                    if [[ $i -ge ${#argv[@]} ]]; then
                        echo "ERROR: Option --$name requires a value" 1>&2; return 2
                    fi
                    val="${argv[$i]}"
                fi
                _args_assign_value "$idx" "$val"
            fi
            i=$((i+1)); continue
        fi

        if [[ "$token" == -* && "$token" != "-" ]]; then
            # Short(s)
            local shorts="${token#-}"
            local pos=0
            local ch idx type rest
            while [[ $pos -lt ${#shorts} ]]; do
                ch="${shorts:$pos:1}"
                idx=$(_args_index_by_short "$ch") || idx=-1
                if [[ $idx -lt 0 ]]; then
                    echo "ERROR: Unknown option -$ch" 1>&2; return 2
                fi
                type="${ARGS_TYPES[$idx]}"
                if [[ "$type" == "flag" ]]; then
                    _args_assign_value "$idx" "1"
                    pos=$((pos+1))
                else
                    # option expects a value: use remainder of token or next argv
                    rest="${shorts:$((pos+1))}"
                    local val
                    if [[ -n "$rest" ]]; then
                        val="$rest"
                        pos=${#shorts}
                    else
                        i=$((i+1))
                        if [[ $i -ge ${#argv[@]} ]]; then
                            echo "ERROR: Option -$ch requires a value" 1>&2; return 2
                        fi
                        val="${argv[$i]}"
                        pos=${#shorts}
                    fi
                    _args_assign_value "$idx" "$val"
                fi
            done
            i=$((i+1)); continue
        fi

        # Positional
        POSITIONAL+=("$token")
        i=$((i+1))
    done

    _args_set_default_if_unset
}
