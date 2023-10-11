#!/bin/sh
set -ef

[ $# != 0 ]

unset SOURCE_DATE_EPOCH
python -m compileall -q -j "$(nproc)" --invalidation-mode checked-hash "$@"
