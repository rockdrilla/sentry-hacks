#!/bin/sh
set -ef

[ $# -ge 1 ]

sed -En '/^\s*(#|$)/d;s/^\s*([a-zA-Z_][^<>~=!]+).*$/\1/p' "$@"
