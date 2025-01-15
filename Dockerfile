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

RUN touch /noblefactor.init && chmod +x /noblefactor.init && cat > /noblefactor.init <<EOF
#!/usr/bin/env bash

set -o errexit -o nounset

export RCLONE_CACHE_DIR=/var/lib/rclone
export RCLONE_CONFIG=/homebridge/.config/rclone/rclone.conf
export RCLONE_LOG_FILE=/var/log/rclone/rclone.log
export RCLONE_LOG_LEVEL=INFO
export RCLONE_VFS_CACHE_MODE=full

if ! /usr/bin/rclone mount --daemon backups:Homebridge/backups/\${NOBLEFACTOR_HOMEBRIDGE_ISO_SUBDIVISION} /homebridge/backups; then
    echo "Rclone exit code: $?" && tail -3 /var/log/rclone/rclone.log
    exit 1
fi
EOF

# RUNTIME ENVIRONMENT

ENTRYPOINT /noblefactor.init && /init
