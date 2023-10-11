#!/bin/sh
set -ef

[ -n "$1" ]
[ -n "$2" ]
[ -f "$2" ]
[ -s "$2" ]

dst="$1"
slist="$2"
shift 2

tlist=$(mktemp)
apt-list-installed > "${tlist}"

tdst=$(mktemp)
grep -Fvx -f "${slist}" "${tlist}" > "${tdst}" || :
sort -uV -- "${tdst}" "$@" > "${dst}"

rm -f -- "${tlist}" "${tdst}" "${slist}" "$@"
