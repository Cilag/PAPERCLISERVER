# Design — Phase 2 : Création des 5+1 agents infra

**Date** : 2026-05-28
**Author** : Guillaume (Cilag) avec assistance Claude (Opus 4.7)
**Status** : Draft v1 — pending user review
**Dépend de** : Phase 1 (toolchain) — DONE. Voir `docs/specs/2026-05-27-agents-infra-design.md` (design global) et `docs/plans/2026-05-27-agents-infra-phase1-toolchain.md`.

---

## Résumé exécutif

Configurer dans Paperclip (company "Guigui Lab") une équipe de **6 agents** pour les missions de conseil infra : un **Infra Lead** (coordinateur, heartbeat autonome) qui délègue à **5 spécialistes** on-demand (Cloud Architect, System, Network, Security, DevOps). On **réutilise les 2 agents démo existants** (CEO→Lead, CTO→DevOps) faute d'API de rename, et on **crée 4 agents** via l'API REST locale. Chaque agent reçoit un fichier d'instructions `AGENTS.md` riche, sourcé et versionné dans le repo avant déploiement. Approche **hybride scriptée** : API POST + écriture de fichiers pour ce qui est automatisable, UI pour les 3 actions que l'API ne couvre pas (archive, toggle heartbeat, renames optionnels).

---

## Contexte technique (découvertes de grounding)

| Capacité | État | Conséquence design |
|---|---|---|
| `POST /api/companies/:id/agents` | ✅ marche (testé), API locale non-authentifiée | Création des 4 nouveaux scriptable via curl |
| Agent créé via API | génère un `AGENTS.md` boilerplate auto | On écrase ce fichier avec notre contenu |
| `PATCH` / `DELETE` agents | ❌ 404 (non supporté) | Rename + archive + toggle heartbeat → via UI (ou DB) |
| Instructions agent | fichiers markdown sur disque : `.../companies/<cid>/agents/<aid>/instructions/AGENTS.md` (+ SOUL/TOOLS/HEARTBEAT optionnels) | On écrit directement `AGENTS.md` |
| Champ `model` | absent du JSON agent ; mécanisme flou | Modèle = défaut claude CLI, à tuner plus tard |
| `runtimeConfig.heartbeat.enabled` | par agent, défaut `false` (wakeOnDemand `true`) | Heartbeat activé sur CEO seul, via UI |
| Company "Guigui Lab" | id `f7e677f1-a742-4876-a930-b6ac9c0ff13c`, prefix `GUI` | Cible des opérations |
| Agents existants | CEO `eafb79a9-...` (role ceo), CTO `0a9766a6-...` (role cto) | Réutilisés |
| Probe parasite | `__probe_agent__` `62da131b-...` (role engineer) | À archiver |

---

## Décisions clés (snapshot)

| Question | Choix |
|---|---|
| Réutiliser ou recréer | Réutiliser CEO (→Lead) + CTO (→DevOps), créer 4 nouveaux |
| Structure org | Lead + 5 spécialistes, tous `reportsTo` = CEO/Lead |
| Heartbeat | CEO/Lead = autonome ; les 5 spécialistes = on-demand |
| Profondeur instructions | `AGENTS.md` solide par agent (pas de bundle SOUL/TOOLS/HEARTBEAT séparé) |
| Modèle | défaut claude CLI (tunable plus tard) |
| Application | hybride scripté (API + fichiers) + UI pour archive/heartbeat/rename |
| Probe `__probe_agent__` | archivé (UI) |

---

## Section 1 — Org & configuration

```
                    ┌─────────────────────────────┐
                    │  Toi (board / human user)   │
                    └──────────────┬──────────────┘
                                   │ assigne missions, valide PRs, pose label prod-approved
                                   ▼
                    ┌─────────────────────────────┐
                    │  CEO  →  "Infra Lead"        │  heartbeat ✅ autonome
                    │  (coordinateur, délègue)     │  reportsTo: board
                    └──────────────┬──────────────┘
            ┌──────────┬───────────┼───────────┬──────────────┐
            ▼          ▼           ▼           ▼              ▼
     ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌──────────┐
     │ Cloud    │ │ System  │ │ Network │ │ Security │ │ CTO →    │
     │ Architect│ │ Engineer│ │ Engineer│ │ Engineer │ │ DevOps   │
     │ (new)    │ │ (new)   │ │ (new)   │ │ (new)    │ │ (reused) │
     └──────────┘ └─────────┘ └─────────┘ └──────────┘ └──────────┘
       on-demand    on-demand   on-demand   on-demand    on-demand
       reportsTo: CEO (tous)
```

