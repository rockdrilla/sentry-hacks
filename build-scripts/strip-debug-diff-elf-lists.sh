#!/bin/sh
set -ef

[ $# -ge 2 ]
[ -n "$1" ]
[ -f "$1" ]

slist="$1"
shift

tlist=$(mktemp)
list-elf.sh "$@" > "${tlist}"

if [ -s "${slist}" ] ; then
    tfilt=$(mktemp)
    tr '\0' '\n' < "${slist}" > "${tfilt}"
    telves=$(mktemp)
    grep -zFvx -f "${tfilt}" "${tlist}" > "${telves}" || :
    cat < "${telves}" > "${tlist}"
    rm -f "${tfilt}" "${telves}"
fi

strip-debug-elf-list.sh "${tlist}"
rm -f -- "${slist}" "${tlist}"
