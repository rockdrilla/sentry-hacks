#!/bin/sh
set -f

_find() { find "$1/" -type f ; }
_find_z() { find "$1/" -path "*/$2" -printf '%p\0' ; }
_is_elf() {
    b=$(od -v -A n -t x4 -N 4 < "$1" | tr -d '[:space:]')
    [ "$b" = '464c457f' ]
}
_find_elves() {
    _find "$1" | while read -r n ; do
        [ -n "$n" ] || continue
        _is_elf "$n" || continue
        printf '%s\n' "$n"
    done
}
_xe() { xargs -0r "$@" ; }

elves=$(mktemp)

if [ "${K2_TOOLS:-1}" = 1 ] ; then
    if command -V ufind >/dev/null ; then
        _find() { ufind "$1" ; }
        _find_z() {
            ufind -z "$1" | grep -zF "/$2"
        }
    fi
    if command -V is-elf >/dev/null ; then
        _is_elf() { is-elf "$1" ; }
    fi
    if command -V xvp >/dev/null ; then
        _xe() { xvp "$@" - ; }
    fi

    while : ; do
        command -V ufind >/dev/null || break
        command -V is-elf >/dev/null || break
        command -V xvp >/dev/null || break

        _find_elves() {
            ufind -z "$1" \
            | xvp is-elf -z - \
            | tr '\0' '\n'
        }

        break
    done
fi

p=$(printf '%s' "$1" | sed -E 's#/+$##g')
_find_elves "$p" | sed -e "s#$p/##" > "${elves}"

{
    _find_z "$p/" 'RECORD'      | _xe grep -Fl -f "${elves}"
    _find_z "$p/" 'SOURCES.txt' | _xe grep -Fl -f "${elves}"
} \
| sed -E 's#^.*/([^/]+)\.(egg|dist)-info/[^/]+$#\1#' \
| tr '[:upper:]' '[:lower:]' | sort -uV

rm -f "${elves}"
