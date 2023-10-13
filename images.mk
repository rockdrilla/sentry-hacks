#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

IMAGE_TAG = $(SENTRY_RELEASE)-$(PYTHON_VERSION)-$(SUITE)

FINAL_IMAGES = sentry snuba
INTERIM_IMAGES = \
	builder \
	uwsgi \
	librdkafka \
	common \
	sentry-wheels \
	snuba-wheels \
	$(addsuffix -deps,common $(strip $(FINAL_IMAGES)))

BUILDER_IMAGES = $(filter-out common,$(INTERIM_IMAGES))

IMAGES = $(FINAL_IMAGES) $(addprefix interim-,$(strip $(INTERIM_IMAGES)))

.PHONY: images
images: $(addprefix image-,$(strip $(IMAGES)))

## explicit ordering
image-snuba: \
  image-interim-snuba-wheels \
  image-interim-common
image-sentry: \
  image-interim-sentry-wheels \
  image-interim-common
image-interim-uwsgi: \
  $(addprefix tarball-,uwsgi uwsgi-dogstatsd) \
  image-interim-builder
image-interim-librdkafka: \
  $(addprefix tarball-,librdkafka) \
  image-interim-builder
image-interim-common-deps: \
  $(addprefix image-interim-,builder uwsgi librdkafka)
image-interim-common: \
  image-interim-common-deps
image-interim-sentry-deps: \
  $(addprefix tarball-,sentry python-xmlsec google-crc32c) \
  $(addprefix image-interim-,common-deps)
image-interim-snuba-deps: \
  $(addprefix tarball-,snuba) \
  $(addprefix image-interim-,common-deps)
image-interim-sentry-wheels: \
  image-interim-sentry-deps
image-interim-snuba-wheels: \
  image-interim-snuba-deps

$(eval $(call final_image_target , sentry , , $(call image_name , sentry , ) ))
$(eval $(call final_image_target , snuba  , , $(call image_name , snuba , ) ))

$(eval $(call interim_image_target , builder , , sentry , builder ))
$(eval $(call interim_image_target , uwsgi , , sentry , uwsgi ))
$(eval $(call interim_image_target , librdkafka , , sentry , librdkafka ))
$(eval $(call interim_image_target , common-deps , , sentry , common-deps ))
$(eval $(call interim_image_target , common , , sentry , common ))
$(eval $(call interim_image_target , sentry-wheels , , sentry , wheels ))
$(eval $(call interim_image_target , snuba-wheels , , snuba , wheels ))

BUILDER_INTERIM_IMAGE     :=$(call fq_image_name , sentry , builder )
UWSGI_INTERIM_IMAGE       :=$(call fq_image_name , sentry , uwsgi )
LIBRDKAFKA_INTERIM_IMAGE  :=$(call fq_image_name , sentry , librdkafka )
COMMON_DEPS_INTERIM_IMAGE :=$(call fq_image_name , sentry , common-deps )
COMMON_INTERIM_IMAGE      :=$(call fq_image_name , sentry , common )
SENTRY_DEPS_INTERIM_IMAGE :=$(call fq_image_name , sentry , deps )
SENTRY_WHL_INTERIM_IMAGE  :=$(call fq_image_name , sentry , wheels )
SNUBA_DEPS_INTERIM_IMAGE  :=$(call fq_image_name , snuba  , deps )
SNUBA_WHL_INTERIM_IMAGE   :=$(call fq_image_name , snuba  , wheels )

$(eval $(call BUILD_IMAGE_ARGS_append , \
	BUILDER_INTERIM_IMAGE \
	UWSGI_INTERIM_IMAGE \
	LIBRDKAFKA_INTERIM_IMAGE \
	COMMON_DEPS_INTERIM_IMAGE \
	COMMON_INTERIM_IMAGE \
	SENTRY_DEPS_INTERIM_IMAGE \
	SENTRY_WHL_INTERIM_IMAGE \
	SNUBA_DEPS_INTERIM_IMAGE \
	SNUBA_WHL_INTERIM_IMAGE \
))

## HERE_PATH must be defined in top-level Makefile
## HERE_PATH:=$(dir $(realpath $(lastword $(MAKEFILE_LIST))))
artifacts_path = $(HERE_PATH)artifacts
ci_path        = $(HERE_PATH).ci

artifacts_volumes = $(call build_volume , $(artifacts_path) , /run/artifacts , )

artifacts_contexts = $(call build_context , artifacts , $(artifacts_path) , )

ci_apt_volumes = \
	$(call build_volume_check , $(ci_path)/apt.list.$(SUITE)    , /etc/apt/sources.list , ro ) \
	$(call build_volume_check , $(ci_path)/apt.sources.$(SUITE) , /etc/apt/sources.list.d/$(SUITE).sources , ro ) \

ci_python_volumes = \
	$(call build_volume_check , $(ci_path)/pip.conf , /etc/pip.conf , ro ) \

ci_nodejs_volumes = \
	$(call build_volume_check , $(ci_path)/npmrc  , /etc/npmrc , ro ) \
	$(call build_volume_check , $(ci_path)/yarnrc , /etc/yarnrc , ro ) \

export BUILD_IMAGE_CONTEXTS:=$(strip \
	$(artifacts_contexts) \
)
export BUILD_IMAGE_VOLUMES:=$(strip \
	$(ci_apt_volumes) \
)

interim_BUILD_IMAGE_VOLUMES:=$(strip $(BUILD_IMAGE_VOLUMES) $(ci_python_volumes) $(ci_nodejs_volumes) $(artifacts_volumes))

$(addprefix image-interim-,$(strip $(BUILDER_IMAGES))): BUILD_IMAGE_VOLUMES=$(interim_BUILD_IMAGE_VOLUMES)
