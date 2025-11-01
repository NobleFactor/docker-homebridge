# Contributing to docker-homebridge

# Contributing to docker-homebridge

Welcome. This guide is for humans contributing to this repository. Automation-specific rules live in `.github/COPILOT_INSTRUCTIONS.md`.

## How we work (short version)

1) Propose first. Open an issue or draft PR with the exact patch (a unified diff) and a short rationale.

2) Get approval. Wait for explicit owner approval before editing anything.

3) Keep it tight. Apply only the approved diff. No drive‑by formatting, comment rewrites, or unrelated changes.

4) Explain and verify. Write a clear commit message (why + what) and include how you verified it.

## Pull requests

- Use focused PRs. Small, single‑purpose changes are easier to review and roll back.
- Follow the PR template checklist. Show pre‑approval, scope control, and validation steps.
- Prefer conventional commits for messages (e.g., `fix: ...`, `feat: ...`, `docs: ...`).
- Link issues where relevant.

## Development setup

- Use Make targets instead of raw Docker commands when possible.
    - Examples: `make New-HomebridgeImage`, `make Start-Homebridge`.
- Scripts use bash with strict flags; many source `build/Declare-BashScript` which manages shell options.

## Shell scripts: standards and template

Write clear, minimal, option‑driven scripts. Prefer long‑form options for readability.

Script header template:

```bash
#!/usr/bin/env bash

# <ScriptName>: <Short description>
#
# USAGE:
#   ./<ScriptName> [--arg1 <value>] [--arg2 <value>] ...
#
# DESCRIPTION:
#   <Brief workflow and expectations>
#
# ARGUMENTS:
#   --arg1 <value>  Description
#   --arg2 <value>  Description
#   --help          Show usage

source ../build/Declare-BashScript "$0" "arg1:,arg2:,help" "" "$@"
eval set -- "$script_arguments"

[[ $* != -- ]] || usage

while :; do
    case "$1" in
        -h|--help) usage; shift ;;
        --arg1) ARG1="$2"; shift 2 ;;
        --arg2) ARG2="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
    [[ $# -eq 0 ]] && break
done

# ...script body...
```

Guidelines:

- Use explicit, descriptive long options (e.g., `--test-location`).
- Defaults: test location defaults to `fake-wa` unless overridden.
- Template paths are project‑root relative and hard‑wired:
    - `./homebridge.yaml.template`
    - `./secrets/certificates/certificate-request.conf.template`
- Generated artifacts live in `./` and `./secrets/<test-location>`.
- Baselines live in `./test/baseline/<test-location>` and `./test/baseline/homebridge-<test-location>.yaml`.
- If a script sources `Declare-BashScript`, don’t add another `set -euo pipefail`—it’s already handled.
- Keep variables/args minimal—include only what’s required for logic and comparison.
- Document arguments, defaults, and file layout in the header and the man page.

## Tests

The `test/Test-HomebridgeArtifactsGeneration` script compares generated artifacts to baselines.

It checks:
- Generated YAML: `./homebridge-<test-location>.yaml`
- Baseline YAML: `./test/baseline/homebridge-<test-location>.yaml`
- Generated secrets: `./secrets/<test-location>`
- Baseline secrets: `./test/baseline/<test-location>`
- Field‑by‑field comparisons for certificate artifacts

Example:

```sh
./Test-HomebridgeArtifactsGeneration --test-location fake-wa
```

## Man pages

All build scripts must include a groff section‑1 man page under `build/man/man.1/` documenting usage, arguments, workflow, and conventions. All test scripts should include a groff seciotn-1 man page under `test/man/man.1`. Copilot and other AI chat bots do a great job of producing usable man pages, bash completions, and zsh completions. It makes this requirement possible.

## Change control

- Propose the exact patch and wait for approval before editing.
- Keep diffs minimal and on‑topic.
- Describe validation steps; prefer reproducible commands or tests.

Automation rules are defined separately in `.github/COPILOT_INSTRUCTIONS.md`.
```
