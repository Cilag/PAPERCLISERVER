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
