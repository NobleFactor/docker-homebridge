# NobleFactor / docker-homebridge

Container image and Makefile to run Homebridge with opinionated defaults, deterministic networking, and rclone-backed backups under s6 supervision.

## What it provides

- Base: `homebridge/homebridge` (version selectable via build arg)
- Rclone mount service (s6 overlay) to expose a cloud "backups" remote inside the container
- Make targets to build the image, create the container, and manage lifecycle
- Deterministic Docker networking with a user-specified IP range and optional static IP
- Scripted certificate generation and volume preparation per location
- Bash and Zsh shell completions for all scripts
- Man pages for all scripts

## Requirements

- Docker with Buildx and Compose
- GNU make, bash
- jq, curl (used by Makefile helpers)
- grepcidr, ipcalc (for IP validation and network configuration)
- openssl (for certificate generation)
- envsubst (from gettext package, for template processing)
- Linux only: nmcli (NetworkManager) for network device discovery

Run `build/Install-Dependencies` to install all required packages automatically on Linux or macOS.

## Quick start

Platform note: we build and regularly test on Linux and macOS. Windows hasn't been exercised yet; it may work via Docker Desktop + WSL2 and GNU tools, but it's currently untested here.

1) Install dependencies:

```sh
build/Install-Dependencies
```

2) Create a location environment file at `homebridge.config/<LOCATION>/certificate-request.env`. See `TEMPLATES.md` for required variables:

```sh
mkdir -p homebridge.config/us-wa
cat > homebridge.config/us-wa/certificate-request.env <<EOF
SERVER_ROLE=homebridge
LOCATION=us-wa
COUNTRY_CODE=US
STATE_OR_PROVINCE=Washington
CITY=Seattle
ORGANIZATION_NAME="My Home"
ORGANIZATIONAL_UNIT="Network"
DOMAIN_NAME="home.example.com"
EMAIL_ADDRESS="admin@example.com"
EOF
```

3) Build the image (optional if you pull a prebuilt tag):

```sh
make New-HomebridgeImage [HOMEBRIDGE_VERSION=latest]
```

4) Create the container and prepare volumes (requires an IP range that does not overlap DHCP):

```sh
make New-HomebridgeContainer LOCATION=us-wa IP_RANGE=192.168.1.0/24 [IP_ADDRESS=192.168.1.25]
```

5) Start Homebridge:

```sh
make Start-Homebridge LOCATION=us-wa
```

6) Check status:

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

The image starts an s6 longrun that mounts a configured rclone remote at `/homebridge/backups`. Place your `rclone.conf` at `homebridge.config/rclone.conf`, then copy it to the container volume:

```sh
make Update-HomebridgeRcloneConf LOCATION=us-wa
```

You can also mount a remote locally for inspection:

```sh
make Mount-HomebridgeBackups
```

## Directory structure

```text
docker-homebridge/
├── build/                    # Scripts (Install-*, New-*, etc.)
├── homebridge.config/        # Per-location configuration
│   ├── <LOCATION>/
│   │   ├── certificate-request.env
│   │   ├── ssl/
│   │   │   ├── certificate-request.conf
│   │   │   ├── certificate.pem
│   │   │   └── private-key.pem
│   │   └── <ENV>.network-config.mk  # Optional: IP_RANGE, IP_ADDRESS, MAC_ADDRESS
│   └── rclone.conf           # Shared rclone configuration
├── volumes/                  # Container bind mounts (created automatically)
│   └── <LOCATION>/
│       ├── .config/          # Runtime config copied here
│       └── backups/          # Rclone mount point
├── share/
│   ├── man/man1/             # Man pages
│   ├── bash-completion/      # Bash completions
│   └── zsh/site-functions/   # Zsh completions
└── docs/                     # Additional documentation
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

## Shell completions

Bash and Zsh completions are provided for all scripts in the `build/` directory.

### Bash

Add to `~/.bashrc`:

```bash
for f in /path/to/docker-homebridge/share/bash-completion/completions/*; do
    source "$f"
done
```

### Zsh

Add to `~/.zshrc`:

```zsh
fpath=(/path/to/docker-homebridge/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit
```

### Available completions

| Script | Completion features |
|--------|---------------------|
| `New-DockerNetwork` | Driver types, network interface names |
| `Remove-DockerNetwork` | Docker network names |
| `New-HomebridgeLocation` | Env file paths, country codes, server roles |
| `Test-HomebridgeLocationGeneration` | Auto-discovers test locations |
| `Install-Dependencies` | Help option |
| `Install-Docker` | Help option |
| `Install-Rclone` | Help option |
| `Declare-BashScript` | Help option, file paths |

## Man pages

Man pages are available for all scripts. View them with:

```sh
man -M share/man <script-name>
```

Or install locally using `Declare-BashScript`'s `install_script_to_local` function, which symlinks scripts, man pages, and completions to `~/.local/`.

---

## Contributing and Change Control

Please read `CONTRIBUTING.md` before proposing changes.

- All changes require explicit pre-approval of the exact patch.
- Pull requests must follow the template and include only the approved diff.

## License

This project is licensed under the MIT License. See individual source files for copyright notices.

The Homebridge software and its dependencies are subject to their respective licenses. See the [Homebridge LICENSE](https://github.com/homebridge/homebridge/blob/latest/LICENSE) for details.
