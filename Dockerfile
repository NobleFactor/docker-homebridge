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

# INSTALLATION

RUN <<EOF
set -o errexit
apt-get update
apt-get -y upgrade
apt-get -y install avahi-daemon fuse3 kmod rclone
mkdir /var/lib/rclone /var/log/rclone
EOF

# RUNTIME ENVIRONMENT

ENTRYPOINT /usr/bin/rclone mount --daemon --vfs-cache-mode writes --config /homebridge/.config/rclone/rclone.conf\
 --cache-dir /var/lib/rclone --log-file /var/log/rclone/rclone.log\
 backups:Homebridge/backups/${NOBLEFACTOR_HOMEBRIDGE_ISO_SUBDIVISION} /homebridge/backups\
 && /init
