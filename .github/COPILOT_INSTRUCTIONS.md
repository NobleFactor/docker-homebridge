# GitHub Copilot Instructions

## Development Guidelines

### Change Control (MANDATORY)
- Do not modify files unless the user explicitly requests an edit and approves the exact patch.
- Always present a proposed patch first (filename, before/after context). Apply only after explicit approval.
- Do not commit or run commands unless asked to. Prefer read-only reviews and suggestions.
- No drive-by edits: avoid formatting, comment rewrites, or style changes unless specifically authorized.

### Command Options
- **Always use long-form command options** (e.g., `--option` instead of `-o`)
- Examples:
  - `usermod --gid` not `usermod -g`
  - `docker --file` not `docker -f`
  - `chmod --recursive` not `chmod -r`

### Code Changes
- **Never make unsolicited code changes**
- **Always provide exact line numbers** when suggesting fixes
- Let the developer make the actual edits unless explicitly asked to do so
- Include sufficient context (3-5 lines before/after) when identifying issues
- If permission to edit is granted, limit changes to the approved patch only.

### Build and Deployment
- **Prefer make targets over raw docker commands**
- Use `make New-HomebridgeImage` instead of `docker build`
- Use `make Start-Homebridge` instead of `docker compose up`

### Communication Style
- Be concise and precise
- Keep discussions succinct
- Do not express emotion
- Provide actionable information
- Don't repeat unchanged context across responses
- Focus on deltas and what changed

## Project Conventions

### Shell Scripts
- Use `bash` with strict error handling: `set -o errexit -o nounset -o pipefail`
- Prefer long-form options for readability

### Docker
- Use BuildKit heredocs for multi-line RUN commands
- Follow OCI Image Format Specification

### S6-Overlay
- Oneshot services use execlineb by default
- Use `foreground { command } true` pattern for non-fatal operations
- Longrun services use shell with `#!/command/with-contenv sh`
