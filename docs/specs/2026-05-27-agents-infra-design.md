# Design — Agents IA pour missions infra (système / réseau / cloud)

**Date** : 2026-05-27
**Author** : Guillaume (Cilag) avec assistance Claude (Opus 4.7)
**Status** : Draft v1 — pending user review
**Scope** : Définir l'architecture, les rôles, le workflow, l'infrastructure technique et le plan d'implémentation pour une équipe de 5 agents IA Claude opérant dans Paperclip pour des missions de conseil en infra.

---

## Résumé exécutif

Construire dans Paperclip une équipe de **5 agents Claude spécialisés** (System, Network, Cloud, Security, DevOps) qui collaborent sur des missions client de conseil en infrastructure. Chaque mission = un **project Paperclip** dans la company unique "Guigui Lab", avec un repo GitHub privé dédié. Les livrables (docs, IaC Terraform, scripts, audits) sont produits sous PR. Les agents peuvent lire toute infra et écrire en staging/sandbox, **jamais en prod sans validation humaine explicite** (label PR `prod-approved` non auto-attribuable).

L'implémentation se fait en 5 phases (~7h cumulées) : toolchain → agents → scaffolding → smoke test → 1re mission réelle. Plusieurs choix avancés sont **explicitement reportés** (MCPs, lead agent, worktrees isolés, Opus par défaut, routines auto).

---

## Décisions clés (snapshot des choix utilisateur)

| Question | Choix |
|---|---|
| Usage cible | Mission client (professionnel, livrables réels) |
| Types de livrables | Documents d'architecture + Infrastructure-as-Code + Scripts/automation + Recommandations/audit |
| Accès aux infras client | Lecture partout + écriture sandbox/staging ; **jamais en prod sans approval humain** |
| Structure d'équipe | Équipe spécialisée fixe (vs généraliste / hybride / per-projet) |
| Taille équipe | 5 agents (3 core + Security + DevOps) |
| Stack cloud | AWS + Azure + GCP + on-prem (multi-cloud) |
| Isolation missions | Une seule company "Guigui Lab" + un project par client (option 2) |
| Stockage livrables | Git repo par client sur GitHub (privés) |
| Provider git | GitHub |
| Gestion secrets | **sops + age** (chiffrement par fichier, commit dans repo) |
| Modèle Claude | **Sonnet par défaut**, Opus invoqué en flag par-task quand nécessaire |
| Architecture mode collab | **Approche A** — shared workdir par project + collab via issues Paperclip ; porte de sortie vers company dédiée pour clients NDA-strict |

---

## Section 1 — Architecture globale

```
┌──────────────────────── Paperclip "Guigui Lab" (company) ───────────────────────┐
│                                                                                  │
│  ┌─ Project: client-acme ─────┐  ┌─ Project: client-beta ──┐  ┌─ Internal ──┐  │
│  │   Issues + sub-issues       │  │   Issues + sub-issues   │  │  R&D, demo  │  │
│  │   workdir: ~/work/acme/     │  │   workdir: ~/work/beta/ │  │  templates  │  │
│  │   secrets: sops .enc.yaml   │  │   secrets: sops         │  │             │  │
│  └─────────────────────────────┘  └─────────────────────────┘  └─────────────┘  │
│                                                                                  │
│       ▲                                                                          │
│       │ Issues assignées par toi (UI)                                            │
│       │                                                                          │
│  ┌────┴────────────────── 5 Agents Claude Code (local) ──────────────────────┐ │
│  │  🏗️ Cloud Architect     🖥️ System Engineer    🌐 Network Engineer          │ │
│  │  🔒 Security Engineer   ⚙️  DevOps/SRE                                      │ │
│  │  Sonnet par défaut (--model sonnet), Opus en flag par-task quand besoin     │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
       │                                                                  │
       ▼                                                                  ▼
┌───────────── GitHub ─────────────┐                  ┌── Cloud providers (per client) ──┐
│  github.com/guiguilab/client-X   │                  │  AWS / Azure / GCP / on-prem      │
│  (private, 1 repo par client)    │                  │  Read partout, write staging only │
│  PR review = ton workflow         │                  │  Credentials via sops .enc.yaml   │
└───────────────────────────────────┘                  └────────────────────────────────────┘
```

