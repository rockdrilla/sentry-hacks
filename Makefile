#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

.DEFAULT: all
.PHONY: all
all: images

HERE_PATH:=$(dir $(realpath $(lastword $(MAKEFILE_LIST))))

include $(HERE_PATH)common.mk

SENTRY_RELEASE ?= 22.10.0
PYTHON_VERSION ?= 3.11
DISTRO         ?= debian
SUITE          ?= bookworm
IMAGE_PATH     ?= docker.io/rockdrilla

$(eval $(call BUILD_IMAGE_ARGS_append , \
	SENTRY_RELEASE \
	PYTHON_VERSION \
	DISTRO SUITE \
	IMAGE_PATH \
))

include $(HERE_PATH)tarballs.mk

include $(HERE_PATH)images.mk

## shortcuts
.PHONY: sentry snuba
sentry: image-sentry
snuba:  image-snuba
