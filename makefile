########################################################################################################################
# Copyright (c) 2024 Noble Factor
# homebridge-base_image
########################################################################################################################

# TODO (david-noble) Reference SPDX document that references MIT and Homebridge software terms and conditions.
# TODO (david-noble) Enable multi-platform builds as an option by adding a step to detect and create a multi-platform builder (See reference 3)

SHELL := bash
.SHELLFLAGS := -o errexit -o nounset -o pipefail -c
.ONESHELL:

## PARAMETERS

### LOCATION

ifeq ($(strip $(LOCATION)),)
    LOCATION := $(shell curl --fail --silent "http://ip-api.com/json?fields=countryCode,region" | jq --raw-output '"\(.countryCode)-\(.region)"' | tr '[:upper:]' '[:lower:]')
else
    LOCATION := $(shell echo $(LOCATION) | tr '[:upper:]' '[:lower:]')
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
	CONTAINER_HOSTNAME := homebridge-$(LOCATION)$(hostname_suffix)
endif

### HOMEBRIDGE_VERSION

ifeq ($(strip $(HOMEBRIDGE_VERSION)),)
	HOMEBRIDGE_VERSION := latest
endif

## IP_ADDRESS

### Optional; if absent docker compose will decide based on the IP_RANGE

## IP_RANGE

export IP_RANGE

## VARIABLES

### PROJECT

ifeq ($(strip $(TAG)),)
    TAG := 1.0.0-preview.1
endif

project_name := homebridge
project_root := $(patsubst %/,%,$(dir $(realpath $(lastword $(MAKEFILE_LIST)))))
project_file := $(project_root)/$(project_name)-$(LOCATION).yaml
project_networks_file := $(project_root)/$(project_name).networks.yaml

ifeq ("$(wildcard $(project_file))","")
    $(error Project file for LOCATION $(LOCATION) does not exist: $(project_file))
endif

HOMEBRIDGE_IMAGE := noblefactor/$(project_name):$(TAG)

### RCLONE

rclone_conf_file := $(project_root)/secrets/rclone.conf

### SECRETS

certificates_root := $(project_root)/secrets/certificates/$(LOCATION)

certificates := \
	$(certificates_root)/certificate-request.conf\
	$(certificates_root)/private-key.pem\
	$(certificates_root)/public-key.pem

### CONTAINER VOLUMES

volume_root := $(project_root)/volumes/$(LOCATION)

container_backups := $(volume_root)/backups

container_certificates := \
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
    LOCATION="$(LOCATION)" \
    CONTAINER_HOSTNAME="$(CONTAINER_HOSTNAME)" \
    CONTAINER_DOMAIN_NAME="$(CONTAINER_DOMAIN_NAME)" \
    NETWORK_NAME="$(network_name)" \
    docker compose -f "$(project_file)" -f "$(project_networks_file)"

HELP_COLWIDTH ?= 28

.PHONY: help help-short help-full clean Get-HomebridgeStatus Mount-HomebridgeBackups New-Homebridge New-HomebridgeContainer New-HomebridgeImage Restart-Homebridge Start-Homebridge Start-HomebridgeShell Stop-Homebridge New-HomebridgeCertificates Update-HomebridgeCertificates Update-HomebridgeRcloneConf

##@ Help
help: help-short ## Show brief help (alias: help-short)

help-short: ## Show brief help for annotated targets
	@awk 'BEGIN {FS = ":.*##"; pad = $(HELP_COLWIDTH); print "Usage: make <target> [VAR=VALUE]"; print ""; print "Targets:"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-*s %s\n", pad, $$1, $$2} /^##@/ {printf "\n%s\n", substr($$0,5)}' $(MAKEFILE_LIST) | less -R

help-full: ## Show detailed usage (man page)
	@man -P 'less -R' -l "$(project_root)/docs/homebridge-image.1"

##@ Utilities
clean: ## Stop, remove network, prune unused images/containers/volumes (DANGEROUS)
	make Stop-Homebridge
	sudo docker network rm --force $(network_name) || true
	sudo docker system prune --force --all
	sudo docker volume prune --force --all

##@ Lifecycle
Get-HomebridgeStatus: ## Show compose status (JSON)
	$(docker_compose) ps --all --format json --no-trunc | jq .

##@ Backups
Mount-HomebridgeBackups: ## Mount OneDrive backups via rclone

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

##@ Build and Create
New-Homebridge: New-HomebridgeImage New-HomebridgeContainer ## Build image and create container
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Start Homebridge in $(LOCATION): make Start-Homebridge [IP_ADDRESS=<IP_ADDRESS>]"

New-HomebridgeContainer: $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf_file) ## Create container from existing image and prepare volumes

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
	@echo "    Start Homebridge in $(LOCATION): make Start-Homebridge [IP_ADDRESS=<IP_ADDRESS>]"

New-HomebridgeImage: ## Build the Homebridge image only
	sudo docker buildx build \
		--build-arg homebridge_version=$(HOMEBRIDGE_VERSION) \
		--build-arg puid=$(shell id -u) \
		--load --progress=plain \
		--tag "$(HOMEBRIDGE_IMAGE)" .
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Create Homebridge container in $(LOCATION): make New-HomebridgeContainer [IP_ADDRESS=<IP_ADDRESS>]"

Restart-Homebridge: ## Restart container
	$(docker_compose) restart
	make Get-HomebridgeStatus
 
Start-Homebridge: ## Start container
	$(docker_compose) start
	make Get-HomebridgeStatus

Start-HomebridgeShell: ## Open interactive shell in the container
	sudo docker exec --interactive --tty ${CONTAINER_HOSTNAME} /bin/bash

Stop-Homebridge: ## Stop container
	$(docker_compose) stop
	make Get-HomebridgeStatus

##@ Certificates and Secrets
New-HomebridgeCertificates: $(certificates_root)/certificate-request.conf ## Generate self-signed certificates for LOCATION
	cd "$(certificates_root)"
	openssl req -x509 -new -config certificate-request.conf -nodes -days 365 -out public-key.pem
	openssl req -new -config certificate-request.conf -nodes -key private-key.pem -out self-signed.csr

Update-HomebridgeCertificates: $(certificates) ## Copy certificates into container volume for LOCATION
	mkdir --parent "$(volume_root)/.config/certificates"
	cp --verbose $(certificates) "$(volume_root)/.config/certificates"
	@echo -e "\n\033[1mWhat's next:\033[0m"
	@echo "    Ensure that Homebridge in $(LOCATION) loads new certificates: make Restart-Homebridge"

Update-HomebridgeRcloneConf: $(rclone_conf_file) ## Copy rclone.conf into container volume for LOCATION
	mkdir --parent "$(volume_root)/.config"
	cp --verbose $(rclone_conf_file) "$(volume_root)/.config"
	@echo -e "\n\033[1mWhat's next:\033[0m"	
	@echo "    Ensure that Homebridge in $(LOCATION) reconfigures rclone: make Restart-Homebridge LOCATION=$(LOCATION)"

## BUILD RULES

$(certificates):
	make New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	make Update-HomebridgeCertificates

$(container_rclone_conf_file): $(rclone_conf_file)
	make Update-HomebridgeRcloneConf
