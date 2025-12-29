########################################################################################################################
# SPDX-FileCopyrightText: 2024-2025 Noble Factor
# SPDX-License-Identifier: MIT AND LicenseRef-Homebridge
#
# This project is licensed under the MIT License for all original work by Noble Factor. The Homebridge software and its
# dependencies are subject to their respective licenses. See:
#
# https://github.com/homebridge/homebridge/blob/latest/LICENSE
#
########################################################################################################################

# TODO (david-noble) Enable multi-platform builds as an option by adding a step to detect and create a multi-platform builder (See reference 3)

SHELL := bash
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c
.ONESHELL:
.SILENT:

### PROJECT

project_name := homebridge
project_root := $(patsubst %/,%,$(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
project_file := $(project_root)/compose.yaml

## PARAMETERS

### LOCATION (of deployment)

LOCATION ?= $(shell curl --fail --silent "http://ip-api.com/json?fields=countryCode,region" | jq --raw-output '"\(.countryCode)-\(.region)"')
location_config_dir := $(project_root)/$(project_name).config/$(LOCATION)

### CONTAINER_*

CONTAINER_DOMAIN_NAME ?= localdomain
CONTAINER_ENVIRONMENT ?= dev
CONTAINER_HOSTNAME ?= $(shell echo "homebridge-$(LOCATION)$$([[ $(CONTAINER_ENVIRONMENT) == prod ]] || echo "-$(CONTAINER_ENVIRONMENT)")" | tr '[:upper:]' '[:lower:]')

### HOMEBRIDGE_VERSION

HOMEBRIDGE_VERSION ?= latest

### TAG

TAG ?= 1.0.0-preview.3

### PER-INSTANCE NETWORK CONFIG (Makefile syntax)

network_config_file := $(location_config_dir)/$(CONTAINER_ENVIRONMENT).network-config.mk

ifneq ($(wildcard $(network_config_file)),)

    error_message := $(shell awk -F= '/^[[:space:]]*#/ { next } /^[[:space:]]*$$/ { next } !/^[[:space:]]*(IP_ADDRESS|IP_RANGE|MAC_ADDRESS)[[:space:]]*[:?]?=/ { printf("Invalid key or line: %s\n", $$0); exit 1 } !/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[:?]?=/ { printf("Invalid assignment: %s\n", $$0); exit 1 }' $(network_config_file) 2>&1)

    ifneq ($(error_message),)
        $(error Invalid network configuration for container $(CONTAINER_HOSTNAME): $(error_message))
    endif

    include $(network_config_file)

endif

export LOCATION CONTAINER_DOMAIN_NAME CONTAINER_ENVIRONMENT CONTAINER_HOSTNAME HOMEBRIDGE_VERSION TAG
export IP_ADDRESS IP_RANGE MAC_ADDRESS

## VARIABLES (static)

HOMEBRIDGE_IMAGE := noblefactor/$(project_name):$(TAG)

### CERTIFICATES

certreq_template := $(project_root)/build/templates/certificate-request.conf.template

certificate_request_env := $(location_config_dir)/certificate-request.env
certificates_root := $(location_config_dir)/ssl
certificate_request_conf := $(certificates_root)/certificate-request.conf
certificates := $(certificates_root)/certificate.pem $(certificates_root)/private-key.pem

### RCLONE CONFIG

rclone_conf_file := $(project_root)/homebridge.config/rclone.conf

### CONTAINER VOLUME

container_volume := $(project_root)/volumes/$(LOCATION)
container_backups := $(container_volume)/backups
container_config := $(container_volume)/.config

container_certificates := \
	$(container_config)/ssl/certificate.pem \
	$(container_config)/ssl/private-key.pem

container_rclone_conf_file := $(container_config)/rclone.conf

### NETWORK

OS := $(shell uname)

ifeq ($(OS),Linux)
    network_device := $(shell ip route | awk '/^default via / { print $$5; exit }')
    network_driver := macvlan
else ifeq ($(OS),Darwin)
    network_device := $(shell scutil --dns | gawk '/if_index/ { print gensub(/[()]/, "", "g", $$4); exit }')
    network_driver := bridge
else
    $(error Unsupported operating system: $(OS))
endif

network_name := $(shell \
    project="$(project_name)"; \
    device="$(network_device)"; \
    length=$$(($${#device} > 15? 15 : $${#device})); \
    echo "$${project:0:$$((62 - length))}_$${device:0:$${length}}")

## TARGETS

docker_compose := sudo \
    CONTAINER_DOMAIN_NAME="$(CONTAINER_DOMAIN_NAME)" \
    CONTAINER_HOSTNAME="$(CONTAINER_HOSTNAME)" \
    CONTAINER_VOLUME="$(container_volume)" \
    HOMEBRIDGE_IMAGE="$(HOMEBRIDGE_IMAGE)" \
	IP_ADDRESS="$(IP_ADDRESS)" \
    LOCATION="$(LOCATION)" \
	MAC_ADDRESS="$(MAC_ADDRESS)" \
    NETWORK_NAME="$(network_name)" \
    docker compose -f "$(project_file)"

.PHONY: help help-short help-full clean Get-HomebridgeHealth Get-HomebridgeStatus Mount-HomebridgeBackups New-Homebridge New-HomebridgeContainer New-HomebridgeImage New-LocationConfig New-HomebridgeNetwork Restart-Homebridge Start-Homebridge Start-HomebridgeShell Stop-Homebridge New-HomebridgeCertificates Update-HomebridgeCertificates Update-HomebridgeRcloneConf .ensure-network

##@ Help

HELP_COLWIDTH ?= 30

help: help-short ## Show brief help (alias: help-short)

help-short: ## Show brief help for annotated targets
	awk 'BEGIN {FS = ":.*##"; pad = $(HELP_COLWIDTH); print "Usage: make <target> [VAR=VALUE]"; print ""; print "Targets:"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-*s %s\n", pad, $$1, $$2} /^##@/ {printf "\n%s\n", substr($$0,5)}' $(MAKEFILE_LIST) | less -R

help-full: ## Show detailed usage (man page)
	man -P 'less -R' -l "$(project_root)/docs/docker-homebridge.1"

##@ Utilities

clean: ## Stop, remove network, prune unused images/containers/volumes (DANGEROUS)
	$(docker_compose) down --remove-orphans  # Stops AND removes containers
	sudo build/Remove-DockerNetwork $(network_name)
	sudo docker system prune --force --all
	sudo docker volume prune --force --all

##@ Lifecycle

Get-HomebridgeHealth: ## Show container health (JSON)
	sudo docker inspect "$(CONTAINER_HOSTNAME)" | jq -r '.[0].State.Health'

Get-HomebridgeStatus: ## Show compose status (JSON)
	$(docker_compose) ps --all --format json --no-trunc | jq .

##@ Backups

Mount-HomebridgeBackups: ## Mount OneDrive backups via rclone

	declare -r mount_subcommand=$$([[ $(OS) == Darwin ]] && echo nfsmount || echo mount) 
	declare -r remote_path="onedrive:Homebridge/backups"
	declare -r mount_dir="HomebridgeBackups"
	declare -r rclone_log_file="$${mount_dir}/../HomebridgeBackups.rclone.log"

	mkdir --parents "$${mount_dir}"

	pids="$$(ps -eo pid=,args= | awk -v mount="$$mount_subcommand" -v remote="$$remote_path" -v mount_dir="$$mount_dir" 'index($$0, "rclone " mount " " remote " " mount_dir) { print $$1 }')"
	if [[ -n "$$pids" ]]; then
		kill $$pids || true
	fi

	rclone "$${mount_subcommand}" "$${remote_path}" "$${mount_dir}" \
		--vfs-cache-mode=full \
		--daemon \
		--log-level=DEBUG \
		--log-file="$${rclone_log_file}" || true

	if [[ -f "$${rclone_log_file}" ]]; then
		awk 'END{print}' "$${rclone_log_file}" || true
	fi

##@ Build and Create

New-Homebridge: New-HomebridgeImage New-HomebridgeContainer ## Build image and create container

New-HomebridgeContainer: .ensure-network $(certificate_request_conf) $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf_file) ## Create container from existing image and prepare volumes

	if [[ -n "$(IP_ADDRESS)" ]]; then
		if ! grepcidr "$(IP_RANGE)" <(echo "$(IP_ADDRESS)") >/dev/null 2>&1; then
			echo "Failure: $(IP_ADDRESS) is NOT in $(IP_RANGE)"
			exit 1
		fi
	fi

	$(docker_compose) stop
	$(docker_compose) create --force-recreate --pull never --remove-orphans
	sudo docker inspect "$(CONTAINER_HOSTNAME)"

	echo -e "\n\033[1mWhat's next:\033[0m"
	echo "    Start Homebridge in $(LOCATION): make Start-Homebridge [IP_ADDRESS=<IP_ADDRESS>]"

New-HomebridgeImage: ## Build the Homebridge image only
	sudo docker buildx build \
		--build-arg homebridge_version=$(HOMEBRIDGE_VERSION) \
		--build-arg puid=$(shell id -u) \
		--load --progress=plain \
		--tag "$(HOMEBRIDGE_IMAGE)" .
	echo -e "\n\033[1mWhat's next:\033[0m"
	echo "    Create Homebridge container in $(LOCATION): make New-HomebridgeContainer [IP_ADDRESS=<IP_ADDRESS>]"

New-LocationConfig: ## Ensure location files exist; generate if missing or older than $(LOCATION)/ssl/certificate-request.env

	if [[ ! -f "$(certificate_request_env)" ]]; then
		echo "Missing environment file: $(certificate_request_env)"
		exit 1
	fi

	if [[ ! -f "$(certificate_request_conf)" || "$(certificate_request_conf)" -ot "$(certificate_request_env)" ]]; then
		build/New-LocationConfig --env-file="$(certificate_request_env)" --location="$(LOCATION)"
	fi

New-HomebridgeNetwork: ## Create Docker network for Homebridge
	if [[ "$(network_driver)" == "macvlan" && -z "$(IP_RANGE)" ]]; then
		echo "An IP_RANGE is required for macvlan networks. Define it in $(network_config_file) or override via: make IP_RANGE=<CIDR>"
		exit 1
	fi
	build/New-DockerNetwork --device "$(network_device)" --driver "$(network_driver)" $(if $(IP_RANGE),--ip-range "$(IP_RANGE)") "$(network_name)"
	echo "Network $(network_name) created"

Restart-Homebridge: $(certificate_request_conf) ## Restart container
	$(docker_compose) restart
	$(MAKE) Get-HomebridgeStatus

Start-Homebridge: $(certificate_request_conf) ## Start container
	$(docker_compose) start
	$(MAKE) Get-HomebridgeStatus

Start-HomebridgeShell: ## Open interactive shell in the container
	sudo docker exec --interactive --tty ${CONTAINER_HOSTNAME} /bin/bash

Stop-Homebridge: $(certificate_request_conf) ## Stop container
	containers=( $$(sudo docker ps --filter "label=com.docker.compose.project=homebridge" --filter "status=running" --quiet) )
	if [[ $${#containers[@]} -gt 0 ]]; then
		sudo docker stop "$${containers[@]}"
	fi
	$(MAKE) Get-HomebridgeStatus

##@ Configuration

New-HomebridgeCertificates: $(certificate_request_conf) ## Generate self-signed certificates for LOCATION
	mkdir -p "$(certificates_root)"
	cd "$(certificates_root)"
	openssl req -x509 -new -newkey rsa:2048 -keyout private-key.pem -config certificate-request.conf -nodes -days 365 -out certificate.pem
	openssl req -new -config certificate-request.conf -nodes -key private-key.pem -out self-signed.csr

Update-HomebridgeCertificates: $(certificates) ## Copy certificates into container volume for LOCATION
	mkdir --parent "$(container_config)/ssl"
	cp --verbose $^ "$(container_config)/ssl"
	echo -e "\n\033[1mWhat's next:\033[0m"
	echo "    Ensure that Homebridge in $(LOCATION) loads new certificates: make Restart-Homebridge"

Update-HomebridgeRcloneConf: $(rclone_conf_file) ## Copy rclone.conf into container volume for LOCATION
	mkdir --parent "$(container_volume)/.config"
	cp --verbose $^ "$(container_volume)/.config"
	echo -e "\n\033[1mWhat's next:\033[0m"	
	echo "    Ensure that Homebridge in $(LOCATION) reconfigures rclone: make Restart-Homebridge LOCATION=$(LOCATION)"

## INTERNAL TARGETS

.ensure-network: # Ensure Docker network exists (internal target)
	if ! sudo docker network inspect $(network_name) >/dev/null 2>&1; then
		$(MAKE) New-HomebridgeNetwork
	fi

$(certificates_root)/certificate.pem $(certificates_root)/private-key.pem:
	$(MAKE) New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	$(MAKE) Update-HomebridgeCertificates

$(container_rclone_conf_file): $(rclone_conf_file)
	$(MAKE) Update-HomebridgeRcloneConf

## Location artifact rules: if missing or stale vs env/templates, (re)generate via New-LocationConfig

env_stamp := $(project_root)/.env-$(LOCATION).stamp

# Friendly guidance when the certificate request env file is missing

$(certificate_request_env):
	echo "Missing environment file: $@"
	echo "Create it or symlink it into the project root (e.g., from test/baseline)."
	exit 1

# Stamp file tracks env freshness without requiring the env to be a hard prerequisite

$(env_stamp): $(certificate_request_env)
	touch "$@"

$(certificate_request_conf): $(certreq_template) $(env_stamp)
	$(MAKE) New-LocationConfig
