#!/usr/bin/env bash

set -e

SCRIPT_NAME="$( basename $0 )"

show_usage()
{
	echo "USAGE: ${SCRIPT_NAME} [-h] [-d] [-c DIR] [-o OUTPUT_FILE]"
	echo "OPTIONS:"
	echo " -h      Display this"
	echo " -d      Show details of the current changes of the repository"
	echo " -c DIR  First move to the specified directory"
	echo " -o FILE Write the output to given file"
	echo
}

# Parse script's arguments
OPTIND=1
ARG_DETAILS=false
ARG_MOVE_TO=""
ARG_OUTPUT_TO="-"
while getopts "hdc:o:" opt; do
    case "$opt" in
    d)
        ARG_DETAILS=true
        ;;
    c)
        ARG_MOVE_TO="$OPTARG"
        if [[ ! -d $ARG_MOVE_TO ]]; then
        	echo "$SCRIPT_NAME: ERROR: Cannot move to missing directory $ARG_MOVE_TO"
        	exit 1
        fi
        ;;
    o)
        ARG_OUTPUT_TO="$OPTARG"
        ;;
    *)
        show_usage
        exit 0
        ;;
    esac
done
shift $((OPTIND-1))
[[ "${1:-}" == "--" ]] && shift

if [[ ! -z $ARG_OUTPUT_TO ]] && [[ $ARG_OUTPUT_TO != "-" ]]; then
	mkdir -p $( dirname "$ARG_OUTPUT_TO" )
	exec &> "$ARG_OUTPUT_TO"
fi

if [[ ! -z $ARG_MOVE_TO ]]; then
	cd "$ARG_MOVE_TO"
fi

if git rev-parse 2>/dev/null; then
	git describe --exact-match --tags 2> /dev/null || git rev-parse --short HEAD
	if [[ $ARG_DETAILS == true ]]; then
		git status --porcelain
	fi
fi