| Agent | Origine | role (DB) | adapterType | heartbeat | reportsTo |
|---|---|---|---|---|---|
| CEO → Infra Lead | réutilisé `eafb79a9` | ceo | claude_local | enabled | null (board) |
| CTO → DevOps/SRE | réutilisé `0a9766a6` | cto | claude_local | disabled | CEO |
| Cloud Architect | nouveau | engineer | claude_local | disabled | CEO |
| System Engineer | nouveau | engineer | claude_local | disabled | CEO |
| Network Engineer | nouveau | engineer | claude_local | disabled | CEO |
| Security Engineer | nouveau | engineer | claude_local | disabled | CEO |

> Les noms affichés "CEO"/"CTO" restent (pas de rename API). Renommage optionnel via UI (Agent settings) → "Infra Lead" / "DevOps". Fonctionnellement, c'est le contenu de `AGENTS.md` + `reportsTo` qui définissent le comportement, pas le label.

---

## Section 2 — Contenu des instructions (`AGENTS.md`)

Les 6 fichiers sont sourcés dans `scripts/agents/` du repo (revus comme du code), puis déployés. Chaque fichier suit le template du design global §2 :

### Structure commune (spécialistes)
```
You are the {ROLE} of Guigui Lab, an infrastructure consulting firm.

## Your specialty
{mission — depuis le tableau des 5 rôles du design global §2}

## Your deliverables
{livrables attendus, format : Markdown commitable, Terraform formaté, etc.}

## Your workflow
1. On each assigned issue: `git pull` in /home/guigui/work/{project}/
2. Branch: {role-slug}/{issue-id}-{slug}
3. Decrypt only the secrets you need: `sops -d secrets/<provider>.enc.yaml` (cleanup with shred)
4. Work, commit with `[{issue-id}]` prefix, push
5. Open a PR via `gh pr create` (skip only for trivial doc changes)
6. Need another specialist? Create a sub-issue assigned to them

## What you do NOT do
{liste "ne touche pas" du rôle}

## Production guardrails
- `terraform plan` and read-only cloud queries: anywhere
- `terraform apply`: staging/lab workspace ONLY
- NEVER destructive ops on prod without an approved PR labelled `prod-approved`

## Tools on this server
{CLIs pertinents du rôle}

## Paperclip discipline
- Use sub-issues for delegated/parallel work; don't poll.
- Always leave a task comment explaining what you did before exiting.
- Respect budget, pause, approval gates.
```

### Spécifique au CEO/Lead (`AGENTS.md` du CEO)
En plus de l'identité "Infra Lead" :
```
## Delegation (your core job)
You coordinate; you do NOT do specialist work yourself. For each incoming mission:
1. Triage the issue.
2. Route to the right specialist via a sub-issue (parentId = current issue):
   - Cloud design, multi-cloud, IaC structure, FinOps → Cloud Architect
   - OS provisioning, hardening, Ansible, systemd, containers → System Engineer
   - VPC/VNet, peering, VPN, firewall, DNS, LB → Network Engineer
   - Audit, IAM, compliance, secrets, threat modeling → Security Engineer
   - CI/CD, K8s, observability, GitOps, deployments → DevOps/SRE (the "CTO" agent)
   - Cross-cutting → split into sub-issues per specialist
3. Follow up on delegated work; unblock or escalate to the board.
4. On sensitive/prod changes, require Security Engineer review before merge.
Always leave a comment explaining who you delegated to and why.
```

Les 6 fichiers concrets (Cloud Architect, System, Network, Security, DevOps, Lead) seront rédigés intégralement dans le plan d'implémentation (contenu complet, pas de placeholder).

---

## Section 3 — Mécanisme de déploiement (hybride scripté)

