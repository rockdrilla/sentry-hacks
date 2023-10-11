#!/bin/sh
set -ef

pip list --exclude-editable --format json \
| jq -r '.[] | .name+"=="+.version' \
| tr '[:upper:]' '[:lower:]' | sort -V
