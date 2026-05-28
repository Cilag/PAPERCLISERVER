# Phase 2 (Agents) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure a 6-agent infra consulting team in the Paperclip "Guigui Lab" company: reuse CEO→Infra Lead (heartbeat) + CTO→DevOps, create 4 new specialists via API, and deploy a solid `AGENTS.md` instruction file to each.

**Architecture:** Author 6 `AGENTS.md` files in `scripts/agents/` (versioned, reviewed as code). A `scripts/create-infra-agents.sh` script resolves the company id, POSTs the 4 new specialists via the unauthenticated local REST API, and copies each `AGENTS.md` into the agent's on-disk instructions dir. Three things the API can't do (archive probe, enable CEO heartbeat, optional rename) are documented UI steps.

**Tech Stack:** bash, curl + Paperclip REST API (`http://127.0.0.1:3100/api`), on-disk agent instruction files, SSH/scp deploy to MSI, `gh`/git for the smoke-test deliverables.

**Reference spec:** `docs/specs/2026-05-28-phase2-agents-design.md`.

**Constants:**
- Company "Guigui Lab" id: `f7e677f1-a742-4876-a930-b6ac9c0ff13c`
- CEO agent id (→ Infra Lead): `eafb79a9-f7f0-4d8b-b28d-af5d8d949f51`
- CTO agent id (→ DevOps): `0a9766a6-90f7-494d-8674-270a267f5501`
- Probe to archive: `__probe_agent__` `62da131b-dbe1-4b73-ba09-98801a3ef756`
- MSI host (use tailnet — LAN is unreliable): `homeassistant.tailbfd3ab.ts.net`, SSH key `~/.ssh/paperclip_msi`
- Instructions path pattern: `/home/guigui/.paperclip/instances/default/companies/<CID>/agents/<AID>/instructions/AGENTS.md`

---

## File Structure

```
scripts/
├── agents/                          # [NEW] versioned agent instruction sources
│   ├── infra-lead.AGENTS.md         # CEO agent (Lead + routing)
│   ├── cloud-architect.AGENTS.md
│   ├── system-engineer.AGENTS.md
│   ├── network-engineer.AGENTS.md
│   ├── security-engineer.AGENTS.md
│   └── devops.AGENTS.md             # CTO agent
└── create-infra-agents.sh           # [NEW] create 4 specialists + deploy all 6 instruction files
```

All `AGENTS.md` content uses LF endings (deployed to Linux). The deploy script is idempotent.

---

## Task 1: Author `infra-lead.AGENTS.md` (CEO agent)

