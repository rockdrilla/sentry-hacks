#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

set -f

# the one may want to set this:
# : "${BUILDAH_FORMAT:=docker}"
# export BUILDAH_FORMAT

rootdir=$(readlink -e "$(dirname "$0")")
cd "${rootdir:?}" || exit

. "${rootdir}/.ci/common.envsh"
set -a
. "${rootdir}/common.envsh"
set +a

export BUILD_IMAGE_ARGS="${BUILD_IMAGE_ARGS}
	PYTHON_VERSION
	SENTRY_RELEASE
"

export BUILD_IMAGE_VOLUMES="
	$(ci_apt_volumes)
	$(build_artifacts_volumes)
"
