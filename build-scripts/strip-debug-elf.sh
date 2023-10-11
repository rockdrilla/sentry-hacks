#!/bin/sh
set -ef

[ $# != 0 ]

t=$(mktemp)
list-elf.sh "$@" > "$t"
strip-debug-elf-list.sh "$t"
rm -f "$t"
