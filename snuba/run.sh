#!/bin/sh
set -ef

snuba_cmd=0
case "$1" in
-* ) snuba_cmd=1 ;;
snuba | */snuba )
    snuba_cmd=1
    shift
;;
esac

if [ "${snuba_cmd}" = 0 ] ; then
    if sed -E '1,/^# commands:/d' "$0" | grep -Fxq -e "$1" ; then
        snuba_cmd=1
    fi
fi

[ "${snuba_cmd}" = 1 ] || exec /ep.sh "$@"

# quirk for "celery" + "dumb-init"
case "$1" in
subscriptions-executor | subscriptions-scheduler | subscriptions-scheduler-executor )
    export DUMB_INIT_SETSID=0
;;
esac

exec /ep.sh snuba "$@"

# commands:
