# {{CLIENT_SLUG}} — {{MISSION_TITLE}}

Mission scaffolded by Guigui Lab on {{DATE_ISO}}.

## Structure

- `docs/` — architecture decision records, audit reports, runbooks
- `terraform/` — IaC modules
- `ansible/` — playbooks and roles
- `secrets/*.enc.yaml` — sops-encrypted credentials (decrypted at agent runtime)
- `.github/workflows/` — CI/CD pipelines (terraform plan, tfsec, checkov, …)

## Working with secrets

```bash
# Encrypt a new file
sops -e -i secrets/aws.enc.yaml

# Decrypt to stdout
sops -d secrets/aws.enc.yaml

# Edit encrypted file in place
sops secrets/aws.enc.yaml
```

The age private key lives at `~/.config/sops/age/keys.txt` on the MSI (read by agents via `SOPS_AGE_KEY_FILE`).

## Branches & PRs

- `main` is protected (require PR review + status checks)
- Feature branches: `{role-slug}/{issue-id}-{short-slug}`
- PR title format: `[{issue-id}] {title}`
- Label `prod-approved` (poseable only by Guillaume) gates prod deploy workflows
