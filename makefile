########################################################################################################################
# Copyright (c) 2024 Noble Factor
# homebridge-base_image
########################################################################################################################

# TODO (david-noble) Reference SPDX document that references MIT and Homebridge software terms and conditions.
# TODO (david-noble) Enable multi-platform builds as an option by adding a step to detect and create a multi-platform builder (See reference 3)

define USAGE

NAME
    make - Manage Homebridge deployment for $(ISO_SUBDIVISION)

SYNOPSIS
    make <target> ISO_SUBDIVISION=CC-SS [VAR=VALUE ...]

REQUIRED
    ISO_SUBDIVISION  ISO 3166-2 subdivision code (e.g., US-WA)
                     This value is computed from the docker host's geo-location, if it's not assigned.

OPTIONAL
    STAGE                Deployment stage: dev (default), test, prod
    NOBLEFACTOR_VERSION  Image tag for noblefactor/homebridge (default: preview.2)
    HOMEBRIDGE_VERSION   Upstream Homebridge version (default: latest)
    HOSTNAME             Override container hostname
    NETWORK_NAME         Override Docker network name

TARGETS
    New-Homebridge                 Build image, create network, and create container
    Start-Homebridge               Start container
    Stop-Homebridge                Stop container
    Restart-Homebridge             Restart container
    Get-HomebridgeStatus           Show compose status (JSON)
    Start-HomebridgeShell          Open an interactive shell in the container
    New-HomebridgeCertificates     Generate self-signed certificates
    Update-HomebridgeCertificates  Copy certificates into container volume
    Update-HomebridgeRcloneConf    Copy rclone.conf into container volume
    clean                          Stop, remove network, prune system, and clear volumes
    help                           Show this help

EXAMPLES
    make New-Homebridge ISO_SUBDIVISION=US-WA
    make Start-Homebridge ISO_SUBDIVISION=US-WA
    make Update-HomebridgeCertificates ISO_SUBDIVISION=US-WA
    make Get-HomebridgeStatus ISO_SUBDIVISION=US-WA
    make clean ISO_SUBDIVISION=US-WA

REFERENCE
    1. https://docs.docker.com/build/building/multi-platform/
    2. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
    3. https://en.wikipedia.org/wiki/ISO_3166-2:US

endef

export USAGE

SHELL := /bin/bash

## PARAMETERS

NOBLEFACTOR_VERSION := preview.2
HOMEBRIDGE_VERSION := latest

ifeq ($(strip $(ISO_SUBDIVISION)),)
    ISO_SUBDIVISION = $(shell curl --no-progress-meter "http://ip-api.com/json?fields=countryCode,region" | jq --raw-output '"\(.countryCode)-\(.region)"')
endif

ifeq ($(strip $(STAGE)),)
	STAGE := dev
else ifeq ($(STAGE),prod)
	stage :=
else
	stage := -$(STAGE)
endif

## VARIABLES

docker_compose = sudo ISO_SUBDIVISION="$(ISO_SUBDIVISION)" NETWORK_NAME="$(network_name)" HOSTNAME="$(container_hostname)" NOBLEFACTOR_VERSION="$(NOBLEFACTOR_VERSION)" docker compose -f "$(project_file)"

### PATHS

project_root := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
project_name := homebridge
project_file := $(project_root)$(project_name).$(ISO_SUBDIVISION).yaml

ifeq ("$(wildcard $(project_file))","")
    $(error Project file for $(ISO_SUBDIVISION) does not exist: $(project_file))
endif

### RCLONE

rclone_conf_root := $(project_root)secrets/rclone
rclone_conf_file:= $(rclone_conf_root)/rclone.conf

### SECRETS

certificates_root := $(project_root)secrets/certificates/$(ISO_SUBDIVISION)

certificates := \
	$(certificates_root)/self-signed.csr\
	$(certificates_root)/private-key.pem\
	$(certificates_root)/public-key.pem

### CONTAINER VOLUMES

volume_root := $(project_root)volumes/$(ISO_SUBDIVISION)

container_backups := $(volume_root)/backups

container_certificates := \
	$(volume_root)/.config/certificates/self-signed.csr\
	$(volume_root)/.config/certificates/private-key.pem\
	$(volume_root)/.config/certificates/public-key.pem

container_rclone_conf_file:= \
	$(volume_root)/.config/rclone/rclone.conf

### NETWORK

container_hostname := $(project_name)-$(ISO_SUBDIVISION)$(stage)

network_device := $(shell if [[ $${OSTYPE} == linux-gnu* ]]; then echo eth0; elif [[ $${OSTYPE} == darwin* ]]; then scutil --dns | gawk '/if_index/ { print gensub(/[()]/, "", "g", $$4); exit }'; else echo nul; fi)
network_driver := $(shell if [[ $${OSTYPE} == linux-gnu* ]]; then echo "macvlan"; else echo "bridge"; fi)
network_name := $(project_name):$(network_device)

## TARGETS

help:
	@echo "$$USAGE"

clean:
	make Stop-Homebridge\
	&& sudo docker network rm --force $(network_name) || true\
	&& sudo docker system prune --force --all\
	&& sudo docker volume prune --force --all\
	&& sudo rm -rfv volumes/*\

Get-HomebridgeStatus:
	$(docker_compose) ps --format json --no-trunc | jq .

New-Homebridge: $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf_file)
	sudo docker buildx build --build-arg homebridge_version=$(HOMEBRIDGE_VERSION) --load --progress=plain --tag=noblefactor/homebridge:$(NOBLEFACTOR_VERSION) . \
	&& New-DockerNetwork --device $(network_device) --driver $(network_driver) $(project_name) \
	&& $(docker_compose) create --force-recreate --pull never --remove-orphans
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Start Homebridge in $(ISO_SUBDIVISION): make Start-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

Restart-Homebridge:
	$(docker_compose) restart\
	&& make Get-HomebridgeStatus
 
Start-Homebridge:
	$(docker_compose) start\
	&& make Get-HomebridgeStatus

Start-HomebridgeShell:
	sudo docker exec --interactive --tty homebridge.US-WA /bin/bash

Stop-Homebridge:
	$(docker_compose) stop\
	&& make Get-HomebridgeStatus 

New-HomebridgeCertificates: $(certificates_root)/certificate-request.conf
	cd "$(certificates_root)"\
	&& openssl req -new -config certificate-request.conf -nodes -out self-signed.csr\
	&& openssl x509 -req -sha256 -days 365 -in self-signed.csr -signkey private-key.pem -out public-key.pem

Update-HomebridgeCertificates: $(certificates)
	mkdir --parent "$(volume_root)/.config/certificates"\
	&& cp --verbose $(certificates) "$(volume_root)/.config/certificates"
	@echo "\nWhat\'s next:"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

Update-HomebridgeRcloneConf: $(rclone_conf_file)
	mkdir --parent "$(volume_root)/.config/rclone"\
	&& cp --verbose $(rclone_conf_file) "$(volume_root)/.config/rclone"
	@echo "\nWhat\'s next:"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

## BUILD RULES

$(certificates):
	make New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	make Update-HomebridgeCertificates

$(container_rclone_conf_file): $(rclone_conf_file)
	make Update-HomebridgeRcloneConf
