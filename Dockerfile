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
LABEL org.opencontainers.image.authors="David.Noble@noblefactor.com"
LABEL org.opencontainers.image.licenses="MIT"

SHELL [ "/usr/bin/env", "bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c" ]
ARG puid pgid

########################################################################################################################
# RCLONE SETUP
#
# Rclone runs under S6 supervision and provides cloud backup mount functionality.
#
# S6 service tree for rclone backups
#
# user (bundle)
# ├─ rclone-backups-init [oneshot]
# ├─ rclone-backups-run  [longrun]
# │    └─ depends on → rclone-backups-init
# │       produces logs → rclone-backups-log
# └─ rclone-backups-log  [longrun]
#
# Responsibilities
# - rclone-backups-init: create /homebridge/.cache/rclone and /homebridge/backups after bind mounts; chown to homebridge
# - rclone-backups-run:  exec s6-setuidgid homebridge rclone mount backups:Homebridge/backups/${NOBLEFACTOR_HOMEBRIDGE_LOCATION}
#                        to /homebridge/backups with configured cache dir and log level
# - rclone-backups-log:  capture logs via s6-log to /var/log/rclone (rotation: n20 s2000000 with timestamps)
#
# Files
# - /etc/s6-overlay/s6-rc.d/rclone-backups-init/{type=oneshot, up}
# - /etc/s6-overlay/s6-rc.d/rclone-backups-run/{type=longrun, run, dependencies.d/rclone-backups-init, producer-for}
# - /etc/s6-overlay/s6-rc.d/rclone-backups-log/{type=longrun, run, consumer-for}
# - /etc/s6-overlay/s6-rc.d/user/contents.d/{rclone-backups-init,rclone-backups-run,rclone-backups-log}
#
########################################################################################################################

## INSTALLATION

RUN <<EOF
# Install rclone and dependencies
apt-get update
apt-get -y upgrade
apt-get -y install avahi-daemon fuse3 iproute2 kmod unzip
curl --silent --show-error https://rclone.org/install.sh | bash -s
EOF

RUN mkdir -p /opt/homebridge && cat > /opt/homebridge/Rclone.manifest <<EOF
Rclone Docker Package Manifest

 Release Version: $(date +%Y-%m-%d)

 | Package | Version |
 |:-------:|:-------:|
 |Ubuntu|24.04|
 |s6-overlay|3.2.0.2|
 |fuse3|$(dpkg -s fuse3 | awk '/^Version:/ {print $2}' | cut -d'-' -f1)|
 |rclone|$(rclone version --check 2>/dev/null | awk 'NR==1{print $2}' || rclone version 2>/dev/null | awk 'NR==1{print $2}')|

EOF

## SECURITY 

RUN <<EOF
# Remove irrelevant user and group

if id -u ubuntu >/dev/null 2>&1; then
    # Ignore mail spool warning; user is deleted successfully even if spool doesn't exist
    userdel -r ubuntu 2>/dev/null || true
fi

if getent group ubuntu >/dev/null 2>&1; then
    groupdel ubuntu
fi

# Modify homebridge user and group as requested by build arguments

if [[ -n ${pgid:-} ]]; then
    if getent group homebridge >/dev/null 2>&1; then
        groupmod -g "${pgid}" homebridge
    else
        groupadd --system --gid "${pgid}" homebridge 2>/dev/null
    fi
else
    pgid=0
fi
if [[ -n ${puid:-} ]]; then
    if id homebridge >/dev/null 2>&1; then
        echo "Modifying homebridge user: $(id homebridge)"
        usermod -u "${puid}" -g "${pgid}" --groups homebridge homebridge
    else
        echo "Creating homebridge user"
        useradd --system --uid "${puid}" --gid "${pgid}" --groups homebridge --no-create-home --shell /usr/sbin/nologin homebridge
    fi
else
    if id homebridge >/dev/null 2>&1; then
        echo "Modifying homebridge user: $(id homebridge)"
        usermod -g "${pgid}" --groups homebridge homebridge
    else
        echo "Creating homebridge user"
        useradd --system --gid "${pgid}" --groups homebridge --no-create-home --shell /usr/sbin/nologin homebridge
    fi
fi

echo "Updated homebridge user: $(id homebridge)"

# Ensure ownership and permissions on /homebridge directory

chown -R homebridge:homebridge /homebridge
chmod -R u+rwX,g+rwX /homebridge
EOF

## Create S6 service files

RUN mkdir -p\
 /etc/s6-overlay/s6-rc.d/homebridge/dependencies.d\
 /etc/s6-overlay/s6-rc.d/rclone-backups-init\
 /etc/s6-overlay/s6-rc.d/rclone-backups-run/dependencies.d\
 /etc/s6-overlay/s6-rc.d/rclone-backups-log\
 /etc/s6-overlay/s6-rc.d/rclone-credits
 
### rclone-credits (oneshot)

