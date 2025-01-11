#################################################
# Copyright (c) 2024 Noble Factor
# homebridge-image
#############################################

# TODO (DANOBLE) Reference SPDX document that references MIT and Homebridge software terms and conditions.

# REFERENCE
# 1. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
# 2. https://en.wikipedia.org/wiki/ISO_3166-2:US

## PARAMETERS

DOCKER_NAMESPACE := homebridge
DOCKER_REPOSITORY := homebridge
DOCKER_TAG := latest
ISO_SUBDIVISION := ${ISO_SUBDIVISION}

ifndef ISO_SUBDIVISION
    $(error Expected a value for ISO_SUBDIVISION. Example: make new-container ISO_SUBDIVSION=US-WA)
endif

## VARIABLES

export PROJECT_ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
export PROJECT_FILE := $(PROJECT_ROOT)$(DOCKER_REPOSITORY).$(ISO_SUBDIVISION).yml

ifeq ("$(wildcard $(PROJECT_FILE))","")
    $(error Project file for $(ISO_SUBDIVISION) does not exist: $(PROJECT_FILE))
endif

export CERTIFICATES_ROOT := $(PROJECT_ROOT)certificates/$(ISO_SUBDIVISION)
export VOLUME_ROOT := $(PROJECT_ROOT)volumes/$(ISO_SUBDIVISION)
export IMAGE := $(DOCKER_NAMESPACE)/$(DOCKER_REPOSITORY):$(DOCKER_TAG)

docker_compose := sudo IMAGE=$(IMAGE) docker compose -f "$(PROJECT_FILE)"
container_certificates := $(CERTIFICATES_ROOT)/self-signed.csr $(CERTIFICATES_ROOT)/private-key.pem $(CERTIFICATES_ROOT)/public-key.pem

## TARGETS

Get-HomebridgeStatus:
	$(docker_compose) ps --format json | jq .
    
New-Homebridge: $(container_certificates)
	mkdir -p "$(VOLUME_ROOT)/certificates"\
	&& cp --verbose "$(CERTIFICATES_ROOT)/"*.pem "$(VOLUME_ROOT)/certificates"\
	&& $(docker_compose) create --force-recreate --pull always --remove-orphans
	@echo 'Use "make Start-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)" to start Homebridge in $(ISO_SUBDIVISION).'

Restart-Homebridge:
	$(docker_compose) restart
 
Start-Homebridge:
	$(docker_compose) start

New-HomebridgeCertificates: $(CERTIFICATES_ROOT)/certificate-request.conf
	mkdir -p "$(CERTIFICATES_ROOT)"\
	&& cd "$(CERTIFICATES_ROOT)"\
	&& touch private-key.pem\
	&& chmod go-rwx private-key.pem\
	&& openssl req -new -config certificate-request.conf -nodes -out self-signed.csr\
	&& openssl x509 -req -sha256 -days 365 -in self-signed.csr -signkey private-key.pem -out public-key.pem

Update-HomebridgeCertificates: $(container_certificates)
	mkdir -p "$(VOLUME_ROOT)/certificates"\
	&& cp --verbose "$(CERTIFICATES_ROOT)/"*.pem "$(VOLUME_ROOT)/certificates"
	@echo 'Use "make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)" so that Homebridge in $(ISO_SUBDIVISION) picks up the new certificates.'
## Rules

$(CERTIFICATES_ROOT)/self-signed.csr $(CERTIFICATES_ROOT)/private-key.pem $(CERTIFICATES_ROOT)/public-key.pem:
	make new-certificates
