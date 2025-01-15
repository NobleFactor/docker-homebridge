########################################################################################################################
# Copyright (c) 2024 Noble Factor
# homebridge-image
########################################################################################################################

# TODO (david-noble) Credit Homebridge as appropriate and required by custom and the law.
# TODO (david-noble) Reference SPDX document that references MIT and Homebridge software terms and conditions.
# TODO (david-noble) Ensure that we comply with the OCI Image Format Specification at https://github.com/opencontainers/image-spec.
# TODO (david-noble) Ensure that the license expression specifies MIT AND any additional license expressions that may be required by homebridge.

ARG homebridge_version=latest

FROM homebridge/homebridge:${homebridge_version}

LABEL org.opencontainers.image.vendor="Noble Factor"
LABEL org.opencontainers.image.authors="David-Noble@noblefactor.com"
LABEL org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-c"]

ARG iso_subdivision

# INSTALLATION

RUN <<EOF
set -o errexit -o nounset
apt-get update
apt-get -y upgrade
apt-get -y install avahi-daemon fuse3 kmod rclone xxd
mkdir --mode=go-rw -p /var/lib/rlcone /var/log/rclone /homebridge/.config/rclone /homebridge/backups
EOF

# RUNTIME ENVIRONMENT

ENV HOMEBRIDGE_ISO_SUBDIVISION="${iso_subdivision}"

ENTRYPOINT echo ${RCLONE_CONF} | /usr/bin/xxd -c0 -p -r > /homebridge/.config/rclone/rclone.conf \
    && rclone mount --daemon --vfs-cache-mode writes backups:Homebridge/backups/US-WA /homebridge/backups\
        --config /homebridge/.config/rclone/rclone.conf\
        --cache-dir /var/lib/rclone\
    && /init
