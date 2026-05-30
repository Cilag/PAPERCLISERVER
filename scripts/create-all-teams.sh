#!/usr/bin/env bash
# create-all-teams.sh
# Idempotent: ensures the 3-team org exists via the Paperclip REST API and deploys
# each agent's AGENTS.md. Run on the MSI as guigui.
#
# Org: board -> CEO -> Tech Lead -> {Infra Lead, Web Lead, Cybersecurity Lead} -> specialists.
# - CEO and Tech Lead are reused demo agents (not created); instructions overwritten.
# - Existing infra specialists (Cloud/System/Network/DevOps) get re-pointed to Infra Lead.
# - Security Engineer is re-pointed to the Cybersecurity Lead.
# - New agents: Infra Lead, Web Lead, Cybersecurity Lead, Frontend, Backend, QA, SOC, Pentester, GRC.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/check.sh"

API="http://127.0.0.1:3100/api"
AGENTS_SRC="$SCRIPT_DIR/agents"

# Known existing agent ids (reused demo agents)
CEO_ID="eafb79a9-f7f0-4d8b-b28d-af5d8d949f51"
CTO_ID="0a9766a6-90f7-494d-8674-270a267f5501"   # Tech Lead

have_cmd curl || { log ERROR "curl required"; exit 1; }
have_cmd jq   || { log ERROR "jq required";   exit 1; }

COMPANY_ID=$(curl -fsSL "$API/companies" | jq -r '.[] | select(.name=="Guigui Lab") | .id')
[ -n "$COMPANY_ID" ] || { log ERROR "Could not find company 'Guigui Lab'"; exit 1; }
log INFO "Company Guigui Lab = $COMPANY_ID"

INSTR_BASE="/home/guigui/.paperclip/instances/default/companies/$COMPANY_ID/agents"

get_agent_id_by_name() {
  curl -fsSL "$API/companies/$COMPANY_ID/agents" \
    | jq -r --arg n "$1" '.[] | select(.name==$n) | .id' | head -1
}

