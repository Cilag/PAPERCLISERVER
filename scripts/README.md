# Paperclip Agents Toolchain Scripts

Idempotent setup for the 5-agents infrastructure consulting team.

## Files

- `bootstrap-agents-toolchain.sh` — installs all CLIs needed by the 5 agents on Ubuntu 24+. Run on the MSI server. Idempotent: safe to re-run.
- `new-client.sh <slug> <mission-title>` — scaffolds a new client mission (Paperclip project + GitHub repo + workdir clone).
- `lib/check.sh` — helper functions sourced by other scripts.
- `templates/repo-template/` — skeleton committed into each new client repo.

## How to run

On the MSI (as user `guigui`):

```bash
# Bootstrap toolchain (one-off, idempotent)
~/work/_bootstrap/bootstrap-agents-toolchain.sh

# Create a new client mission
~/work/_bootstrap/new-client.sh acme "Migration on-prem -> AWS"
```

## Deploy from control plane (Windows PAPERCLISERVER repo)

```powershell
# Sync to MSI _bootstrap dir
scp -i $env:USERPROFILE\.ssh\paperclip_msi -r scripts/* guigui@192.168.1.16:~/work/_bootstrap/
```

See `docs/specs/2026-05-27-agents-infra-design.md` §4-§5 for the full design.
