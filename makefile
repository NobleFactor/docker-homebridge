########################################################################################################################
# Copyright (c) 2024 Noble Factor
# homebridge-base_image
########################################################################################################################

# TODO (david-noble) Reference SPDX document that references MIT and Homebridge software terms and conditions.
# TODO (david-noble) Enable multi-platform builds as an option by adding a step to detect and create a multi-platform builder (See reference 3)

SHELL := bash
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c
.ONESHELL:

define USAGE

NAME
    make - Manage Homebridge deployment for $(ISO_SUBDIVISION)

SYNOPSIS
    make <target> ISO_SUBDIVISION=CC-SS [VAR=VALUE ...]

REQUIRED
    IP_RANGE                  IP range for Docker network (e.g., 192.168.1.8/29). This is required to create the Docker
                              network when making a new Homebridge container. Care should be take to ensure that the
                              IP range you specify does not conflict with your network's DHCP server. This may require
                              a change to the pool of addresses allocated by your DHCP server.

                              Required by: New-HomebridgeContainer.

OPTIONAL
    CONTAINER_DOMAIN_NAME     Override container domain name (default: localdomain)
    CONTAINER_ENVIRONMENT     Deployment environment: dev, test, prod (default: dev). Except for prod, whatever 
                              environment name you specify is included as a suffix in the default CONTAINER_HOSTNAME.
    CONTAINER_HOSTNAME        Override container hostname (default: homebridge-ISO_SUBDIVISION[-CONTAINER_ENVIRONMENT])
    HOMEBRIDGE_VERSION        Upstream Homebridge version (default: latest)
    IP_ADDRESS                IPv4 address for the Homebridge container (e.g.,192.168.1.10). You may set this whenever
                              you start or restart the container. The value does not matter at any other time. If not
                              set, Docker will assign an available address from the IP_RANGE.
    ISO_SUBDIVISION           ISO 3166-2 subdivision code (default: computed from the docker host's geo-location)

TARGETS
    help                           Show this help
    clean                          Stop, remove network, prune system, and clear volumes
    New-Homebridge                 Build image, create network, and create container
    New-HomebridgeImage            Build image and create network
    New-HomebridgeContainer        Create container from existing image
    Start-Homebridge               Start container
    Stop-Homebridge                Stop container
    Restart-Homebridge             Restart container
    Get-HomebridgeStatus           Show compose status (JSON)
    Start-HomebridgeShell          Open an interactive shell in the container
    New-HomebridgeCertificates     Generate self-signed certificates
    Update-HomebridgeCertificates  Copy certificates into container volume
    Update-HomebridgeRcloneConf    Copy rclone.conf into container volume

TARGET VARIABLE DEPENDENCIES

    help
        Consults: ISO_SUBDIVISION (for display in help text)

    clean
        Consults: network_name (computed from project_name, network_device)
        Indirect: project_name, network_device, ISO_SUBDIVISION (via project_file)

    Get-HomebridgeStatus
        Consults: docker_compose variable which uses:
                  - HOMEBRIDGE_IMAGE (computed from project_name, TAG)
                  - CONTAINER_HOSTNAME (from param or computed from ISO_SUBDIVISION, CONTAINER_ENVIRONMENT)
                  - CONTAINER_DOMAIN_NAME (from param or default: localdomain)
                  - ISO_SUBDIVISION (from param or auto-detected)
                  - network_name (computed from project_name, network_device)
                  - project_file (computed from project_name, ISO_SUBDIVISION)
                  - project_networks_file (computed from project_name)

    New-HomebridgeImage
        Consults: IP_RANGE (required)
                  HOMEBRIDGE_VERSION (from param or default: latest)
                  HOMEBRIDGE_IMAGE (computed from project_name, TAG)
                  network_device (auto-detected from OS)
                  network_driver (auto-detected from OS: macvlan or bridge)
                  ISO_SUBDIVISION (for display in output)
        Indirect: TAG (default: 1.0.0-preview.1), project_name

    New-HomebridgeContainer
        Consults: IP_ADDRESS (optional, validated against IP_RANGE if provided)
                  IP_RANGE (for validation)
                  docker_compose (see Get-HomebridgeStatus for variables)
                  CONTAINER_HOSTNAME (for docker inspect)
                  ISO_SUBDIVISION (for display in output)
        Dependencies: certificates, container_backups, container_certificates, container_rclone_conf_file
        Indirect: certificates_root (uses ISO_SUBDIVISION), volume_root (uses ISO_SUBDIVISION)

    New-Homebridge
        Consults: All variables from New-HomebridgeImage and New-HomebridgeContainer
                  ISO_SUBDIVISION (for display in output)

    Restart-Homebridge
        Consults: docker_compose (see Get-HomebridgeStatus for variables)

    Start-Homebridge
        Consults: docker_compose (see Get-HomebridgeStatus for variables)

    Stop-Homebridge
        Consults: docker_compose (see Get-HomebridgeStatus for variables)

    Start-HomebridgeShell
        Consults: CONTAINER_HOSTNAME (shell variable expansion)

    New-HomebridgeCertificates
        Consults: certificates_root (computed from ISO_SUBDIVISION)
        Dependencies: certificate-request.conf file

    Update-HomebridgeCertificates
        Consults: certificates (files in certificates_root, uses ISO_SUBDIVISION)
                  volume_root (computed from ISO_SUBDIVISION)
                  ISO_SUBDIVISION (for display in output)

    Update-HomebridgeRcloneConf
        Consults: rclone_conf_file (path to secrets/rclone.conf)
                  volume_root (computed from ISO_SUBDIVISION)
                  ISO_SUBDIVISION (for display in output)

REFERENCE
    1. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
    2. https://en.wikipedia.org/wiki/ISO_3166-2:US
    3. New-DockerNetwork --help

endef

export USAGE

## PARAMETERS

### ISO_SUBDIVISION

ifeq ($(strip $(ISO_SUBDIVISION)),)
    ISO_SUBDIVISION := $(shell curl --fail --silent "http://ip-api.com/json?fields=countryCode,region" | jq --raw-output '"\(.countryCode)-\(.region)"' | tr '[:upper:]' '[:lower:]')
else
    ISO_SUBDIVISION := $(shell echo $(ISO_SUBDIVISION) | tr '[:upper:]' '[:lower:]')
endif

### CONTAINER_ENVIRONMENT

ifeq ($(strip $(CONTAINER_ENVIRONMENT)),)
	CONTAINER_ENVIRONMENT := dev
endif

ifeq ($(CONTAINER_ENVIRONMENT),prod)
	undefine hostname_suffix
else
	hostname_suffix := -$(CONTAINER_ENVIRONMENT)
endif

### CONTAINER_DOMAIN_NAME

ifeq ($(strip $(CONTAINER_DOMAIN_NAME)),)
	CONTAINER_DOMAIN_NAME := localdomain
endif

### CONTAINER_HOSTNAME

ifeq ($(strip $(CONTAINER_HOSTNAME)),)
	CONTAINER_HOSTNAME := homebridge-$(ISO_SUBDIVISION)$(hostname_suffix)
endif

### HOMEBRIDGE_VERSION

ifeq ($(strip $(HOMEBRIDGE_VERSION)),)
	HOMEBRIDGE_VERSION := latest
endif

## IP_ADDRESS

### Optional; if absent docker compose will decide based on the IP_RANGE

## IP_RANGE

### Required; you must provide a value to construct the homebridge network

export IP_RANGE

## VARIABLES

### PROJECT

ifeq ($(strip $(TAG)),)
    TAG := 1.0.0-preview.1
endif

project_name := homebridge
project_root := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
project_file := $(project_root)$(project_name)-$(ISO_SUBDIVISION).yaml
project_networks_file := $(project_root)$(project_name).networks.yaml

ifeq ("$(wildcard $(project_file))","")
    $(error Project file for ISO_SUBDIVISION $(ISO_SUBDIVISION) does not exist: $(project_file))
endif

HOMEBRIDGE_IMAGE := noblefactor/$(project_name):$(TAG)

### RCLONE

rclone_conf_root := $(project_root)secrets
rclone_conf_file := $(rclone_conf_root)/rclone.conf

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

OS := $(shell uname)

ifeq ($(OS),Linux)
    network_device := $(shell ip route | awk '/^default via / { print $$5; exit }')
    network_driver := macvlan
else ifeq ($(OS),Darwin)
    network_device := $(shell scutil --dns | gawk '/if_index/ { print gensub(/[()]/, "", "g", $$4); exit }')
    network_driver := bridge
else
    $(error Unsupported operating system: $OS)
endif

network_name := $(shell \
    project="$(project_name)"; \
    device="$(network_device)"; \
    len=$$((15 - $${#device})); \
    echo "$${project:0:$${len}}_$${device}")

## TARGETS

docker_compose := sudo \
	HOMEBRIDGE_IMAGE="$(HOMEBRIDGE_IMAGE)" \
	ISO_SUBDIVISION="$(ISO_SUBDIVISION)" \
	CONTAINER_HOSTNAME="$(CONTAINER_HOSTNAME)" \
	CONTAINER_DOMAIN_NAME="$(CONTAINER_DOMAIN_NAME)" \
	NETWORK_NAME="$(network_name)" \
	docker compose -f "$(project_file)" -f "$(project_networks_file)"

.PHONY: help clean Get-HomebridgeStatus Mount-HomebridgeBackups New-Homebridge New-HomebridgeContainer New-HomebridgeImage Restart-Homebridge Start-Homebridge Start-HomebridgeShell Stop-Homebridge New-HomebridgeCertificates Update-HomebridgeCertificates Update-HomebridgeRcloneConf

help:
	@echo "$$USAGE"

clean:
	make Stop-Homebridge
	sudo docker network rm --force $(network_name) || true
	sudo docker system prune --force --all
	sudo docker volume prune --force --all
	sudo rm -rfv volumes/*

Get-HomebridgeStatus:
	$(docker_compose) ps --all --format json --no-trunc | jq .

Mount-HomebridgeBackups:

	@declare -r mount_subcommand=$$([[ $(OS) == Darwin ]] && echo nfsmount || echo mount) 
	@declare -r remote_path="onedrive:Homebridge/backups"
	@declare -r mount_dir="HomebridgeBackups"
	@declare -r rclone_log_file="$${mount_dir}/../HomebridgeBackups.rclone.log"

	@mkdir --parents "$${mount_dir}"

	@pids="$$(ps -eo pid=,args= | awk -v mount="$$mount_subcommand" -v remote="$$remote_path" -v mount_dir="$$mount_dir" 'index($$0, "rclone " mount " " remote " " mount_dir) { print $$1 }')"
	@if [[ -n "$$pids" ]]; then
		kill $$pids || true
	fi

	rclone "$${mount_subcommand}" "$${remote_path}" "$${mount_dir}" \
		--vfs-cache-mode=full \
		--daemon \
		--log-level=DEBUG \
		--log-file="$${rclone_log_file}" || true

	@if [[ -f "$${rclone_log_file}" ]]; then
		awk 'END{print}' "$${rclone_log_file}" || true
	fi

New-Homebridge: New-HomebridgeImage New-HomebridgeContainer
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Start Homebridge in $(ISO_SUBDIVISION): make Start-Homebridge [IP_ADDRESS=<IP_ADDRESS>]"

New-HomebridgeContainer: $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf_file)

	@if [[ -z "$(IP_RANGE)" ]]; then
		echo "An IP_RANGE is required. Take care to ensure it does not overlap with the pool of addresses managed by your DHCP Server."
		exit 1		
	fi

	@if [[ -n "$(IP_ADDRESS)" ]]; then
		if ! grepcidr "$(IP_RANGE)" <(echo "$(IP_ADDRESS)") >/dev/null 2>&1; then
			echo "Failure: $(IP_ADDRESS) is NOT in $(IP_RANGE)"
			exit 1
		fi
	fi

	$(docker_compose) stop && New-DockerNetwork --device "$(network_device)" --driver "$(network_driver)" --ip-range "$(IP_RANGE)" homebridge
	$(docker_compose) create --force-recreate --pull never --remove-orphans
	@sudo docker inspect "$(CONTAINER_HOSTNAME)"

	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Start Homebridge in $(ISO_SUBDIVISION): make Start-Homebridge [IP_ADDRESS=<IP_ADDRESS>]"

New-HomebridgeImage:
	sudo docker buildx build \
		--build-arg homebridge_version=$(HOMEBRIDGE_VERSION) \
		--load --progress=plain \
		--tag "$(HOMEBRIDGE_IMAGE)" .
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Create Homebridge container in $(ISO_SUBDIVISION): make New-HomebridgeContainer [IP_ADDRESS=<IP_ADDRESS>]"

Restart-Homebridge:
	$(docker_compose) restart
	make Get-HomebridgeStatus
 
Start-Homebridge:
	$(docker_compose) start
	make Get-HomebridgeStatus

Start-HomebridgeShell:
	sudo docker exec --interactive --tty ${CONTAINER_HOSTNAME} /bin/bash

Stop-Homebridge:
	$(docker_compose) stop
	make Get-HomebridgeStatus

New-HomebridgeCertificates: $(certificates_root)/certificate-request.conf
	cd "$(certificates_root)"
	openssl req -new -config certificate-request.conf -nodes -out self-signed.csr
	openssl x509 -req -sha256 -days 365 -in self-signed.csr -signkey private-key.pem -out public-key.pem

Update-HomebridgeCertificates: $(certificates)
	mkdir --parent "$(volume_root)/.config/certificates"
	cp --verbose $(certificates) "$(volume_root)/.config/certificates"
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge"

Update-HomebridgeRcloneConf: $(rclone_conf_file)
	mkdir --parent "$(volume_root)/.config"
	cp --verbose $(rclone_conf_file) "$(volume_root)/.config"
	@echo -e "\n\033[1mWhat's next:\033[0m"	
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) reconfigures rclone: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

## BUILD RULES

$(certificates):
	make New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	make Update-HomebridgeCertificates

$(container_rclone_conf_file): $(rclone_conf_file)
	make Update-HomebridgeRcloneConf
