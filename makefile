#################################################
# Copyright (c) 2024 Noble Factor
# homebridge-image
#############################################

# TODO (DANOBLE) Reference SPDX document that references MIT and Homebridge software terms and conditions.

# REFERENCE
# 1. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
# 2. https://en.wikipedia.org/wiki/ISO_3166-2:US

## Variables

DOCKER_NAMESPACE = homebridge
DOCKER_REPOSITORY = homebridge
DOCKER_TAG = latest
ISO_SUBDIVISION =

ifndef ISO_SUBDIVISION
    $(error Expected a value for ISO_SUBDIVISION. Example: make new-container ISO_SUBDIVSION=US-WA)
endif

export PROJECT_ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
export PROJECT_FILE := $(PROJECT_ROOT)$(DOCKER_REPOSITORY).$(ISO_SUBDIVISION).yml

ifeq ("$(wildcard $(PROJECT_FILE))","")
    $(error Project file for $(ISO_SUBDIVISION) does not exist: $(PROJECT_FILE))
endif

export CERTIFICATES_ROOT := $(PROJECT_ROOT)certificates/$(ISO_SUBDIVISION)
export VOLUME_ROOT := $(PROJECT_ROOT)volumes/$(ISO_SUBDIVISION)
export IMAGE := $(DOCKER_NAMESPACE)/$(DOCKER_REPOSITORY):$(DOCKER_TAG)

## Targets

new-container: $(CERTIFICATES_ROOT)/certficate-request.conf $(CERTIFICATES_ROOT)/self-signed.csr $(CERTIFICATES_ROOT)/private-key.pem $(CERTIFICATES_ROOT)/public-key.pem
	mkdir -p "$(VOLUME_ROOT)/certificates"\
	&& cp "$(CERTIFICATES_ROOT)/"*.pem "$(VOLUME_ROOT)/certificates"\
	&& docker compose -f "$(PROJECT_FILE)" create

start-container:
	docker compose -f "$(PROJECT_FILE)" start

new-certificates:
	mkdir -p "certifcates/$(ISO_SUBDIVISION)"\
	&& cd "certifcates/$(ISO_SUBDIVISION)"\
	&& touch private-key.pem\
	&& chmod go-rwx private-key.pem\
	&& openssl req -new -config certficate-request.conf -nodes -out self-signed.csr -quiet\
	&& openssl x509 -req -sha256 -days 365 -in self-signed.csr -signkey private-key.pem -out public-key.pem

## Rules

$(CERTIFICATES_ROOT)/self-signed.csr $(CERTIFICATES_ROOT)/private-key.pem $(CERTIFICATES_ROOT)/public-key.pem:
	make new-certificates
