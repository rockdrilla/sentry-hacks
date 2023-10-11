#!/bin/sh
set -ef

[ $# != 0 ]

ufind -z "$@" | xvp is-elf -z - | sort -zuV