### Points-clés

- **Une company Paperclip "Guigui Lab"**, plusieurs projects (un par client). 1 project = 1 mission.
- **5 agents persistents**, partagés entre tous les projects → capitalisation d'expérience entre missions.
- **Workdir par project** sur la MSI : `~/work/<slug>/` qui est un clone du repo GitHub client.
- **Secrets sops** dans `<workdir>/secrets/*.enc.yaml` (chiffrés age, dans le repo). L'agent déchiffre au runtime via la clé age stockée hors-repo (`~/.config/sops/age/keys.txt`).
- **Dispatching manuel** au début (toi → Issue → assignee = agent X). Possibilité d'ajouter un Lead Agent plus tard (signal-driven).

### Signaux pour migrer hors de l'approche A

| Signal observé | Migration recommandée |
|---|---|
| Conflits git réguliers entre 2 agents qui éditent les mêmes fichiers | Migrer vers **approche B** (worktrees isolés par agent) |
| Tu passes plus de temps à dispatcher qu'à reviewer | Ajouter un 6e agent **Lead** (approche C) |
| Un client demande NDA strict / isolation totale | Créer une **company dédiée** pour ce client (option 1 d'isolation) |

---

## Section 2 — Les 5 agents en détail

### 🏗️ Cloud Architect

| Aspect | Détail |
|---|---|
| **Mission** | Conception multi-cloud (AWS/Azure/GCP), choix de services, sizing, coûts, multi-region/HA. IaC structurelle. |
| **Livrables** | Architecture Decision Records (ADR), schémas mermaid/draw.io, Terraform/OpenTofu modules, FinOps estimations, diagrammes C4. |
| **Modèle** | Sonnet par défaut. Opus pour design d'archi greenfield ou migration complexe (>10 services). |
| **CLIs requis** | `aws`, `az`, `gcloud`, `terraform` (et `tofu`), `terragrunt`, `infracost` |
| **MCPs utiles** (différé) | AWS MCP (read-only par défaut), terraform-registry pour docs modules |
| **Ne touche pas** | Code applicatif, configs OS niveau hôte (→ System), règles firewall fines (→ Network) |
| **Escalade vers** | Security pour validation guardrails ; Network pour topologie ; DevOps pour pipeline IaC |

### 🖥️ System Engineer

| Aspect | Détail |
|---|---|
| **Mission** | Provisioning OS (Linux/Windows), hardening, automation Ansible, packaging, services systemd, container runtime. |
| **Livrables** | Ansible playbooks/roles, scripts Bash/PowerShell, fichiers systemd, Dockerfiles, configs (`/etc/...`), runbooks d'install. |
| **Modèle** | Sonnet |
| **CLIs requis** | `ansible` (+ collections cloud), `ssh`, `terraform` (consume), `podman`/`docker`, `kubectl` (init nodes) |
| **MCPs utiles** (différé) | filesystem MCP pour gros patches, GitHub MCP pour Ansible Galaxy |
| **Ne touche pas** | Topologie réseau (→ Network), policies IAM/cloud (→ Cloud Architect/Security) |
| **Escalade vers** | DevOps pour intégration CI ; Security pour hardening conformité (CIS) |

### 🌐 Network Engineer

| Aspect | Détail |
|---|---|
| **Mission** | Topologie réseau (LAN/WAN/cloud), VPC/VNet, peering, VPN, firewall, load balancing, DNS, segmentation, SD-WAN. |
| **Livrables** | Schémas réseau (mermaid/draw.io), tables de routage, configs firewall (pf/iptables/cloud), policies réseau, runbooks failover. |
| **Modèle** | Sonnet ; Opus pour réseau multi-cloud / connectivité hybride complexe |
| **CLIs requis** | `aws`/`az`/`gcloud` (slice réseau), `terraform`, `dig`, `nmap`, `traceroute`, `mtr`, `wireguard-tools`, `tailscale` |
| **MCPs utiles** (différé) | Cloud MCPs pour inspecter VPC/subnets existants |
| **Ne touche pas** | Compute/storage (→ Cloud Architect), workloads applicatifs (→ DevOps) |
| **Escalade vers** | Security pour règles d'égress, Cloud Architect pour cost impact |

### 🔒 Security Engineer

| Aspect | Détail |
|---|---|
| **Mission** | Audit, threat modeling, hardening, IAM, secrets, compliance (CIS/PCI/SOC2/ISO27001), revues IaC, gestion vulnérabilités. |
| **Livrables** | Rapports d'audit (Markdown + scoring CVSS), policies IAM (least privilege), `.sops.yaml`, configs WAF/IDS, runbooks incident. |
| **Modèle** | Sonnet pour scans/configs ; **Opus pour threat modeling**, design IAM complexe, dossiers de conformité. |
| **CLIs requis** | `aws`/`az`/`gcloud`, `terraform`, `sops` + `age`, `prowler`, `kube-bench`, `trivy`, `gitleaks`, `checkov`, `tfsec` |
| **MCPs utiles** (différé) | GitHub MCP (PR reviews), cloud MCPs (read-only IAM/policies) |
| **Ne touche pas** | Implémentation réseau brute (→ Network), provisioning OS (→ System) |
| **Escalade vers** | Tous — rôle cross-cutting. Il review les outputs des 4 autres avant merge sur sujets sensibles. |

### ⚙️ DevOps / SRE

| Aspect | Détail |
|---|---|
| **Mission** | CI/CD, observabilité, SLO/SLI, déploiements, GitOps, K8s, automation opérationnelle, post-mortems. |
| **Livrables** | Pipelines GitHub Actions, Helm charts + manifests K8s, dashboards Grafana JSON, configs Prometheus, scripts deploy, post-mortems. |
| **Modèle** | Sonnet |
| **CLIs requis** | `kubectl`, `helm`, `kustomize`, `argocd`, `flux`, `gh`, `terraform`, `prometheus`/`promtool`, `jq`/`yq` |
| **MCPs utiles** (différé) | GitHub MCP (workflows), Prometheus MCP si dispo |
| **Ne touche pas** | Design architecture initiale (→ Cloud Architect), policies IAM (→ Security) |
| **Escalade vers** | System pour config nodes K8s ; Security pour secrets/policies cluster ; Cloud Architect pour cost de l'observability stack |

### Template de prompt système (commun aux 5)

```
Tu es {role} de Guigui Lab, une boîte de conseil en infrastructure.

## Ta spécialité
{mission détaillée du tableau}

## Tes livrables typiques
{livrables du tableau, format attendu : Markdown commitable, Terraform formaté, etc.}

## Ton workflow
1. Pour chaque issue assignée, commence par `git pull` dans /home/guigui/work/{project}/
2. Crée une branche `{role-slug}/{issue-id}-{slug}`
3. Décrypte les secrets dont tu as besoin : `sops -d secrets/aws.enc.yaml`
4. Travaille, commit avec messages clairs et préfixe `[{issue-id}]`, push
5. Ouvre une PR via `gh pr create` (sauf changements documentaires triviaux)
6. Si tu as besoin d'un autre agent, crée une sub-issue assignée à lui

## Ce que tu ne fais pas
{liste "Ne touche pas" du tableau}

## Garde-fous prod
- Tu peux faire `terraform plan` et `aws/az/gcloud get/describe/list` partout
- Tu peux `terraform apply` UNIQUEMENT dans workspace staging/lab
- Tu NE LANCES JAMAIS de commande destructive sur prod sans validation explicite
  (PR mergée avec label "prod-approved")
- Pour toute action destructive douteuse, ouvre une PR et demande review

## Hygiène secrets
- Toujours déchiffrer dans /tmp avec un nom unique (mktemp)
- Effacer (`shred -u`) à la fin de la task
- Ne JAMAIS commit de secrets en clair ; le pre-commit gitleaks doit passer

## Tes outils CLI installés sur le serveur
{liste des CLIs du tableau}
```

---

## Section 3 — Workflow & collaboration entre agents

### Cycle de vie d'une mission

```
1. Intake
   └─ Toi (UI Paperclip) → crée Project "client-acme" + repo GitHub privé acme
                          + push initial du squelette de repo (template)

2. Kick-off Issue
   └─ Toi → Issue "ACME-1: Migrer infra on-prem vers AWS"
            assignee = 🏗️ Cloud Architect
            attachments = brief client (.md ou .pdf)

3. Phase Discovery (Cloud Architect)
   └─ 🏗️ pull repo, lit le brief, fait un état des lieux
       └─ produit docs/discovery.md + commit/PR "ACME-1 Discovery"
       └─ crée sub-issues :
           ├─ ACME-1.1 → 🌐 Network "audit topologie actuelle"
           ├─ ACME-1.2 → 🖥️ System "inventaire serveurs"
           └─ ACME-1.3 → 🔒 Security "audit IAM et secrets existants"

4. Phase Design (en parallèle)
   └─ 🏗️ designe arch cible (docs/architecture/target.md + diagram)
   └─ 🌐 propose topologie cible (docs/network/target.md)
   └─ 🔒 review les drafts, propose IAM/policies (docs/security/policies.md)
       → re-passes croisées via comments sur PR

5. Phase Implementation
   └─ 🏗️ écrit terraform/modules/{vpc,compute,storage}.tf
   └─ 🖥️ écrit ansible/roles/* pour config OS post-provisioning
   └─ ⚙️ écrit .github/workflows/* (CI Terraform + Ansible)
   └─ 🔒 review chaque PR avec checkov/tfsec/gitleaks

6. Phase Validation staging
   └─ ⚙️ apply en staging via pipeline GitHub Actions
       └─ smoke tests passent
   └─ 🔒 audit staging (prowler/kube-bench)

7. Phase Prod (avec garde-fous)
   └─ Toi mergeas la PR "production rollout" avec label `prod-approved`
       → ⚙️ déclenche le déploiement prod via workflow gated
       → 🔒 re-audit post-deploy

8. Closing
   └─ Toi → ferme l'issue ACME-1 + génère le rapport final
            (auto-généré par 🏗️ basé sur l'historique d'issues)
```

### Patterns de collaboration

**Pattern A — Séquentiel** (par défaut, le plus safe)
- Tu assignes ACME-1 à 🏗️, attends sa PR, review, merge
- Puis tu assignes ACME-2 à 🖥️, etc.
- Pas de conflit git possible. Plus lent mais lisible.

**Pattern B — Parallèle disjoint** (quand pertinent)
- Tu assignes en parallèle 🌐 sur `network/*` et 🖥️ sur `compute/*`
- Convention : chaque agent ne touche **que son préfixe de path**
- Plus rapide, OK tant que les paths ne se chevauchent pas

**Pattern C — Escalade** (un agent demande à un autre)
- 🏗️ tombe sur un souci IAM → crée sub-issue assignée à 🔒
- Il attend (via heartbeat Paperclip) que 🔒 réponde avec son verdict, puis continue
- Géré nativement par Paperclip (parent issue attend ses sub-issues)

**Pattern D — Review croisée** (sur PR)
- Sur sujets sensibles (sécurité, prod), l'agent qui ouvre la PR ajoute reviewer (autre agent)
- L'autre agent commente via `gh pr review --comment`
- Tu trancheas si désaccord

### Conventions de branches et PR

```
main                              ← prod, protégée
├── feat/cloud-architect/ACME-1   ← 🏗️ travaille ici
├── feat/network/ACME-1.1         ← 🌐 sa sub-issue
├── feat/system/ACME-1.2          ← 🖥️
├── feat/security/ACME-1.3        ← 🔒
└── deploy/staging                ← tracking staging (auto-rebase main)
```

- **Branch naming** : `{role-slug}/{issue-id}-{short-slug}`
  - Role slugs : `cloud-architect`, `system`, `network`, `security`, `devops`
- **PR title** : `[ACME-1] Discovery report` (préfixe avec issue ID)
- **PR review** : au moins toi en reviewer ; si change `terraform/*` → 🔒 aussi (convention prompt)

### Guardrail "prod-approved"

- **Branche `main` protégée GitHub** : require PR review + status checks (terraform plan + tfsec + checkov)
- **Workflow de deploy prod** : gated par label PR `prod-approved` que **seul toi** peux poser (GitHub Required Reviewers natif)
- **Aucun agent** ne peut self-approuver

### Dispatching — qui assigne quoi ?

**Au début (1er-3 mois) — dispatching manuel**
- Tu lis le brief client, tu crées les premières issues, tu choisis l'assignee
- Tu apprends les patterns

**Plus tard — options d'automation**
- Ajouter un 6e agent "Project Lead" (passage en approche C)
- OU créer des **routines Paperclip** (templates) : "Mission AWS migration → crée auto les 8 premières issues avec les bons assignees"

---

## Section 4 — Infrastructure technique sur la MSI

### 4.1 CLIs à installer

**Via apt**
```bash
sudo apt install -y \
  curl jq git \
  dnsutils nmap traceroute mtr \
  wireguard-tools \
  podman buildah skopeo \
  python3-pip pipx
```

**Via scripts officiels**
```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip
unzip /tmp/awscli.zip -d /tmp && sudo /tmp/aws/install

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Google Cloud SDK
curl https://sdk.cloud.google.com | bash -s -- --install-dir=$HOME --disable-prompts

# Terraform + OpenTofu (via HashiCorp + OpenTofu repos)
# kubectl, helm, kustomize (via apt sources Kubernetes)
```

**Via binaires GitHub (dans `~/.local/bin/`, no sudo)**
- tfsec, gitleaks, kube-bench, trivy, infracost, age

**Via pipx**
```bash
pipx install ansible-core
pipx install checkov
pipx install yq
pipx install prowler
```

**Via npm (déjà fait)**
- `@anthropic-ai/claude-code` (2.1.152)

**Reproductibilité** : tous ces installs vont dans un script `bootstrap-agents-toolchain.sh` commité dans le repo `guiguilab/toolchain` GitHub — réutilisable sur autre machine.

### 4.2 MCP servers (différés)

Pas activés en Phase 1. À ajouter quand un manque clair se fait sentir.

| MCP | Quel agent | Auth | Priorité |
|---|---|---|---|
| GitHub | tous (PR, issues) | PAT scope `repo` | basse (gh CLI suffit) |
| AWS | Cloud Architect, Network, Security | profil AWS via env | moyenne |
| Azure | idem | service principal | moyenne |
| GCP | idem | SA JSON | moyenne |
| Filesystem | tous | scope workdir | basse (Read/Write/Glob/Grep suffit) |
| Sequential-thinking | Security, Cloud Architect (audits) | aucune | moyenne |

### 4.3 sops + age setup

**Génération de la clé age (une fois, pour Guigui Lab)**
```bash
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
# Note la public key affichée (age1...) — c'est ce que tu mets dans .sops.yaml
```

**Variable d'env** (dans `~/paperclip/agent-env`)
```
SOPS_AGE_KEY_FILE=/home/guigui/.config/sops/age/keys.txt
```

**`.sops.yaml` dans chaque repo client**
```yaml
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Workflow agent au runtime**
1. `TMPCRED=$(mktemp) && sops -d secrets/aws.enc.yaml > $TMPCRED`
2. `export AWS_PROFILE=acme` ou source les vars
3. Travail
4. `shred -u $TMPCRED` quand fini

**Pour clients NDA-strict** : clé age dédiée par client (chiffrement séparé), même mécanisme.

### 4.4 Structure de répertoire sur la MSI

```
/home/guigui/
├── .nvm/                                  # déjà
├── .claude/                               # déjà
├── .config/
│   ├── sops/age/keys.txt                  # clé age Guigui Lab (mode 600) [NEW]
│   ├── gcloud/                            # GCP profiles [NEW]
│   └── ...
├── .aws/                                  # [NEW]
│   ├── config                             # profils nommés (acme, beta, ...)
│   └── credentials                        # idem
├── .azure/                                # [NEW]
├── .local/bin/                            # binaires installés userspace [NEW]
├── paperclip/                             # déjà
├── .paperclip/                            # déjà
└── work/                                  # [NEW]
    ├── _bootstrap/
    │   ├── bootstrap-agents-toolchain.sh
    │   ├── new-client.sh                  # scaffold un nouveau project
    │   └── templates/repo-template/       # squelette repo client
    ├── acme/                              # repo client clone
    │   ├── .git/
    │   ├── .sops.yaml
    │   ├── README.md
    │   ├── docs/
    │   ├── terraform/
    │   ├── ansible/
    │   ├── secrets/*.enc.yaml
    │   └── .github/workflows/
    └── beta/                              # autre client
```

### 4.5 GitHub auth

- **1 PAT fine-grained** (org `guiguilab`, scopes `repo` + `workflow`)
- Stocké dans `~/paperclip/agent-env` :
  ```
  GITHUB_TOKEN=ghp_...
  GH_TOKEN=ghp_...
  ```
- `gh auth status` doit montrer "Logged in to github.com"
- Les agents font `gh pr create`, `gh pr review`, `gh repo clone` sans setup additionnel

### 4.6 Updates au systemd unit

Pas de changement de structure du unit — il charge déjà `EnvironmentFile=/home/guigui/paperclip/agent-env`. On ajoute juste les nouvelles vars :

```
# /home/guigui/paperclip/agent-env (mode 600)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...     # déjà
GITHUB_TOKEN=ghp_...                         # nouveau
GH_TOKEN=ghp_...                             # nouveau
SOPS_AGE_KEY_FILE=/home/guigui/.config/sops/age/keys.txt  # nouveau
```

**Note importante** : les creds AWS/Azure/GCP **par client** restent dans `~/work/<client>/secrets/*.enc.yaml`, déchiffrés à la volée par l'agent quand il bosse sur ce client. **Jamais en variables d'env système** (qui seraient lisibles par tous les agents simultanément).

---

## Section 5 — Plan d'implémentation par phases

### Phase 1 — Toolchain (~2h)

**Objectif** : tous les CLIs/MCPs/secrets prêts sur la MSI avant de toucher aux agents.

| Étape | Validation |
|---|---|
| Écrire et lancer `bootstrap-agents-toolchain.sh` (idempotent) | `which aws az gcloud terraform tofu kubectl helm sops age gh` → tous trouvés |
| Générer la clé age, créer `~/.config/sops/age/keys.txt` | `sops --version`, test enc/dec sur dummy |
| Créer le PAT GitHub fine-grained, ajouter `GITHUB_TOKEN` dans `agent-env`, restart paperclip | `gh auth status` dans le contexte du service |
| Ajouter `SOPS_AGE_KEY_FILE` dans `agent-env`, restart | `sops -d` marche dans le contexte du service |
| Créer `~/work/_bootstrap/` + scripts | `new-client.sh` exécute sans erreur sur un faux client |
| Commit le script bootstrap dans `guiguilab/toolchain` | re-bootstrap possible sur autre machine |

**Critère de sortie** : tous les CLIs sont là, sops marche, GitHub fonctionne, structure `~/work/` initialisée.

### Phase 2 — Agents (~1h)

**Objectif** : les 5 agents créés dans Paperclip avec leurs prompts système.

| Étape | Validation |
|---|---|
| Renommer l'agent existant **PDG** → **🏗️ Cloud Architect**, rédiger son prompt | Adapter Environment Check passe ; smoke task "écris un ADR : EKS vs ECS" |
| Renommer **CTO** → **⚙️ DevOps/SRE** (le contexte CTO match bien DevOps), nouveau prompt | Idem smoke task |
| Créer 🖥️ **System Engineer**, 🌐 **Network Engineer**, 🔒 **Security Engineer** | Test environment check pour chacun |
| Configurer `--model sonnet` par défaut dans l'adapter de chaque agent | journalctl logs montrent `sonnet` |
| Documenter dans `guiguilab/toolchain/agents/` les 5 prompts versionnés | un agent abimé peut être restauré depuis git |

**Critère de sortie** : les 5 agents existent, chacun répond correctement à un mini-test relevant son domaine.

### Phase 3 — Repo template & scaffolding (~1.5h)

**Objectif** : créer un nouveau project en 1 minute.

| Étape | Validation |
|---|---|
| Créer `guiguilab/template-client-repo` (.sops.yaml, .github/workflows, README placeholders, docs/ skel, terraform/ skel) | Tu peux cloner le template à la main |
| Script `new-client.sh <slug> <mission-title>` : crée le project Paperclip, crée le repo GitHub (`gh repo create --template`), clone dans `~/work/<slug>/`, initialise `secrets/` vide, crée la 1re issue avec brief vide | tu lances `new-client.sh test-acme "Migrate prod"` : project + repo + issue créés en <1min |
| Documenter dans `~/work/_bootstrap/README.md` la procédure d'onboarding mission | quelqu'un d'autre pourrait suivre |

**Critère de sortie** : création d'un nouveau client en commande unique.

### Phase 4 — Smoke test end-to-end (~2h)

**Objectif** : valider tout le flow sur un faux client `test-internal`.

| Étape | Agent | Validation |
|---|---|---|
| Issue "Designer l'architecture cible AWS" | 🏗️ Cloud Architect | `docs/architecture/target.md` + diagram mermaid commitées ; PR ouverte |
| Sub-issue "Topologie VPC" auto-créée | 🌐 Network Engineer | `terraform/vpc.tf` + docs réseau |
| Sub-issue "Hardening AMI" | 🖥️ System Engineer | `ansible/roles/baseline-os/*` |
| Sub-issue "Audit IAM proposé" | 🔒 Security Engineer | `docs/security/iam-review.md` + checkov pass |
| Sub-issue "Pipeline CI" | ⚙️ DevOps | `.github/workflows/terraform.yml` + tfsec/checkov gates |
| Merge final (PR principale) | toi | repo final cohérent, doc lisible, tests CI verts |

**Critère de sortie** : flow complet marche du brief client jusqu'au merge ; tous les patterns A/B/C/D du Section 3 ont été exercés.

### Phase 5 — Première mission réelle

**Objectif** : capitaliser, ajuster les prompts d'agents et conventions au fur et à mesure.

- Choisir une mission à faible enjeu pour démarrer (idéalement où tu peux itérer sur les agents sans risque)
- Tenir un journal "ce que j'ai changé dans les prompts et pourquoi" → commits dans `guiguilab/toolchain/agents/CHANGELOG.md`
- Après 2-3 missions, surveiller les signaux de migration (cf. Section 1)

---

## Reports / "pas-encore"

Choix explicitement reportés à plus tard :

- ❌ **MCPs cloud (AWS/Azure/GCP)** — on démarre avec les CLIs ; ajouter MCPs si manque clair
- ❌ **Lead agent / approche C** — dispatch manuel le temps d'apprendre les patterns
- ❌ **Worktrees isolés / approche B** — tant que pas de conflits récurrents
- ❌ **Routines Paperclip auto** — issues créées manuellement d'abord
- ❌ **Opus par défaut** — Sonnet only ; Opus en flag par-task uniquement
- ❌ **Company dédiée par client** — option 2 (project) suffit ; passer à option 1 pour NDA-strict ponctuel

---

## Changelog

| Version | Date | Auteur | Changements |
|---|---|---|---|
| v1 | 2026-05-27 | Guillaume + Claude | Création initiale du design (5 sections + reports) |
