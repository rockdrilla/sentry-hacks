#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

set -ef

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
	BUILDER_INTERIM_IMAGE
	UWSGI_INTERIM_IMAGE
	LIBRDKAFKA_INTERIM_IMAGE
	SENTRY_DEPS_INTERIM_IMAGE
	SNUBA_DEPS_INTERIM_IMAGE
	SENTRY_GITREF
	SNUBA_GITREF
	UWSGI_GITREF
	UWSGI_DOGSTATSD_GITREF
	LIBRDKAFKA_GITREF
	SENTRY_ARROYO_GITREF
	PYTHON_XMLSEC_GITREF
	PSYCOPG2_GITREF
"

export BUILD_IMAGE_VOLUMES="
	$(ci_apt_volumes)
	$(build_artifacts_volumes)
"

mkdir -p artifacts
while read -r file uri ; do
	[ -n "${file}" ] || continue
	file="artifacts/${file}"
	[ -s "${file}" ] || curl -Lo "${file}" "${uri}"
done <<-EOF
	sentry-${SENTRY_GITREF}.tar.gz ${SENTRY_URI}
	snuba-${SNUBA_GITREF}.tar.gz   ${SNUBA_URI}

	uwsgi-${UWSGI_GITREF}.tar.gz ${UWSGI_URI}
	uwsgi-dogstatsd-${UWSGI_DOGSTATSD_GITREF}.tar.gz ${UWSGI_DOGSTATSD_URI}

	librdkafka-${LIBRDKAFKA_GITREF}.tar.gz ${LIBRDKAFKA_URI}
	sentry-arroyo-${SENTRY_ARROYO_GITREF}.tar.gz ${SENTRY_ARROYO_URI}
	python-xmlsec-${PYTHON_XMLSEC_GITREF}.tar.gz ${PYTHON_XMLSEC_URI}
	psycopg2-${PSYCOPG2_GITREF}.tar.gz ${PSYCOPG2_URI}
EOF

export BUILDER_INTERIM_IMAGE="${IMAGE_PATH}/sentry-interim-builder:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"
export UWSGI_INTERIM_IMAGE="${IMAGE_PATH}/sentry-interim-uwsgi:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"
export LIBRDKAFKA_INTERIM_IMAGE="${IMAGE_PATH}/sentry-interim-librdkafka:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"
export SENTRY_DEPS_INTERIM_IMAGE="${IMAGE_PATH}/sentry-interim-sentry-deps:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"
export SNUBA_DEPS_INTERIM_IMAGE="${IMAGE_PATH}/sentry-interim-snuba-deps:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"

podman inspect "${BUILDER_INTERIM_IMAGE}" >/dev/null || {
	BUILD_IMAGE_PUSH=0 \
	BUILD_IMAGE_TARGET=builder \
	build-image.sh . "${BUILDER_INTERIM_IMAGE}"
}

podman inspect "${UWSGI_INTERIM_IMAGE}" >/dev/null || {
	BUILD_IMAGE_PUSH=0 \
	BUILD_IMAGE_TARGET=uwsgi \
	build-image.sh . "${UWSGI_INTERIM_IMAGE}"
}

podman inspect "${LIBRDKAFKA_INTERIM_IMAGE}" >/dev/null || {
	BUILD_IMAGE_PUSH=0 \
	BUILD_IMAGE_TARGET=librdkafka \
	build-image.sh . "${LIBRDKAFKA_INTERIM_IMAGE}"
}

podman inspect "${SENTRY_DEPS_INTERIM_IMAGE}" >/dev/null || {
	BUILD_IMAGE_PUSH=0 \
	BUILD_IMAGE_TARGET=sentry-deps \
	build-image.sh . "${SENTRY_DEPS_INTERIM_IMAGE}"
}

podman inspect "${SNUBA_DEPS_INTERIM_IMAGE}" >/dev/null || {
	BUILD_IMAGE_PUSH=0 \
	BUILD_IMAGE_TARGET=snuba-deps \
	build-image.sh . "${SNUBA_DEPS_INTERIM_IMAGE}"
}

BUILD_IMAGE_TARGET=snuba \
build-image.sh . "${IMAGE_PATH}/snuba:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"

BUILD_IMAGE_TARGET=sentry \
build-image.sh . "${IMAGE_PATH}/sentry:${SENTRY_RELEASE}-${PYTHON_VERSION}-${SUITE}${IMAGE_TAG_SUFFIX}"