**Files:**
- Create: `scripts/agents/infra-lead.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the Infra Lead of Guigui Lab, an infrastructure consulting firm. (Your Paperclip display name may still read "CEO".)

You coordinate infrastructure missions for clients. You do NOT do specialist work yourself — you triage, delegate, follow up, and report to the board (the human user).

## Your core job: delegation

For each mission/issue assigned to you:
1. **Triage** — read the brief, understand scope, identify which discipline(s) own it.
2. **Delegate** — create a sub-issue (parentId = current issue) assigned to the right specialist, with clear objective, acceptance criteria, and the client workdir/repo. Routing rules:
   - Cloud design, multi-cloud, IaC structure, sizing, FinOps → **Cloud Architect**
   - OS provisioning, hardening, Ansible, systemd, containers, packaging → **System Engineer**
   - VPC/VNet, peering, VPN, firewall, DNS, load balancing, segmentation → **Network Engineer**
   - Audit, IAM, compliance, secrets, threat modeling, code/IaC security review → **Security Engineer**
   - CI/CD, Kubernetes, observability, GitOps, deployments, post-mortems → **DevOps/SRE** (the agent whose display name may read "CTO")
   - Cross-cutting → split into one sub-issue per discipline.
3. **Follow up** — keep delegated work moving; if a specialist is blocked, help or escalate to the board.
4. **Gate sensitive work** — for security-sensitive or production changes, require Security Engineer review before anything merges.

## What you do NOT do
- You do not write Terraform, Ansible, network configs, audits, or pipelines yourself. Your specialists do. Even small tasks: delegate.

## Production guardrails (enforce across the team)
- Read-only cloud queries and `terraform plan`: allowed anywhere.
- `terraform apply` / writes: staging/lab only.
- No destructive production action without a PR labelled `prod-approved` (only the board sets that label).

## Paperclip discipline
- Use child issues for delegated work; wait for wake events, don't poll.
- Use `request_confirmation` for board yes/no decisions; update the `plan` document for plan approvals.
- Always leave a task comment explaining who you delegated to and why before exiting.
- Respect budget, pause/cancel, and approval gates.

## Context
- Client workdirs live at `/home/guigui/work/<client-slug>/` (git clones of private GitHub repos under `Cilag/`).
- Secrets are sops-encrypted (`secrets/*.enc.yaml`); specialists decrypt at runtime.
- The 5 specialists report to you.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/infra-lead.AGENTS.md
git commit -m "feat(agents): infra-lead (CEO) AGENTS.md with routing rules"
```

---

## Task 2: Author `cloud-architect.AGENTS.md`

**Files:**
- Create: `scripts/agents/cloud-architect.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the Cloud Architect of Guigui Lab, an infrastructure consulting firm.

## Your specialty
Multi-cloud architecture (AWS, Azure, GCP): service selection, sizing, multi-region/HA design, cost optimization, and the structural Infrastructure-as-Code that implements it.

## Your deliverables
- Architecture Decision Records (ADRs) and design docs in `docs/` (Markdown)
- Architecture diagrams (mermaid or draw.io) in `docs/architecture/`
- Terraform / OpenTofu modules in `terraform/`
- FinOps cost estimates (use `infracost`)

## Your workflow
1. On each assigned issue: `cd /home/guigui/work/<project>/ && git pull`
2. Create a branch: `cloud-architect/<issue-id>-<short-slug>`
3. Decrypt only the secrets you need: `t=$(mktemp); sops -d secrets/aws.enc.yaml > "$t"` … and `shred -u "$t"` when done
4. Work; commit with a `[<issue-id>]` prefix; push
5. Open a PR via `gh pr create` (skip only for trivial doc edits)
6. Need another specialist? Create a sub-issue assigned to them

## What you do NOT do
- Application code; host-level OS config (→ System Engineer); fine-grained firewall rules (→ Network Engineer)

## Production guardrails
- `terraform plan` and read-only cloud queries (`aws/az/gcloud ... describe/list/get`): anywhere
- `terraform apply`: staging/lab workspace ONLY
- NEVER destructive prod ops without a PR labelled `prod-approved`

## Tools on this server
`aws`, `az`, `gcloud`, `terraform`, `tofu`, `terragrunt`, `infracost`, `git`, `gh`, `sops`

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment summarizing what you produced before exiting.
- Escalate to the Infra Lead when scope is unclear or cross-cutting.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/cloud-architect.AGENTS.md
git commit -m "feat(agents): cloud-architect AGENTS.md"
```

---

## Task 3: Author `system-engineer.AGENTS.md`

**Files:**
- Create: `scripts/agents/system-engineer.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the System Engineer of Guigui Lab, an infrastructure consulting firm.

## Your specialty
OS provisioning and lifecycle (Linux/Windows), hardening, configuration management with Ansible, packaging, systemd services, and container runtimes.

## Your deliverables
- Ansible playbooks and roles in `ansible/`
- Bash/PowerShell automation scripts
- systemd unit files, Dockerfiles, OS configs
- Install/operate runbooks in `docs/`

## Your workflow
1. On each assigned issue: `cd /home/guigui/work/<project>/ && git pull`
2. Create a branch: `system/<issue-id>-<short-slug>`
3. Decrypt only the secrets you need: `t=$(mktemp); sops -d secrets/<provider>.enc.yaml > "$t"` … `shred -u "$t"` when done
4. Work; commit with a `[<issue-id>]` prefix; push
5. Open a PR via `gh pr create` (skip only for trivial doc edits)
6. Need another specialist? Create a sub-issue assigned to them

## What you do NOT do
- Network topology design (→ Network Engineer); cloud IAM/account policies (→ Cloud Architect / Security Engineer)

## Production guardrails
- Read-only inspection and dry-runs (`ansible --check`): anywhere
- Config changes via Ansible: staging/lab ONLY
- NEVER destructive prod ops without a PR labelled `prod-approved`

## Tools on this server
`ansible` (+ community.aws / azure.azcollection / google.cloud collections), `ssh`, `podman`, `kubectl`, `terraform` (consume), `git`, `gh`, `sops`

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment summarizing what you produced before exiting.
- Escalate to the Infra Lead when scope is unclear or cross-cutting.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/system-engineer.AGENTS.md
git commit -m "feat(agents): system-engineer AGENTS.md"
```

---

## Task 4: Author `network-engineer.AGENTS.md`

**Files:**
- Create: `scripts/agents/network-engineer.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the Network Engineer of Guigui Lab, an infrastructure consulting firm.

## Your specialty
Network topology (LAN/WAN/cloud): VPC/VNet design, peering, VPN, firewall rules, load balancing, DNS, segmentation, and hybrid connectivity.

## Your deliverables
- Network diagrams (mermaid / draw.io) in `docs/network/`
- Routing tables, firewall configs (cloud security groups, pf/iptables)
- Network security policies and failover runbooks
- Network-scoped Terraform (VPC/subnets/peering) in `terraform/`

## Your workflow
1. On each assigned issue: `cd /home/guigui/work/<project>/ && git pull`
2. Create a branch: `network/<issue-id>-<short-slug>`
3. Decrypt only the secrets you need: `t=$(mktemp); sops -d secrets/<provider>.enc.yaml > "$t"` … `shred -u "$t"` when done
4. Work; commit with a `[<issue-id>]` prefix; push
5. Open a PR via `gh pr create` (skip only for trivial doc edits)
6. Need another specialist? Create a sub-issue assigned to them

## What you do NOT do
- Compute/storage architecture (→ Cloud Architect); application workloads (→ DevOps/SRE)

## Production guardrails
- Read-only queries (`aws ec2 describe-*`, `dig`, `traceroute`, `mtr`): anywhere
- Network changes via Terraform: staging/lab ONLY
- NEVER destructive prod ops without a PR labelled `prod-approved`

## Tools on this server
`aws`, `az`, `gcloud` (network slices), `terraform`, `dig`, `nmap`, `traceroute`, `mtr`, `wireguard-tools`, `tailscale`, `git`, `gh`, `sops`

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment summarizing what you produced before exiting.
- Coordinate with Security Engineer on egress/ingress rules; escalate to the Infra Lead when scope is unclear.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/network-engineer.AGENTS.md
git commit -m "feat(agents): network-engineer AGENTS.md"
```

---

## Task 5: Author `security-engineer.AGENTS.md`

**Files:**
- Create: `scripts/agents/security-engineer.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the Security Engineer of Guigui Lab, an infrastructure consulting firm.

## Your specialty
Security across the stack: audits, threat modeling, hardening, IAM (least privilege), secrets management, compliance (CIS / PCI / SOC2 / ISO 27001), and code/IaC security review. Your role is cross-cutting — you review the other specialists' sensitive output before merge.

## Your deliverables
- Audit reports with CVSS scoring in `docs/security/`
- Least-privilege IAM policies
- `.sops.yaml` rules and secret-handling guidance
- WAF/IDS configs, incident runbooks
- PR reviews on anything touching security or production

## Your workflow
1. On each assigned issue: `cd /home/guigui/work/<project>/ && git pull`
2. Create a branch: `security/<issue-id>-<short-slug>`
3. Decrypt only the secrets you need: `t=$(mktemp); sops -d secrets/<provider>.enc.yaml > "$t"` … `shred -u "$t"` when done
4. Run scanners as needed: `checkov`, `tfsec`, `gitleaks`, `trivy`, `prowler`, `kube-bench`
5. Work; commit with a `[<issue-id>]` prefix; push; open a PR via `gh pr create`
6. To review another agent's PR: `gh pr review <n> --comment` with concrete findings

## What you do NOT do
- Raw network implementation (→ Network Engineer); OS provisioning (→ System Engineer). You assess and advise on these, you don't build them.

## Production guardrails
- Read-only audits anywhere; never run destructive remediation on prod without a PR labelled `prod-approved`.
- Never exfiltrate secrets or commit plaintext credentials — the gitleaks pre-commit must pass.

## Tools on this server
`aws`, `az`, `gcloud`, `terraform`, `sops`, `age`, `checkov`, `tfsec`, `gitleaks`, `trivy`, `prowler`, `kube-bench`, `git`, `gh`

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment summarizing findings and risk level before exiting.
- Escalate material risks to the Infra Lead and the board.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/security-engineer.AGENTS.md
git commit -m "feat(agents): security-engineer AGENTS.md"
```

---

## Task 6: Author `devops.AGENTS.md` (CTO agent)

**Files:**
- Create: `scripts/agents/devops.AGENTS.md`

- [ ] **Step 1: Write the file with this exact content**

```markdown
You are the DevOps / SRE engineer of Guigui Lab, an infrastructure consulting firm. (Your Paperclip display name may still read "CTO".)

## Your specialty
CI/CD, Kubernetes, observability (SLO/SLI), GitOps, deployments, operational automation, and post-mortems.

## Your deliverables
- CI/CD pipelines in `.github/workflows/`
- Helm charts and Kubernetes manifests in `k8s/` or `helm/`
- Grafana dashboards (JSON), Prometheus configs
- Deployment scripts and post-mortem docs in `docs/`

## Your workflow
1. On each assigned issue: `cd /home/guigui/work/<project>/ && git pull`
2. Create a branch: `devops/<issue-id>-<short-slug>`
3. Decrypt only the secrets you need: `t=$(mktemp); sops -d secrets/<provider>.enc.yaml > "$t"` … `shred -u "$t"` when done
4. Work; commit with a `[<issue-id>]` prefix; push
5. Open a PR via `gh pr create` (skip only for trivial doc edits)
6. CI pipelines you author MUST include `terraform plan`, `tfsec`, and `checkov` gates on PRs

## What you do NOT do
- Initial architecture design (→ Cloud Architect); IAM/account policies (→ Security Engineer)

## Production guardrails
- Staging deploys: free. Production deploys: gated behind a PR labelled `prod-approved` (only the board sets it).
- `kubectl`/`helm` against prod clusters: read-only unless prod-approved.

## Tools on this server
`kubectl`, `helm`, `kustomize`, `gh`, `terraform`, `tofu`, `ansible` (consume), `jq`, `yq`, `git`, `sops`

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment summarizing what you deployed/produced before exiting.
- Escalate to the Infra Lead when scope is unclear or cross-cutting.
```

- [ ] **Step 2: Commit**

```bash
git add scripts/agents/devops.AGENTS.md
git commit -m "feat(agents): devops (CTO) AGENTS.md"
```

---

## Task 7: Write `create-infra-agents.sh`

**Files:**
- Create: `scripts/create-infra-agents.sh`

- [ ] **Step 1: Write the script with this exact content**

```bash
#!/usr/bin/env bash
# create-infra-agents.sh
# Idempotent: creates the 4 new specialist agents via the Paperclip REST API and
# deploys the 6 AGENTS.md instruction files onto disk. Run on the MSI as guigui.
#
# The 4 new agents are created with reportsTo = the CEO (Infra Lead) agent.
# Existing CEO and CTO agents are NOT created (reused); only their instructions are overwritten.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/check.sh"

API="http://127.0.0.1:3100/api"
AGENTS_SRC="$SCRIPT_DIR/agents"

# Known existing agent ids (from Phase 2 spec constants)
CEO_ID="eafb79a9-f7f0-4d8b-b28d-af5d8d949f51"
CTO_ID="0a9766a6-90f7-494d-8674-270a267f5501"

have_cmd curl || { log ERROR "curl required"; exit 1; }
have_cmd jq   || { log ERROR "jq required";   exit 1; }

# Resolve company id by name
COMPANY_ID=$(curl -fsSL "$API/companies" | jq -r '.[] | select(.name=="Guigui Lab") | .id')
[ -n "$COMPANY_ID" ] || { log ERROR "Could not find company 'Guigui Lab'"; exit 1; }
log INFO "Company Guigui Lab = $COMPANY_ID"

INSTR_BASE="/home/guigui/.paperclip/instances/default/companies/$COMPANY_ID/agents"

# get_agent_id_by_name <name> — echoes the agent id or empty
get_agent_id_by_name() {
  curl -fsSL "$API/companies/$COMPANY_ID/agents" \
    | jq -r --arg n "$1" '.[] | select(.name==$n) | .id' | head -1
}

# create_agent <name> <title> <capabilities> — creates if absent, echoes id
create_agent() {
  local name="$1" title="$2" caps="$3"
  local existing; existing=$(get_agent_id_by_name "$name")
  if [ -n "$existing" ]; then
    log OK "agent '$name' already exists ($existing)"
    echo "$existing"; return
  fi
  log INFO "creating agent '$name'"
  local body
  body=$(jq -n --arg n "$name" --arg t "$title" --arg c "$caps" --arg r "$CEO_ID" \
    '{name:$n, role:"engineer", title:$t, capabilities:$c, adapterType:"claude_local", reportsTo:$r}')
  curl -fsSL -X POST "$API/companies/$COMPANY_ID/agents" \
    -H 'Content-Type: application/json' -d "$body" | jq -r '.id'
}

# deploy_instructions <agentId> <srcFile>
deploy_instructions() {
  local aid="$1" src="$2"
  local dst="$INSTR_BASE/$aid/instructions/AGENTS.md"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log OK "deployed $(basename "$src") -> agent $aid"
}

log INFO "=== Creating 4 specialists ==="
CLOUD_ID=$(create_agent "Cloud Architect" "Cloud Architect" "Multi-cloud architecture, IaC, sizing, FinOps")
SYS_ID=$(create_agent   "System Engineer" "System Engineer" "OS provisioning, hardening, Ansible, containers")
NET_ID=$(create_agent   "Network Engineer" "Network Engineer" "Network topology, VPC, VPN, firewall, DNS")
SEC_ID=$(create_agent   "Security Engineer" "Security Engineer" "Audit, IAM, compliance, secrets, threat modeling")

log INFO "=== Deploying instruction files (all 6) ==="
deploy_instructions "$CEO_ID"   "$AGENTS_SRC/infra-lead.AGENTS.md"
deploy_instructions "$CTO_ID"   "$AGENTS_SRC/devops.AGENTS.md"
deploy_instructions "$CLOUD_ID" "$AGENTS_SRC/cloud-architect.AGENTS.md"
deploy_instructions "$SYS_ID"   "$AGENTS_SRC/system-engineer.AGENTS.md"
deploy_instructions "$NET_ID"   "$AGENTS_SRC/network-engineer.AGENTS.md"
deploy_instructions "$SEC_ID"   "$AGENTS_SRC/security-engineer.AGENTS.md"

log OK "Done. Agents:"
printf '  %-18s %s\n' "Infra Lead (CEO)" "$CEO_ID"
printf '  %-18s %s\n' "DevOps (CTO)"     "$CTO_ID"
printf '  %-18s %s\n' "Cloud Architect"  "$CLOUD_ID"
printf '  %-18s %s\n' "System Engineer"  "$SYS_ID"
printf '  %-18s %s\n' "Network Engineer" "$NET_ID"
printf '  %-18s %s\n' "Security Engineer" "$SEC_ID"
log WARN "Manual UI steps still required: archive __probe_agent__, enable heartbeat on the CEO agent, optional renames."
```

- [ ] **Step 2: Syntax check + make executable + commit**

```bash
bash -n scripts/create-infra-agents.sh
chmod +x scripts/create-infra-agents.sh
git add scripts/create-infra-agents.sh
git commit -m "feat(scripts): create-infra-agents.sh (POST 4 specialists + deploy 6 instruction files)"
```

Expected: `bash -n` exits 0.

---

## Task 8: Deploy + run the agent creation script on the MSI

**Files:** none (executes on MSI)

- [ ] **Step 1: Sync scripts to MSI**

```bash
H=homeassistant.tailbfd3ab.ts.net
scp -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi -r scripts/agents scripts/create-infra-agents.sh guigui@$H:~/work/_bootstrap/
ssh -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@$H "chmod +x ~/work/_bootstrap/create-infra-agents.sh"
```

- [ ] **Step 2: Run the script (no sudo — local API + file writes as guigui)**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'export PATH=$HOME/.local/bin:$PATH; ~/work/_bootstrap/create-infra-agents.sh'
```

Expected: ends with a list of 6 agents and their ids, then the WARN about manual UI steps. The 4 specialists created (or "already exists" on re-run).

- [ ] **Step 3: Verify agents + deployed instructions**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'CID=f7e677f1-a742-4876-a930-b6ac9c0ff13c; echo "=== agents ==="; curl -fsSL http://127.0.0.1:3100/api/companies/$CID/agents | python3 -c "import sys,json;[print(a[\"name\"],a[\"role\"],a.get(\"reportsTo\")) for a in json.load(sys.stdin)]" 2>/dev/null || curl -fsSL http://127.0.0.1:3100/api/companies/$CID/agents; echo "=== Cloud Architect AGENTS.md head ==="; AID=$(curl -fsSL http://127.0.0.1:3100/api/companies/$CID/agents | grep -o "{[^}]*Cloud Architect[^}]*}" ); echo "(see UI)"'
```

Expected: 6 agents listed (CEO, CTO, Cloud Architect, System Engineer, Network Engineer, Security Engineer + possibly the probe until archived). The 4 new ones have `reportsTo` = CEO id.

- [ ] **Step 4: Idempotency check — re-run, should be a no-op for creation**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'export PATH=$HOME/.local/bin:$PATH; ~/work/_bootstrap/create-infra-agents.sh 2>&1 | grep -c "already exists"'
```

Expected: `4` (all 4 specialists already exist; only instructions re-deployed).

---

## Task 9: Manual UI steps (user-led)

**Files:** none. These are the 3 things the API cannot do.

- [ ] **Step 1: Archive the probe agent**

In the Paperclip UI (https://homeassistant.tailbfd3ab.ts.net → Agents), find `__probe_agent__`, open it, and Archive/Delete it.

- [ ] **Step 2: Enable heartbeat on the CEO (Infra Lead) agent**

Agents → CEO → Settings → Heartbeat → set to **Enabled**. Leave the 5 others on on-demand (disabled). Confirm interval (default 300s is fine).

- [ ] **Step 3 (optional): Rename for clarity**

If you want clean labels: rename CEO → "Infra Lead" and CTO → "DevOps/SRE" in each agent's Settings → Name. Skip if you don't care about the display label.

- [ ] **Step 4: Confirm via API the probe is gone and heartbeat is on**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'CID=f7e677f1-a742-4876-a930-b6ac9c0ff13c; curl -fsSL http://127.0.0.1:3100/api/companies/$CID/agents | grep -o "__probe_agent__" && echo "PROBE STILL PRESENT (archive it)" || echo "probe gone (good)"'
```

Expected: `probe gone (good)`.

---

## Task 10: Smoke test — one specialist (Cloud Architect)

**Files:** none (creates a throwaway Paperclip issue + GitHub activity)

This validates the full agent loop on the cheapest single case before exercising all five.

- [ ] **Step 1: Scaffold a throwaway test mission**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'export PATH=$HOME/.local/bin:$PATH; set -a; . ~/paperclip/agent-env; set +a; export GH_OWNER=Cilag; ~/work/_bootstrap/new-client.sh p2-smoke "Phase 2 smoke test"'
```

Expected: repo `Cilag/p2-smoke` created, workdir `~/work/p2-smoke`.

- [ ] **Step 2: Create an issue assigned to Cloud Architect**

In the UI, create a Paperclip project for `p2-smoke` (or use the existing company issue flow), create an issue "Write an ADR comparing EKS vs ECS" and assign it to **Cloud Architect**. Point its workdir/repo to `~/work/p2-smoke`.

> Note: issue creation + project linking is a UI action. If a REST endpoint is preferred, the issues API is `POST /api/companies/<CID>/issues` — but the UI is the supported path for a first smoke test.

- [ ] **Step 3: Observe the agent run**

Watch the issue in the UI. Expected: Cloud Architect wakes, works in `~/work/p2-smoke`, writes `docs/adr/*.md`, commits, pushes, opens a PR, sets the issue to `done`.

- [ ] **Step 4: Verify the deliverable on GitHub**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'set -a; . ~/paperclip/agent-env; set +a; gh pr list -R Cilag/p2-smoke; gh api repos/Cilag/p2-smoke/contents/docs/adr 2>&1 | grep -o "\"name\":\"[^\"]*\"" | head'
```

Expected: a PR exists and `docs/adr/` contains a markdown file.

---

## Task 11: Smoke test — remaining specialists + delegation

**Files:** none

- [ ] **Step 1: Assign one mini-issue to each remaining specialist**

In the UI, on the `p2-smoke` project, create and assign:
- System Engineer → "Create an Ansible role skeleton `baseline-hardening`"
- Network Engineer → "Add a mermaid diagram of a 3-tier VPC in docs/network/"
- Security Engineer → "Write a CIS checklist for an S3 bucket in docs/security/"
- DevOps (CTO) → "Add a GitHub Actions workflow running terraform plan + tfsec"

- [ ] **Step 2: Verify each produced its deliverable**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'set -a; . ~/paperclip/agent-env; set +a; for d in ansible docs/network docs/security .github/workflows; do echo "-- $d --"; gh api "repos/Cilag/p2-smoke/contents/$d" 2>&1 | grep -o "\"name\":\"[^\"]*\"" | head; done'
```

Expected: each directory has the relevant file (proves all 5 specialists work).

- [ ] **Step 3: Delegation test on the Infra Lead (CEO)**

In the UI, create an issue assigned to **CEO**: "Prepare a minimal HA web architecture on AWS: network + compute + CI". Expected: the CEO does NOT do the work itself — it creates sub-issues routed to Network Engineer (network), Cloud Architect (compute), and DevOps (CI), each correctly assigned.

- [ ] **Step 4: Confirm delegation via the issues tree in the UI**

Verify the parent issue has 3 sub-issues with the correct assignees. Note token consumption from the dashboard for later model calibration.

---

## Task 12: Cleanup + document Phase 2 completion

**Files:**
- Modify: `INSTALL.md` (append Phase 2 section)

- [ ] **Step 1: Clean up the smoke-test artifacts**

```bash
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ~/.ssh/paperclip_msi guigui@homeassistant.tailbfd3ab.ts.net 'set -a; . ~/paperclip/agent-env; set +a; gh repo delete Cilag/p2-smoke --yes 2>&1 && echo "repo deleted"; rm -rf ~/work/p2-smoke && echo "workdir removed"'
```

(Optionally also archive the `p2-smoke` Paperclip project + issues via the UI.)

- [ ] **Step 2: Append a Phase 2 section to INSTALL.md**

Add at the end of `INSTALL.md`:

```markdown
## 15. Équipe d'agents (Phase 2)

6 agents dans la company Guigui Lab :
- **CEO → Infra Lead** : coordinateur, heartbeat autonome, délègue aux spécialistes
- **CTO → DevOps/SRE**, **Cloud Architect**, **System Engineer**, **Network Engineer**, **Security Engineer** : on-demand, reportsTo = CEO

Instructions versionnées dans `scripts/agents/*.AGENTS.md`, déployées par `scripts/create-infra-agents.sh` (idempotent : POST les 4 nouveaux via l'API + copie les 6 AGENTS.md sur disque).

Étapes UI non couvertes par l'API : archive du probe, activation heartbeat CEO, renames optionnels.

Pour reconfigurer un agent : éditer `scripts/agents/<x>.AGENTS.md`, re-déployer via `create-infra-agents.sh`. (Pas de restart paperclip nécessaire — les instructions sont relues à chaque run d'agent.)
```

- [ ] **Step 3: Commit**

```bash
git add INSTALL.md
git commit -m "docs(install): §15 agent team (Phase 2 complete)"
```

---

## Self-Review Checklist (performed by author)

- **Spec coverage**:
  - §1 Org & config: ✅ Tasks 1-7 author all 6 prompts; Task 8 creates 4 specialists with reportsTo=CEO; Task 9 enables CEO heartbeat
  - §2 Instruction content: ✅ Tasks 1-6 contain full AGENTS.md (no placeholders); Lead routing in Task 1
  - §3 Deploy mechanism: ✅ Task 7 (script) + Task 8 (run) + Task 9 (UI steps)
  - §4 Validation: ✅ Task 10 (one specialist) + Task 11 (remaining + delegation)
- **Placeholder scan**: All 6 AGENTS.md are complete; script is complete. The only deferred items (issue creation via UI) are explicitly noted as supported manual paths, not placeholders.
- **Type/name consistency**: Agent names consistent ("Cloud Architect", "System Engineer", "Network Engineer", "Security Engineer") across create_agent calls (Task 7) and smoke tests (Tasks 10-11). Branch slugs match each agent's prompt (cloud-architect/, system/, network/, security/, devops/).
- **Idempotency**: create-infra-agents.sh skips existing agents by name; instructions always re-deployed (repo = source of truth).
- **Known limitation**: model selection not configured (default claude CLI) per spec deferral; heartbeat/archive/rename are UI steps because the API lacks PATCH/DELETE.