# create_agent <name> <title> <capabilities> <reportsTo> — creates if absent, echoes id
create_agent() {
  local name="$1" title="$2" caps="$3" reports="$4"
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

# repoint_agent <name> <newReportsTo> — PATCH reportsTo on an existing agent (idempotent)
repoint_agent() {
  local name="$1" reports="$2"
  local id; id=$(get_agent_id_by_name "$name")
  [ -n "$id" ] || { log WARN "cannot repoint '$name' (not found)"; return; }
  # Agent update is a FLAT route: PATCH /api/agents/<id> (not nested under /companies).
  # Non-fatal: a repoint failure must not abort instruction deployment below.
  if curl -fsSL -X PATCH "$API/agents/$id" \
       -H 'Content-Type: application/json' \
       -d "$(jq -n --arg r "$reports" '{reportsTo:$r}')" >/dev/null 2>&1; then
    log OK "repointed '$name' -> ${reports:0:8}" >&2
  else
    log WARN "repoint of '$name' failed (continuing)" >&2
  fi
  echo "$id"
}

deploy_instructions() {
  local aid="$1" src="$2"
  local dst="$INSTR_BASE/$aid/instructions/AGENTS.md"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log OK "deployed $(basename "$src") -> agent $aid"
}

log INFO "=== Creating the 3 team leads ==="
INFRA_LEAD_ID=$(create_agent "Infra Lead"          "Infra Lead"          "Hosting, servers, network, DNS, deployment CI/CD" "$CTO_ID")
WEB_LEAD_ID=$(create_agent   "Web Lead"            "Web Lead"            "Web app delivery, frontend+backend, security loop" "$CTO_ID")
CYBER_LEAD_ID=$(create_agent "Cybersecurity Lead"  "Cybersecurity Lead"  "Security audit, /10 scoring, OWASP/ISO27001" "$CTO_ID")

log INFO "=== Creating Web specialists ==="
FE_ID=$(create_agent  "Frontend Engineer" "Frontend Engineer" "React/Vue/TS UI, accessibility, client validation" "$WEB_LEAD_ID")
BE_ID=$(create_agent  "Backend Engineer"  "Backend Engineer"  "APIs, auth, DB, server-side validation" "$WEB_LEAD_ID")
QA_ID=$(create_agent  "QA Engineer"       "Fullstack / QA"    "E2E/integration tests, CI test gates" "$WEB_LEAD_ID")

log INFO "=== Creating Cyber specialists ==="
SOC_ID=$(create_agent "SOC Analyst"       "SOC / Blue Team"   "Detection, logging, SIEM, incident response" "$CYBER_LEAD_ID")
PEN_ID=$(create_agent "Pentester"         "Pentester / Red Team" "Offensive testing, OWASP, exploit PoC (lab)" "$CYBER_LEAD_ID")
GRC_ID=$(create_agent "GRC Analyst"       "GRC / Compliance"  "ISO27001, OWASP ASVS, GDPR, risk mapping" "$CYBER_LEAD_ID")

log INFO "=== Re-pointing existing specialists ==="
repoint_agent "Cloud Architect"   "$INFRA_LEAD_ID" >/dev/null
repoint_agent "System Engineer"   "$INFRA_LEAD_ID" >/dev/null
repoint_agent "Network Engineer"  "$INFRA_LEAD_ID" >/dev/null
repoint_agent "DevOps Engineer"   "$INFRA_LEAD_ID" >/dev/null
repoint_agent "Security Engineer" "$CYBER_LEAD_ID" >/dev/null

# Resolve ids of re-pointed agents for instruction deployment
CLOUD_ID=$(get_agent_id_by_name "Cloud Architect")
SYS_ID=$(get_agent_id_by_name   "System Engineer")
NET_ID=$(get_agent_id_by_name   "Network Engineer")
DEVOPS_ID=$(get_agent_id_by_name "DevOps Engineer")
SEC_ID=$(get_agent_id_by_name   "Security Engineer")

log INFO "=== Deploying instruction files ==="
deploy_instructions "$CEO_ID"        "$AGENTS_SRC/ceo.AGENTS.md"
deploy_instructions "$CTO_ID"        "$AGENTS_SRC/tech-lead.AGENTS.md"
deploy_instructions "$INFRA_LEAD_ID" "$AGENTS_SRC/infra-lead.AGENTS.md"
deploy_instructions "$WEB_LEAD_ID"   "$AGENTS_SRC/web-lead.AGENTS.md"
deploy_instructions "$CYBER_LEAD_ID" "$AGENTS_SRC/cybersecurity-lead.AGENTS.md"
deploy_instructions "$CLOUD_ID"      "$AGENTS_SRC/cloud-architect.AGENTS.md"
deploy_instructions "$SYS_ID"        "$AGENTS_SRC/system-engineer.AGENTS.md"
deploy_instructions "$NET_ID"        "$AGENTS_SRC/network-engineer.AGENTS.md"
deploy_instructions "$DEVOPS_ID"     "$AGENTS_SRC/devops.AGENTS.md"
deploy_instructions "$FE_ID"         "$AGENTS_SRC/frontend-engineer.AGENTS.md"
deploy_instructions "$BE_ID"         "$AGENTS_SRC/backend-engineer.AGENTS.md"
deploy_instructions "$QA_ID"         "$AGENTS_SRC/qa-engineer.AGENTS.md"
deploy_instructions "$SOC_ID"        "$AGENTS_SRC/soc-analyst.AGENTS.md"
deploy_instructions "$PEN_ID"        "$AGENTS_SRC/pentester.AGENTS.md"
deploy_instructions "$GRC_ID"        "$AGENTS_SRC/grc-analyst.AGENTS.md"

log OK "Done. Org:"
printf '  %-22s %s\n' "CEO"               "$CEO_ID"
printf '  %-22s %s\n' "Tech Lead"         "$CTO_ID"
printf '  %-22s %s\n' "Infra Lead"        "$INFRA_LEAD_ID"
printf '  %-22s %s\n' "Web Lead"          "$WEB_LEAD_ID"
printf '  %-22s %s\n' "Cybersecurity Lead" "$CYBER_LEAD_ID"
log WARN "Manual UI steps: enable heartbeat on CEO, Tech Lead, Infra Lead, Web Lead, Cybersecurity Lead."
