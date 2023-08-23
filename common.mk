#!/usr/bin/make -f
# SPDX-License-Identifier: Apache-2.0
# (c) 2023, Konstantin Demin

.NOTPARALLEL:

SHELL       :=/bin/sh
.SHELLFLAGS :=-ec
MAKEFLAGS   +=-Rr --no-print-directory

.PHONY: debug-print-env
debug-print-env:
	@env | sort -V

## HERE_PATH must be defined in top-level Makefile
## HERE_PATH:=$(dir $(realpath $(lastword $(MAKEFILE_LIST))))
export PATH:=$(HERE_PATH).ci:$(PATH)

SOURCE_DATE_EPOCH ?= $(shell date -u '+%s')
BUILD_IMAGE_PUSH ?= 0
export SOURCE_DATE_EPOCH BUILD_IMAGE_PUSH

empty :=
space :=$(empty) $(empty)
comma :=,
xsedx :=$(shell printf '\027')

## $1 - list of variables
define flush_vars=
$(foreach _____v,$(strip $(1)),$(eval unexport $(_____v)))
$(foreach _____v,$(strip $(1)),$(eval override undefine $(_____v)))
endef

## must be '$(eval )'-ed
## $1 - list of variables
define BUILD_IMAGE_ARGS_append=

BUILD_IMAGE_ARGS ?=

BUILD_IMAGE_ARGS += $(strip $(1))

export BUILD_IMAGE_ARGS $(strip $(1))

endef

## $1 - uri
tarball_uri_basename = $(strip $(notdir $(strip $(1))))

## $1 - version/gitref
## $2 - uri
tarball_suffix = $(strip $(word 2,$(subst $(strip $(1)),$(space),_$(call tarball_uri_basename , $(2) ))))

## $1 - name
## $2 - version/gitref
## $3 - uri
tarball_path = $(TARBALL_DIRPATH)$(strip $(1))-$(strip $(2))$(call tarball_suffix , $(2) , $(3) )

## must be '$(eval )'-ed
## $1 - name
## $2 - version/gitref
## $3 - uri
define tarball_target=

$(call tarball_path , $(1) , $(2) , $(3) ):
	mkdir -p '$(dir $(call tarball_path , $(1) , $(2) , $(3) ))' ; \
	curl -Lo '$(call tarball_path , $(1) , $(2) , $(3) )' '$(strip $(3))'

.PHONY: tarball-$(strip $(1))
tarball-$(strip $(1)): $(call tarball_path , $(1) , $(2) , $(3) )

endef

## $1 - host path
## $2 - container path
## $3 - mount options (optional)
build_volume = $(strip $(1)):$(strip $(2))$(if $(strip $(3)),:$(strip $(3)))

## same as "build_volume" but check path presense
## $1 - host path
## $2 - container path
## $3 - mount options (optional)
build_volume_check = $(if $(wildcard $(strip $(1))),$(call build_volume , $(1) , $(2) , $(3) ))

## $1 - name
## $2 - host path
build_context = $(strip $(1))=$(strip $(2))

## same as "build_context" but check path presense
## $1 - name
## $2 - host path
build_context_check = $(if $(wildcard $(strip $(2))),$(call build_context , $(1) , $(2) ))

## $1 - pure image name
## $2 - image tag
## $3 - image tag prefix (may be empty)
generic_image_name = $(strip $(1)):$(if $(strip $(3)),$(strip $(3))-)$(strip $(2))$(if $(strip $(IMAGE_TAG_SUFFIX)),-$(strip $(IMAGE_TAG_SUFFIX)))

## $1 - (relative) image name
generic_fq_image_name = $(IMAGE_PATH)/$(strip $(1))

## $1 - pure image name
## $2 - image tag prefix (may be empty)
image_name = $(call generic_image_name , $(1) , $(IMAGE_TAG) , $(2) )

## $1 - pure image name
## $2 - image tag prefix (may be empty)
fq_image_name = $(call generic_fq_image_name , $(call image_name , $(1) , $(2) ) )

## $1 - Dockerfile target
## $2 - build context specifier (e.g. Dockerfile path)
## $3 - (relative) image name
define image_recipe=
	podman inspect '$(call generic_fq_image_name , $(3) )' > /dev/null || \
	BUILD_IMAGE_TARGET=$(strip $(1)) \
	build-image.sh '$(if $(strip $(2)),$(strip $(2)),.)' '$(call generic_fq_image_name , $(3) )'
endef

## must be '$(eval )'-ed
## $1 - name
## $2 - Dockerfile target
## $3 - build context specifier (e.g. Dockerfile path)
## $4 - (relative) image name
define image_target=

.PHONY: image-$(strip $(1))
image-$(strip $(1)):
	@$(call image_recipe , $(2) , $(3) , $(4) )

endef

## must be '$(eval )'-ed
## $1 - name (also Dockerfile target)
## $2 - build context specifier (e.g. Dockerfile path)
## $3 - pure image name
## $4 - image tag prefix (required to be non-empty)
define interim_image_target=

$(call image_target , interim-$(strip $(1)) , $(1) , $(2) , $(call image_name , $(3) , $(4) ) )

image-interim-$(strip $(1)): BUILD_IMAGE_PUSH=0

endef

## must be '$(eval )'-ed
## $1 - name (also Dockerfile target)
## $2 - build context specifier (e.g. Dockerfile path)
## $3 - (relative) image name
define final_image_target=

$(call image_target , $(1) , $(1) , $(2) , $(3) )

$(call interim_image_target , $(strip $(1))-deps , $(2) ,$(1) , deps )

image-$(strip $(1)): image-interim-$(strip $(1))-deps

endef
