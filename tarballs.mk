#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

SENTRY_REPO_URI          ?= https://github.com/getsentry/sentry
SNUBA_REPO_URI           ?= https://github.com/getsentry/snuba
UWSGI_REPO_URI           ?= https://github.com/unbit/uwsgi
UWSGI_DOGSTATSD_REPO_URI ?= https://github.com/datadog/uwsgi-dogstatsd
LIBRDKAFKA_REPO_URI      ?= https://github.com/confluentinc/librdkafka
PYTHON_XMLSEC_REPO_URI   ?= https://github.com/xmlsec/python-xmlsec
GOOGLE_CRC32C_REPO_URI   ?= https://github.com/google/crc32c

SENTRY_GITREF          ?= $(SENTRY_RELEASE)
SNUBA_GITREF           ?= $(SENTRY_RELEASE)
UWSGI_GITREF           ?= 2.0.22
UWSGI_DOGSTATSD_GITREF ?= e11ace2c535a01c6b5f087effd2afd96254e7431
LIBRDKAFKA_GITREF      ?= v2.2.0
PYTHON_XMLSEC_GITREF   ?= 156394743a0c712e6638fe6e7e300c2f24b4fb12
GOOGLE_CRC32C_GITREF   ?= 1.1.2

$(eval $(call BUILD_IMAGE_ARGS_append , \
	SENTRY_GITREF \
	SNUBA_GITREF \
	UWSGI_GITREF \
	UWSGI_DOGSTATSD_GITREF \
	LIBRDKAFKA_GITREF \
	PYTHON_XMLSEC_GITREF \
	GOOGLE_CRC32C_GITREF \
))

SENTRY_URI          ?= $(SENTRY_REPO_URI)/archive/$(SENTRY_GITREF).tar.gz
SNUBA_URI           ?= $(SNUBA_REPO_URI)/archive/$(SNUBA_GITREF).tar.gz
UWSGI_URI           ?= $(UWSGI_REPO_URI)/archive/$(UWSGI_GITREF).tar.gz
UWSGI_DOGSTATSD_URI ?= $(UWSGI_DOGSTATSD_REPO_URI)/archive/$(UWSGI_DOGSTATSD_GITREF).tar.gz
LIBRDKAFKA_URI      ?= $(LIBRDKAFKA_REPO_URI)/archive/$(LIBRDKAFKA_GITREF).tar.gz
PYTHON_XMLSEC_URI   ?= $(PYTHON_XMLSEC_REPO_URI)/archive/$(PYTHON_XMLSEC_GITREF).tar.gz
GOOGLE_CRC32C_URI   ?= $(GOOGLE_CRC32C_REPO_URI)/archive/$(GOOGLE_CRC32C_GITREF).tar.gz

TARBALLS = \
	sentry \
	snuba \
	uwsgi \
	uwsgi-dogstatsd \
	librdkafka \
	python-xmlsec \
	google-crc32c \

TARBALL_DIR = artifacts
TARBALL_DIRPATH = $(if $(strip $(TARBALL_DIR)),$(strip $(TARBALL_DIR))/)

$(eval $(call versioned_tarball_target , sentry          , $(SENTRY_GITREF)          , $(SENTRY_URI)          ))
$(eval $(call versioned_tarball_target , snuba           , $(SNUBA_GITREF)           , $(SNUBA_URI)           ))
$(eval $(call versioned_tarball_target , uwsgi           , $(UWSGI_GITREF)           , $(UWSGI_URI)           ))
$(eval $(call versioned_tarball_target , uwsgi-dogstatsd , $(UWSGI_DOGSTATSD_GITREF) , $(UWSGI_DOGSTATSD_URI) ))
$(eval $(call versioned_tarball_target , librdkafka      , $(LIBRDKAFKA_GITREF)      , $(LIBRDKAFKA_URI)      ))
$(eval $(call versioned_tarball_target , python-xmlsec   , $(PYTHON_XMLSEC_GITREF)   , $(PYTHON_XMLSEC_URI)   ))
$(eval $(call versioned_tarball_target , google-crc32c   , $(GOOGLE_CRC32C_GITREF)   , $(GOOGLE_CRC32C_URI)   ))

.PHONY: tarballs
tarballs: $(addprefix tarball-,$(strip $(TARBALLS)))