RUN touch /etc/s6-overlay/s6-rc.d/rclone-credits/up && chmod +x /etc/s6-overlay/s6-rc.d/rclone-credits/up && cat > /etc/s6-overlay/s6-rc.d/rclone-credits/up <<EOF
#!/bin/sh
# Display rclone manifest during startup
cat /opt/homebridge/Rclone.manifest
EOF

### rclone-backups-init (oneshot)

RUN touch /etc/s6-overlay/s6-rc.d/rclone-backups-init/up && chmod +x /etc/s6-overlay/s6-rc.d/rclone-backups-init/up && cat > /etc/s6-overlay/s6-rc.d/rclone-backups-init/up <<EOF
#!/command/execlineb -P
foreground { mkdir -p /homebridge/.cache/rclone }
foreground { mkdir -p /homebridge/backups }
foreground { chown -R homebridge:root /homebridge/.cache/rclone /homebridge/backups }
EOF

### rclone-backups-run (longrun)

RUN touch /etc/s6-overlay/s6-rc.d/rclone-backups-run/run && chmod +x /etc/s6-overlay/s6-rc.d/rclone-backups-run/run && cat > /etc/s6-overlay/s6-rc.d/rclone-backups-run/run <<EOF
#!/command/with-contenv sh
exec /command/s6-setuidgid homebridge /usr/bin/rclone mount \
    "backups:Homebridge/backups/\${NOBLEFACTOR_HOMEBRIDGE_LOCATION}" \
    "/homebridge/backups" \
    --config /homebridge/.config/rclone.conf \
    --cache-dir /homebridge/.cache/rclone \
    --vfs-cache-mode full \
    --allow-non-empty \
    --log-level INFO
EOF

### rclone-backups-log (longrun)

RUN touch /etc/s6-overlay/s6-rc.d/rclone-backups-log/run && chmod +x /etc/s6-overlay/s6-rc.d/rclone-backups-log/run && cat > /etc/s6-overlay/s6-rc.d/rclone-backups-log/run <<EOF
#!/bin/sh
exec s6-log -b n20 s2000000 T /var/log/rclone
EOF

## Specify service types

RUN <<EOF
echo oneshot > /etc/s6-overlay/s6-rc.d/rclone-credits/type
echo oneshot > /etc/s6-overlay/s6-rc.d/rclone-backups-init/type
echo longrun > /etc/s6-overlay/s6-rc.d/rclone-backups-run/type
echo longrun > /etc/s6-overlay/s6-rc.d/rclone-backups-log/type
EOF

## Wire dependencies and add to the default bundle

RUN <<EOF
# rclone-credits displays the rclone manifest during startup (oneshot, runs early)
touch /etc/s6-overlay/s6-rc.d/user/contents.d/rclone-credits

# rclone-backups-run depends on rclone-backups-init (init must complete before mount starts)
touch /etc/s6-overlay/s6-rc.d/rclone-backups-run/dependencies.d/rclone-backups-init

# homebridge depends on rclone-backups-run (mount must be ready before homebridge starts)
touch /etc/s6-overlay/s6-rc.d/homebridge/dependencies.d/rclone-backups-run

# rclone-backups-run produces logs for rclone-backups-log (logging pipeline)
echo rclone-backups-log > /etc/s6-overlay/s6-rc.d/rclone-backups-run/producer-for
echo rclone-backups-run > /etc/s6-overlay/s6-rc.d/rclone-backups-log/consumer-for

# Add all rclone services to the user bundle
touch /etc/s6-overlay/s6-rc.d/user/contents.d/rclone-backups-init
touch /etc/s6-overlay/s6-rc.d/user/contents.d/rclone-backups-run
touch /etc/s6-overlay/s6-rc.d/user/contents.d/rclone-backups-log
EOF

# ENTRYPOINT

RUN touch /noblefactor.init && chmod +x /noblefactor.init && cat > /noblefactor.init <<'EOF'
#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Modify homebridge user/group based on PUID/PGID environment variables at runtime
# This allows the container to match host user/group IDs for volume permissions

if [[ -n "${PUID:-}" ]] || [[ -n "${PGID:-}" ]]; then
    echo "Runtime user/group modification requested"
    
    current_uid=$(id --user homebridge)
    current_gid=$(id --group homebridge)
    
    if [[ -n "${PGID:-}" ]] && [[ "${PGID}" != "${current_gid}" ]]; then
        echo "Modifying homebridge group: ${current_gid} -> ${PGID}"
        groupmod --gid "${PGID}" homebridge
    fi
    
    if [[ -n "${PUID:-}" ]] && [[ "${PUID}" != "${current_uid}" ]]; then
        echo "Modifying homebridge user: ${current_uid} -> ${PUID}"
        usermod --uid "${PUID}" homebridge
    fi
  
    echo "Updating /homebridge ownership..."
    chown --recursive homebridge:homebridge /homebridge
fi

echo "homebridge user: $(id homebridge)"

# Chain to S6 overlay init
exec /init "$@"
EOF

ENTRYPOINT [ "/noblefactor.init" ]
