#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

SENTRY_REPO_URI          ?= https://github.com/getsentry/sentry
SNUBA_REPO_URI           ?= https://github.com/getsentry/snuba
UWSGI_REPO_URI           ?= https://github.com/unbit/uwsgi
UWSGI_DOGSTATSD_REPO_URI ?= https://github.com/datadog/uwsgi-dogstatsd
LIBRDKAFKA_REPO_URI      ?= https://github.com/confluentinc/librdkafka
SENTRY_ARROYO_REPO_URI   ?= https://github.com/getsentry/arroyo
PYTHON_XMLSEC_REPO_URI   ?= https://github.com/xmlsec/python-xmlsec

SENTRY_GITREF          ?= $(SENTRY_RELEASE)
SNUBA_GITREF           ?= $(SENTRY_RELEASE)
UWSGI_GITREF           ?= 2.0.22
UWSGI_DOGSTATSD_GITREF ?= e11ace2c535a01c6b5f087effd2afd96254e7431
LIBRDKAFKA_GITREF      ?= v2.2.0
SENTRY_ARROYO_GITREF   ?= 0.1.1
PYTHON_XMLSEC_GITREF   ?= 156394743a0c712e6638fe6e7e300c2f24b4fb12

$(eval $(call BUILD_IMAGE_ARGS_append , \
	SENTRY_GITREF \
	SNUBA_GITREF \
	UWSGI_GITREF \
	UWSGI_DOGSTATSD_GITREF \
	LIBRDKAFKA_GITREF \
	SENTRY_ARROYO_GITREF \
	PYTHON_XMLSEC_GITREF \
))

SENTRY_URI          ?= $(SENTRY_REPO_URI)/archive/$(SENTRY_GITREF).tar.gz
SNUBA_URI           ?= $(SNUBA_REPO_URI)/archive/$(SNUBA_GITREF).tar.gz
UWSGI_URI           ?= $(UWSGI_REPO_URI)/archive/$(UWSGI_GITREF).tar.gz
UWSGI_DOGSTATSD_URI ?= $(UWSGI_DOGSTATSD_REPO_URI)/archive/$(UWSGI_DOGSTATSD_GITREF).tar.gz
LIBRDKAFKA_URI      ?= $(LIBRDKAFKA_REPO_URI)/archive/$(LIBRDKAFKA_GITREF).tar.gz
SENTRY_ARROYO_URI   ?= $(SENTRY_ARROYO_REPO_URI)/archive/$(SENTRY_ARROYO_GITREF).tar.gz
PYTHON_XMLSEC_URI   ?= $(PYTHON_XMLSEC_REPO_URI)/archive/$(PYTHON_XMLSEC_GITREF).tar.gz

TARBALLS = \
	sentry \
	snuba \
	uwsgi \
	uwsgi-dogstatsd \
	librdkafka \
	sentry-arroyo \
	python-xmlsec \

TARBALL_DIR = artifacts
TARBALL_DIRPATH = $(if $(strip $(TARBALL_DIR)),$(strip $(TARBALL_DIR))/)

$(eval $(call tarball_target , sentry          , $(SENTRY_GITREF)          , $(SENTRY_URI)          ))
$(eval $(call tarball_target , snuba           , $(SNUBA_GITREF)           , $(SNUBA_URI)           ))
$(eval $(call tarball_target , uwsgi           , $(UWSGI_GITREF)           , $(UWSGI_URI)           ))
$(eval $(call tarball_target , uwsgi-dogstatsd , $(UWSGI_DOGSTATSD_GITREF) , $(UWSGI_DOGSTATSD_URI) ))
$(eval $(call tarball_target , librdkafka      , $(LIBRDKAFKA_GITREF)      , $(LIBRDKAFKA_URI)      ))
$(eval $(call tarball_target , sentry-arroyo   , $(SENTRY_ARROYO_GITREF)   , $(SENTRY_ARROYO_URI)   ))
$(eval $(call tarball_target , python-xmlsec   , $(PYTHON_XMLSEC_GITREF)   , $(PYTHON_XMLSEC_URI)   ))

.PHONY: tarballs
tarballs: $(addprefix tarball-,$(strip $(TARBALLS)))
