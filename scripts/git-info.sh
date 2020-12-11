#!/usr/bin/env bash

# If a file is given as parameter, the info is writen there
if [[ ! -z "$1" ]]; then
	exec &>"$1"
fi

if git rev-parse 2>/dev/null; then
	git describe --exact-match --tags 2> /dev/null || git rev-parse --short HEAD
	git status --porcelain
fi