### 3.1 Fichiers sourcés (repo)
```
scripts/agents/
├── infra-lead.AGENTS.md       # pour le CEO
├── devops.AGENTS.md           # pour le CTO
├── cloud-architect.AGENTS.md  # nouveau
├── system-engineer.AGENTS.md  # nouveau
├── network-engineer.AGENTS.md # nouveau
└── security-engineer.AGENTS.md# nouveau
```

### 3.2 Script `scripts/create-infra-agents.sh` (exécuté sur la MSI)
1. Résout `COMPANY_ID` via `GET /api/companies` (match name "Guigui Lab")
2. Pour chaque nouveau spécialiste (Cloud/System/Network/Security) :
   - `GET` agents → skip si un agent du même `name` existe déjà (idempotent)
   - sinon `POST /api/companies/:id/agents` avec `{name, role:"engineer", title, capabilities, adapterType:"claude_local", reportsTo:<CEO_ID>}`
3. Pour CHAQUE agent (les 6) : `cp scripts/agents/<x>.AGENTS.md` → `.../agents/<agentId>/instructions/AGENTS.md` (écrase boilerplate/démo)
4. Affiche les étapes UI manuelles restantes (cf 3.3)

> Idempotent : re-runnable. Les instructions sont toujours ré-écrites (source de vérité = repo).

### 3.3 Étapes UI manuelles (ce que l'API ne fait pas)
1. **Archiver** le probe `__probe_agent__` (Agents → … → Archive)
2. **Activer le heartbeat** sur l'agent CEO (Agent settings → Heartbeat → Enabled). Garder les 5 autres sur on-demand.
3. **(Optionnel)** Renommer CEO→"Infra Lead", CTO→"DevOps/SRE" (Agent settings → Name)
4. **Vérifier `reportsTo`** : les nouveaux pointent vers le CEO (réglé à la création) ; ajuster si besoin.

---

## Section 4 — Validation (smoke tests)

### 4.1 Test par spécialiste (on-demand)
Créer un project test `internal-r-and-d` (ou réutiliser un repo jetable), puis assigner une mini-issue à chaque spécialiste :
| Agent | Mini-tâche | Attendu |
|---|---|---|
| Cloud Architect | "Écris un ADR EKS vs ECS dans docs/adr/" | docs/adr/*.md commité, PR ouverte |
| System Engineer | "Crée un rôle Ansible baseline-hardening (squelette)" | ansible/roles/... commité |
| Network Engineer | "Schéma mermaid d'un VPC 3-tier dans docs/network/" | docs/network/*.md |
| Security Engineer | "Checklist CIS pour un bucket S3 dans docs/security/" | docs/security/*.md |
| DevOps (CTO) | "Workflow GitHub Actions terraform plan + tfsec" | .github/workflows/*.yml |

Critère : chaque agent pull, bosse, commit, ouvre une PR, met l'issue en `done`. Tokens raisonnables (Sonnet-class).

### 4.2 Test de délégation (CEO/Lead)
Assigner au CEO une tâche mixte : "Prépare une mini-archi web HA sur AWS : réseau + compute + CI". Attendu : le CEO crée des sub-issues correctement routées (réseau→Network, compute→Cloud Architect, CI→DevOps) et les assigne. Pas de travail fait par le CEO lui-même.

### 4.3 Critère de sortie Phase 2
- 6 agents configurés, instructions déployées
- probe archivé, heartbeat CEO actif
- 5 smoke tests spécialistes ✅
- 1 test délégation Lead ✅
- conso tokens notée (pour calibrer le modèle plus tard)

---

## Reports / "pas-encore"
- ❌ Bundle SOUL/TOOLS/HEARTBEAT séparé (AGENTS.md unique suffit)
- ❌ Tuning du modèle Sonnet/Opus par agent (défaut d'abord ; calibrer après les smoke tests)
- ❌ Heartbeat sur les spécialistes (on-demand d'abord)
- ❌ Routines Paperclip automatiques (manuel d'abord)
- ❌ Rename des agents si l'utilisateur s'en fiche du label "CEO"/"CTO"

---

## Changelog
| Version | Date | Auteur | Changements |
|---|---|---|---|
| v1 | 2026-05-28 | Guillaume + Claude | Création initiale du design Phase 2 |
