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
<<<<<<< HEAD
mkdir --mode=go-rw --parents /var/lib/rlcone /var/log/rclone /homebridge/.config/rclone /homebridge/backups
=======
su root
mkdir --mode=go-rw --parents /var/lib/rlcone /var/log/rclone /homebridge/backups
if [[ \$? -ne 0 ]]; then
    echo WTF? > WTF
    mkdir /homebridge/.config
    mkdir /homebridge/.config/rclone
fi
>>>>>>> 22c4b0f233e4ced0c1a6d1f474815898a5c92347
EOF

# RUNTIME ENVIRONMENT

ENV HOMEBRIDGE_ISO_SUBDIVISION="${iso_subdivision}"

# ENTRYPOINT set -o errexit -o nounset && echo ${RCLONE_CONF} | /usr/bin/xxd -c0 -p -r > /etc/rclone.conf \
#     && /usr/bin/rclone mount --daemon --vfs-cache-mode writes\
#         --config /etc/rclone.conf\
#         --cache-dir /var/lib/rclone\
#         backups:Homebridge/backups/US-WA /homebridge/backups\
    && /init
