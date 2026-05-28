#!/usr/bin/env bash
# create-infra-agents.sh
# Idempotent: ensures the specialist agents exist via the Paperclip REST API and
# deploys each agent's AGENTS.md instruction file onto disk. Run on the MSI as guigui.
#
# Org (Phase 2.5): board -> CEO (Infra Lead) -> CTO (Tech Lead) -> 5 specialists.
# - CEO and CTO are the reused demo agents (not created); instructions overwritten.
#   CEO gets infra-lead.AGENTS.md, CTO gets tech-lead.AGENTS.md.
# - Cloud/System/Network/Security: created earlier (reportsTo=CEO in DB; instructions
#   say they report to the Tech Lead — behaviour is instruction-driven).
# - DevOps Engineer: new agent, reportsTo = CTO (Tech Lead).

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

# create_agent <name> <title> <capabilities> [reportsTo] — creates if absent, echoes id
create_agent() {
  local name="$1" title="$2" caps="$3" reports="${4:-$CEO_ID}"
  local existing; existing=$(get_agent_id_by_name "$name")
  if [ -n "$existing" ]; then
    log OK "agent '$name' already exists ($existing)" >&2
    echo "$existing"; return
  fi
  log INFO "creating agent '$name' (reportsTo ${reports:0:8})" >&2
  local body
  body=$(jq -n --arg n "$name" --arg t "$title" --arg c "$caps" --arg r "$reports" \
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

log INFO "=== Ensuring specialists exist ==="
CLOUD_ID=$(create_agent "Cloud Architect"  "Cloud Architect"  "Multi-cloud architecture, IaC, sizing, FinOps")
SYS_ID=$(create_agent   "System Engineer"  "System Engineer"  "OS provisioning, hardening, Ansible, containers")
NET_ID=$(create_agent   "Network Engineer" "Network Engineer" "Network topology, VPC, VPN, firewall, DNS")
SEC_ID=$(create_agent   "Security Engineer" "Security Engineer" "Audit, IAM, compliance, secrets, threat modeling")
# New DevOps specialist, reporting to the Tech Lead (CTO)
DEVOPS_ID=$(create_agent "DevOps Engineer" "DevOps / SRE" "CI/CD, Kubernetes, supervision, observability, GitOps" "$CTO_ID")

log INFO "=== Deploying instruction files ==="
deploy_instructions "$CEO_ID"    "$AGENTS_SRC/infra-lead.AGENTS.md"
deploy_instructions "$CTO_ID"    "$AGENTS_SRC/tech-lead.AGENTS.md"
deploy_instructions "$CLOUD_ID"  "$AGENTS_SRC/cloud-architect.AGENTS.md"
deploy_instructions "$SYS_ID"    "$AGENTS_SRC/system-engineer.AGENTS.md"
deploy_instructions "$NET_ID"    "$AGENTS_SRC/network-engineer.AGENTS.md"
deploy_instructions "$SEC_ID"    "$AGENTS_SRC/security-engineer.AGENTS.md"
deploy_instructions "$DEVOPS_ID" "$AGENTS_SRC/devops.AGENTS.md"

log OK "Done. Org:"
printf '  %-20s %s\n' "Infra Lead (CEO)"  "$CEO_ID"
printf '  %-20s %s\n' "Tech Lead (CTO)"   "$CTO_ID"
printf '  %-20s %s\n' "Cloud Architect"   "$CLOUD_ID"
printf '  %-20s %s\n' "System Engineer"   "$SYS_ID"
printf '  %-20s %s\n' "Network Engineer"  "$NET_ID"
printf '  %-20s %s\n' "Security Engineer" "$SEC_ID"
printf '  %-20s %s\n' "DevOps Engineer"   "$DEVOPS_ID"
log WARN "Manual UI steps: enable heartbeat on BOTH the CEO (Infra Lead) and CTO (Tech Lead) agents."
