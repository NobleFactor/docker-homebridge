# NobleFactor / docker-homebridge

Container image and Makefile to run Homebridge with opinionated defaults, deterministic networking, and rclone-backed backups under s6 supervision.

## What it provides

- Base: `homebridge/homebridge` (version selectable via build arg)
- Rclone mount service (s6 overlay) to expose a cloud “backups” remote inside the container
- Make targets to build the image, create the container, and manage lifecycle
- Deterministic Docker networking with a user-specified IP range and optional static IP
- Scripted certificate generation and volume preparation per location

## Requirements

- Docker with Buildx and Compose
- GNU make, bash
- jq and curl (used by Makefile helpers)
- grepcidr (for IP validation when creating the container)

## Quick start

Platform note: we build and regularly test on Linux and macOS. Windows hasn’t been exercised yet; it may work via Docker Desktop + WSL2 and GNU tools, but it’s currently untested here.

1) Create a location environment file in the project root (example: `homebridge-us-wa.env`). See `TEMPLATES.md` for variables used by the templates.

2) Build the image (optional if you pull a prebuilt tag):

```sh
make New-HomebridgeImage [HOMEBRIDGE_VERSION=latest]
```

3) Create the container and prepare volumes (requires an IP range that does not overlap DHCP):

```sh
make New-HomebridgeContainer LOCATION=us-wa IP_RANGE=192.168.1.0/24 [IP_ADDRESS=192.168.1.25]
```

4) Start Homebridge:

```sh
make Start-Homebridge LOCATION=us-wa
```

5) Check status:

```sh
make Get-HomebridgeStatus LOCATION=us-wa
```

## Certificates and secrets

- Generate self-signed certificates for a location:

```sh
make New-HomebridgeCertificates LOCATION=us-wa
```

- Copy certificates and rclone config into the container’s volume:

```sh
make Update-HomebridgeCertificates LOCATION=us-wa
make Update-HomebridgeRcloneConf LOCATION=us-wa
```

## Backups (rclone)

The image starts an s6 longrun that mounts a configured rclone remote at `/homebridge/backups`. Supply `rclone.conf` via the volume at `volumes/<location>/.config/rclone.conf` (use the `Update-HomebridgeRcloneConf` target above). You can also mount a remote locally for inspection:

```sh
make Mount-HomebridgeBackups
```

## Networking

Container creation uses a deterministic network with your specified `IP_RANGE`. Optionally set a fixed `IP_ADDRESS` within that range. On Linux, the default network driver is `macvlan`; on macOS, `bridge`.

## Make targets (common)

- Build image: `make New-HomebridgeImage`
- Create container: `make New-HomebridgeContainer LOCATION=<loc> IP_RANGE=<cidr> [IP_ADDRESS=<ip>]`
- Start/Stop/Restart: `make Start-Homebridge` | `make Stop-Homebridge` | `make Restart-Homebridge`
- Status: `make Get-HomebridgeStatus`
- Certificates: `make New-HomebridgeCertificates` | `make Update-HomebridgeCertificates`
- Rclone config: `make Update-HomebridgeRcloneConf`

---

## Contributing and Change Control

Please read `CONTRIBUTING.md` before proposing changes.

- All changes require explicit pre-approval of the exact patch.
- Pull requests must follow the template and include only the approved diff.
