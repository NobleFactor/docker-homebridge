########################################################################################################################
# Copyright (c) 2024 Noble Factor
# homebridge-base_image
########################################################################################################################

# TODO (david-noble) Reference SPDX document that references MIT and Homebridge software terms and conditions.
# TODO (david-noble) Enable multi-platform builds as an option by adding a step to detect and create a multi-platform builder (See reference 3)

# REFERENCE
# 1. https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes
# 2. https://en.wikipedia.org/wiki/ISO_3166-2:US
# 3. https://docs.docker.com/build/building/multi-platform/

## PARAMETERS

NOBLEFACTOR_VERSION := preview.1
HOMEBRIDGE_VERSION := latest

ISO_SUBDIVISION := ${ISO_SUBDIVISION}

ifndef ISO_SUBDIVISION
    $(error Expected a value for ISO_SUBDIVISION. Example: make new-container ISO_SUBDIVSION=US-WA)
endif

## VARIABLES

project_root := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
project_file := $(project_root)homebridge.$(ISO_SUBDIVISION).yaml

ifeq ("$(wildcard $(project_file))","")
    $(error Project file for $(ISO_SUBDIVISION) does not exist: $(project_file))
endif

docker_compose := sudo ISO_SUBDIVISION=$(ISO_SUBDIVISION) NOBLEFACTOR_VERSION="$(NOBLEFACTOR_VERSION)" docker compose -f "$(project_file)"
certificates_root := $(project_root)secrets/certificates/$(ISO_SUBDIVISION)
rclone_conf_root := $(project_root)secrets/rclone
volume_root := $(project_root)volumes/$(ISO_SUBDIVISION)

certificates := \
	$(certificates_root)/self-signed.csr\
	$(certificates_root)/private-key.pem\
	$(certificates_root)/public-key.pem

rclone_conf := $(rclone_conf_root)/rclone.conf

container_backups := $(volume_root)/backups

container_certificates := \
	$(volume_root)/.config/certificates/self-signed.csr\
	$(volume_root)/.config/certificates/private-key.pem\
	$(volume_root)/.config/certificates/public-key.pem

container_rclone_conf := \
	$(volume_root)/.config/rclone/rclone.conf

## TARGETS

clean:
	make Stop-Homebridge\
	&& docker system prune --force --all && sudo rm -rfv volumes/*

Get-HomebridgeStatus:
	$(docker_compose) ps --format json | jq .

New-Homebridge: $(certificates) $(container_backups) $(container_certificates) $(container_rclone_conf)
	sudo docker buildx build --build-arg homebridge_version=$(HOMEBRIDGE_VERSION) --load --progress=plain --tag=noblefactor/homebridge:$(NOBLEFACTOR_VERSION) . \
	&& $(docker_compose) create --force-recreate --pull never --remove-orphans
	@echo "\nWhat's next:"
	@echo "    Start Homebridge in $(ISO_SUBDIVISION): make Start-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

Restart-Homebridge:
	$(docker_compose) restart
 
Start-Homebridge:
	$(docker_compose) start

Stop-Homebridge:
	$(docker_compose) stop

New-HomebridgeCertificates: $(certificates_root)/certificate-request.conf
	cd "$(certificates_root)"\
	&& openssl req -new -config certificate-request.conf -nodes -out self-signed.csr\
	&& openssl x509 -req -sha256 -days 365 -in self-signed.csr -signkey private-key.pem -out public-key.pem

Update-HomebridgeCertificates: $(certificates)
	mkdir --parent "$(volume_root)/.config/certificates"\
	&& cp --verbose $(certificates) "$(volume_root)/.config/certificates"
	@echo "\nWhat\'s next:"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

Update-HomebridgeRcloneConf: $(rclone_conf)
	mkdir --parent "$(volume_root)/.config/rclone"\
	&& cp --verbose $(rclone_conf) "$(volume_root)/.config/rclone"
	@echo "\nWhat\'s next:"
	@echo "    Ensure that Homebridge in $(ISO_SUBDIVISION) loads new certificates: make Restart-Homebridge ISO_SUBDIVISION=$(ISO_SUBDIVISION)"

## BUILD RULES

$(certificates):
	make New-HomebridgeCertificates

$(container_backups):
	mkdir -p $(container_backups)

$(container_certificates): $(certificates)
	make Update-HomebridgeCertificates

$(container_rclone_conf): $(rclone_conf)
	make Update-HomebridgeRcloneConf