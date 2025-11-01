# Contributing to docker-homebridge


## Shell Script and Automation Standards

All contributors, bots, and automation agents must follow these conventions for shell scripts and project automation:

### Bash Script Declaration Template

All new bash scripts should begin with the following declaration pattern, as exemplified in `build/New-HomebridgeLocation` and `test/Test-HomebridgeArtifactsGeneration`:


```bash
#!/usr/bin/env bash

source ../build/Declare-BashScript "$0" "arg1:,arg2:,help" "" "$@"

```bash
#!/usr/bin/env bash

# <ScriptName>: <Short description of what the script does>
#
# USAGE:
#   ./<ScriptName> [--arg1 <value>] [--arg2 <value>] ...
#
# DESCRIPTION:
#   <Detailed description of script workflow, conventions, and expected behavior>
#
# ARGUMENTS:
#   --arg1 <value>   Description of arg1
#   --arg2 <value>   Description of arg2
#   --help           Show usage information
#
source ../build/Declare-BashScript "$0" "arg1:,arg2:,help" "" "$@"

eval set -- "$script_arguments"

[[ $* != -- ]] || usage

while :; do
    case "$1" in
        -h|--help)
            usage; # does not return
            shift 1
            ;;
        --arg1)
            export ARG1="$2"
            shift 2
            ;;
        --arg2)
            export ARG2="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
    [[ $# -eq 0 ]] && break
done

# Example processing loop with case statement
for item in "${items[@]}"; do
    case "$item" in
        arg1)
            echo "Processing arg1 logic"
            ;;
        arg2)
            echo "Processing arg2 logic"
            ;;
        *)
            echo "Unknown item: $item"
            ;;
    esac
done
```
- Use explicit, descriptive long option names (e.g., `--test-location`).
- Avoid ambiguous or generic argument names.

### Default Values
- Default test location is `fake-wa` unless overridden by the user.

### Template Paths
- Hardwire template paths in scripts; do not use a `template_dir` argument.
- Use project-root-relative paths for templates:
  - `./homebridge.yaml.template`
  - `./secrets/certificates/certificate-request.conf.template`

### Directory Structure
- Generated artifacts are always in the project root (`.`) and `./secrets/<test-location>`.
- Baseline artifacts are always in `./test/baseline/<test-location>` and `./test/baseline/homebridge-<test-location>.yaml`.

### Shell Options
- Do not add `set -euo pipefail` to scripts that source `Declare-BashScript`, as it already manages shell options.

### Minimalism
- Remove all unnecessary variables and arguments from scripts.
- Only keep variables required for logic and comparison.

### Documentation
- Clearly document argument usage, default values, and directory structure in script headers and man pages.

## Test Script Reference

The `Test-HomebridgeArtifactsGeneration` script compares generated Homebridge artifacts to baseline reference files:

- Generated YAML: `./homebridge-<test-location>.yaml`
- Baseline YAML: `./test/baseline/homebridge-<test-location>.yaml`
- Generated secrets: `./secrets/<test-location>`
- Baseline secrets: `./test/baseline/<test-location>`
- Field-by-field comparisons for certificate artifacts
- Template files are always at the project root

#### Example Usage

```sh
./Test-HomebridgeArtifactsGeneration --test-location fake-wa
```

## Man Page Requirement

All scripts in this repository must include a man page in groff format (section 1), located in the appropriate `test/man/man.1/` directory. Man pages should document usage, arguments, workflow, and conventions. These man pages must be able to be generated automatically by any chatbot or automation agent, ensuring documentation is always up-to-date and reproducible.

All Copilot agents, chatbots, and contributors must adhere to these standards for consistency and maintainability.
