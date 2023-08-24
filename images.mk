#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

IMAGE_TAG = $(SENTRY_RELEASE)-$(PYTHON_VERSION)-$(SUITE)

FINAL_IMAGES = sentry snuba
INTERIM_IMAGES = \
	builder \
	uwsgi \
	librdkafka \
	$(addsuffix -deps,$(strip $(FINAL_IMAGES)))

IMAGES = $(FINAL_IMAGES) $(addprefix interim-,$(strip $(INTERIM_IMAGES)))

.PHONY: images
images: $(addprefix image-,$(strip $(IMAGES)))

## explicit ordering
image-interim-uwsgi: \
  $(addprefix tarball-,uwsgi uwsgi-dogstatsd) \
  image-interim-builder
image-interim-librdkafka: \
  $(addprefix tarball-,librdkafka) \
  image-interim-builder
image-interim-sentry-deps: \
  $(addprefix tarball-,sentry python-xmlsec google-crc32c) \
  $(addprefix image-interim-,builder uwsgi librdkafka)
image-interim-snuba-deps: \
  $(addprefix tarball-,snuba) \
  $(addprefix image-interim-,builder uwsgi librdkafka)

$(eval $(call final_image_target , sentry , , $(call image_name , sentry , ) ))
$(eval $(call final_image_target , snuba  , , $(call image_name , snuba , ) ))

$(eval $(call interim_image_target , builder , , sentry , builder ))
$(eval $(call interim_image_target , uwsgi , , sentry , uwsgi ))
$(eval $(call interim_image_target , librdkafka , , sentry , librdkafka ))

BUILDER_INTERIM_IMAGE     :=$(call fq_image_name , sentry , builder )
UWSGI_INTERIM_IMAGE       :=$(call fq_image_name , sentry , uwsgi )
LIBRDKAFKA_INTERIM_IMAGE  :=$(call fq_image_name , sentry , librdkafka )
SENTRY_DEPS_INTERIM_IMAGE :=$(call fq_image_name , sentry , deps )
SNUBA_DEPS_INTERIM_IMAGE  :=$(call fq_image_name , snuba  , deps )

$(eval $(call BUILD_IMAGE_ARGS_append , \
	BUILDER_INTERIM_IMAGE \
	UWSGI_INTERIM_IMAGE \
	LIBRDKAFKA_INTERIM_IMAGE \
	SENTRY_DEPS_INTERIM_IMAGE \
	SNUBA_DEPS_INTERIM_IMAGE \
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

ci_volumes = \
	$(ci_apt_volumes) \
	$(ci_python_volumes) \
	$(ci_nodejs_volumes) \

export BUILD_IMAGE_CONTEXTS:=$(strip \
	$(artifacts_contexts) \
)
## TODO: remove $(artifacts_volumes) from final/interim images (to avoid spoiling layers)
export BUILD_IMAGE_VOLUMES:=$(strip \
	$(ci_volumes) \
	$(artifacts_volumes) \
)
