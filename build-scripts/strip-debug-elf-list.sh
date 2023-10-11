#!/bin/sh
set -ef

[ -n "$1" ]
[ -f "$1" ]

xvp ls --block-size=K -l "$1"
xvp strip --strip-debug "$1" ; echo
xvp ls --block-size=K -l "$1"
