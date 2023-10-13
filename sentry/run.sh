#!/bin/sh
set -ef

sentry_cmd=0
case "$1" in
-* ) sentry_cmd=1 ;;
sentry | */sentry )
    sentry_cmd=1
    shift
;;
esac

if [ "${sentry_cmd}" = 0 ] ; then
    if sed -E '1,/^# commands:/d' "$0" | grep -Fxq -e "$1" ; then
        sentry_cmd=1
    fi
fi

[ "${sentry_cmd}" = 1 ] || exec /ep.sh "$@"

# quirk for "celery" + "dumb-init"
case "$1" in
run )
    case "$2" in
    cron | worker )
        export DUMB_INIT_SETSID=0
    ;;
    esac
;;
esac

exec /ep.sh sentry "$@"

# commands:
