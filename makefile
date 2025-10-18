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
    IP_RANGE                  IP range for Docker network (e.g., 192.168.1.8/29). This is required to create the Docker
                              network when making a new Homebridge image.

OPTIONAL
    HOMEBRIDGE_DOMAIN_NAME    Override container domain name (default: localdomain)
    HOMEBRIDGE_HOSTNAME       Override container hostname (default: homebridge-ISO_SUBDIVISION[-STAGE])
    HOMEBRIDGE_VERSION        Upstream Homebridge version (default: latest)
    IP_ADDRESS                IPv4 address for the Homebridge container (e.g.,192.168.1.10). You may set this whenever
                              you start or restart the container. The value does not matter any other time. If not set,
                              Docker will assign an available address from the IP_RANGE.
    ISO_SUBDIVISION           ISO 3166-2 subdivision code (default: computed from the docker host's geo-location)
    NOBLEFACTOR_VERSION       Image tag for noblefactor/homebridge (default: preview.2)
    STAGE                     Deployment stage: dev, test, prod (default: dev)

TARGETS
    help                           Show this help
    clean                          Stop, remove network, prune system, and clear volumes
    New-Homebridge                 Build image, create network, and create container
    Start-Homebridge               Start container
    Stop-Homebridge                Stop container
    Restart-Homebridge             Restart container
    Get-HomebridgeStatus           Show compose status (JSON)
    Start-HomebridgeShell          Open an interactive shell in the container
    New-HomebridgeCertificates     Generate self-signed certificates
    Update-HomebridgeCertificates  Copy certificates into container volume
    Update-HomebridgeRcloneConf    Copy rclone.conf into container volume

REFERENCE
    1. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
    2. https://en.wikipedia.org/wiki/ISO_3166-2:US
	3. New-DockerNetwork --help

endef

export USAGE

SHELL := /bin/bash

## PARAMETERS

### NOBLEFACTOR_VERSION

ifndef NOBLEFACTOR_VERSION
	NOBLEFACTOR_VERSION :=
endif

ifeq ($(strip $(NOBLEFACTOR_VERSION)),)
	NOBLEFACTOR_VERSION := preview.
endif

### ISO_SUBDIVISION

ifndef ISO_SUBDIVISION
    ISO_SUBDIVISION :=
endif

ifeq ($(strip $(ISO_SUBDIVISION)),)
    ISO_SUBDIVISION := $(shell curl --no-progress-meter "http://ip-api.com/json?fields=countryCode,region" | jq --raw-output '"\(.countryCode)-\(.region)"' | tr '[:upper:]' '[:lower:]')
else
    ISO_SUBDIVISION := $(shell echo $(ISO_SUBDIVISION) | tr '[:upper:] '[:lower:]')
endif

### STAGE

ifndef STAGE
    STAGE :=
endif

ifeq ($(strip $(STAGE)),)
	STAGE := dev
endif

ifeq ($(STAGE),prod)
	stage :=
else
	stage := -$(STAGE)
endif

### HOMEBRIDGE_DOMAIN_NAME

ifndef HOMEBRIDGE_DOMAIN_NAME
	HOMEBRIDGE_DOMAIN_NAME :=
endif

ifeq ($(strip $(HOMEBRIDGE_DOMAIN_NAME)),)
	HOMEBRIDGE_DOMAIN_NAME := localdomain
endif

### HOMEBRIDGE_HOSTNAME

ifndef HOMEBRIDGE_HOSTNAME
	HOMEBRIDGE_HOSTNAME :=
endif

ifeq ($(strip $(HOMEBRIDGE_HOSTNAME)),)
	HOMEBRIDGE_HOSTNAME := homebridge-$(ISO_SUBDIVISION)$(stage)
endif

### HOMEBRIDGE_VERSION

ifndef HOMEBRIDGE_VERSION
	HOMEBRIDGE_VERSION :=
endif

ifeq ($(strip $(HOMEBRIDGE_VERSION)),)
	HOMEBRIDGE_VERSION := latest
endif

## VARIABLES

docker_compose = sudo \
	HOMEBRIDGE_DOMAIN_NAME="$(HOMEBRIDGE_DOMAIN_NAME)" \
	HOMEBRIDGE_HOSTNAME="$(HOMEBRIDGE_HOSTNAME)" \
	IP_ADDRESS="$(IP_ADDRESS)" \
	ISO_SUBDIVISION="$(ISO_SUBDIVISION)" \
	NETWORK_NAME="$(network_name)" \
	NOBLEFACTOR_VERSION="$(NOBLEFACTOR_VERSION)" \
	docker compose -f "$(project_file)" -f "$(project_networks_file)"

### PATHS

project_root := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
project_name := homebridge
project_file := $(project_root)$(project_name)-$(ISO_SUBDIVISION).yaml
project_networks_file := $(project_root)$(project_name).networks.yaml

ifeq ("$(wildcard $(project_file))","")
    $(error Project file for $(ISO_SUBDIVISION) does not exist: $(project_file))
endif

### RCLONE

rclone_conf_root := $(project_root)secrets
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
	$(volume_root)/.config/rclone.conf

### NETWORK

network_device := $(shell if [[ $${OSTYPE} == linux-gnu* ]]; then echo eth0; elif [[ $${OSTYPE} == darwin* ]]; then scutil --dns | gawk '/if_index/ { print gensub(/[()]/, "", "g", $$4); exit }'; else echo nul; fi)
network_driver := $(shell if [[ $${OSTYPE} == linux-gnu* ]]; then echo "macvlan"; else echo "bridge"; fi)
network_name := $(shell service_name="$(project_name)" device_name="$(network_device)" && echo "$${service_name:0:$$(( 16 - $${#device_name} ))}_$${device_name}")

$(error HOMEBRIDGE_DOMAIN_NAME: $(HOMEBRIDGE_DOMAIN_NAME))

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

New-Homebridge: $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf_file) $(check_defined_ip_range)
	sudo docker buildx build --build-arg homebridge_version=$(HOMEBRIDGE_VERSION) --load --progress=plain --tag=noblefactor/$(project_name):$(NOBLEFACTOR_VERSION) . \
	&& New-DockerNetwork --ip-range "$(IP_RANGE)" "${project_name}" \
	&& $(docker_compose) create --force-recreate --pull never --remove-orphans \
	&& sudo docker inspect "$(HOMEBRIDGE_HOSTNAME)"
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Start Homebridge in $(ISO_SUBDIVISION): make Start-Homebridge IP_ADDRESS=<IP_ADDRESS>"

Restart-Homebridge: $(check_defined_ip_address)
	$(docker_compose) restart\
	&& make Get-HomebridgeStatus
 
Start-Homebridge: $(check_defined_ip_address)
	$(docker_compose) start\
	&& make Get-HomebridgeStatus

Start-HomebridgeShell:
	sudo docker exec --interactive --tty ${HOMEBRIDGE_HOSTNAME} /bin/bash

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
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge"

Update-HomebridgeRcloneConf: $(rclone_conf_file)
	mkdir --parent "$(volume_root)/.config"\
	&& cp --verbose $(rclone_conf_file) "$(volume_root)/.config"
	@echo -e "\n\033[1mWhat's next:\033[0m"	
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) reconfigures rclone: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

## BUILD RULES

check_defined_ip_range:
	$(if $(filter undefined,$(origin IP_RANGE)), $(error IP_RANGE is required. Specify IP_RANGE=<CIDR> on the make command line.))

$(certificates):
	make New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	make Update-HomebridgeCertificates

$(container_rclone_conf_file): $(rclone_conf_file)
	make Update-HomebridgeRcloneConf
