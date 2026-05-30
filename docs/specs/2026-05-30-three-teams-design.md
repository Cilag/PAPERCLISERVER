# Design — Réorganisation en 3 équipes (Infra / Web / Cyber)

- **Date :** 2026-05-30
- **Statut :** validé (brainstorming), en attente de relecture utilisateur
- **Contexte projet :** PAPERCLISERVER orchestre une équipe d'agents IA (Guigui Lab) tournant sur le serveur MSI. Org actuelle (Phase 2.5) : board → CEO (Infra Lead) → Tech Lead → 5 spécialistes (Cloud, System, Network, Security, DevOps). Souci connu « L2=0 » : le Tech Lead a tendance à tout faire lui-même au lieu de déléguer.

## 1. Objectif

Passer d'une équipe infra unique à **3 équipes parallèles** au sein du même lab, chacune avec son **Team Lead** sous le Tech Lead, pour traiter des missions de bout en bout (ex. « réaliser un site web hébergé ») :

- **🖥️ Infra** — hébergement (serveur/VM, réseau, domaine, CI/CD de déploiement).
- **💻 Web** — code applicatif (frontend + backend + QA).
- **🛡️ Cyber** — audit de sécurité du code avec **note /10** et boucle de correction.

La structure à 3 leads vise aussi à corriger le gap de délégation « L2=0 » en distribuant explicitement la coordination.

## 2. Organigramme

```
board
 └─ CEO                       [existant, réutilisé — relations client, cadrage, livraison]
     └─ Tech Lead             [existant, réutilisé — cohérence technique, orchestre les 3 leads]
         ├─ Infra Lead        [NOUVEAU]
         │    ├─ Cloud Architect      [existant → reportsTo = Infra Lead]
         │    ├─ System Engineer      [existant → reportsTo = Infra Lead]
         │    ├─ Network Engineer     [existant → reportsTo = Infra Lead]
         │    └─ DevOps / SRE         [existant → reportsTo = Infra Lead]
         ├─ Web Lead          [NOUVEAU]
         │    ├─ Frontend Engineer    [NOUVEAU]
         │    ├─ Backend Engineer     [NOUVEAU]
         │    └─ Fullstack / QA       [NOUVEAU]
         └─ Cybersecurity Lead [NOUVEAU]
              ├─ SOC / Blue Team       [NOUVEAU]
              ├─ Pentester / Red Team  [NOUVEAU]
              ├─ GRC / Compliance      [NOUVEAU]
              └─ Security Engineer     [existant → MIGRE de l'infra vers la cyber, reportsTo = Cyber Lead]
```

**Bilan :** 9 nouveaux agents (3 leads + 6 spécialistes), 5 agents repointés/migrés, CEO + Tech Lead inchangés.

**Renommage :** le titre « Infra Lead » porté par le CEO disparaît. Le CEO redevient « CEO » (cadrage/client). Le fichier `infra-lead.AGENTS.md` actuel (= instructions CEO) est renommé `ceo.AGENTS.md`, et un nouveau `infra-lead.AGENTS.md` décrit le team-lead infra.

## 3. Workflow inter-équipes & boucle qualité

Mission type « site web hébergé » :

**Phase 0 — Cadrage & infra (parallèle)**
1. CEO cadre, passe la mission technique au Tech Lead (sous-issue).
2. Tech Lead délègue **en parallèle** :
   - Infra Lead → prépare l'hébergement.
   - Web Lead → prépare le code applicatif (ownership de fichiers non-chevauchant entre Frontend/Backend/QA).

**Phase 1 — Boucle qualité autonome (Web Lead ↔ Cyber Lead)**
3. Code prêt → le **Web Lead crée une sous-issue d'audit assignée directement au Cybersecurity Lead** (handoff team-to-team, sans passer par le Tech Lead).
4. Le Cyber Lead audite (voir §5 pour la stratégie tooling-first) et **consolide une note /10** + findings priorisés (CVSS).
5. **Règle de validation :**
   - **Note ≥ 8/10** → ✅ PASS. Le Cyber Lead ferme l'issue d'audit, notifie le Web Lead.
   - **Note < 8/10** → ❌ FAIL. Le Cyber Lead renvoie au Web Lead la liste des failles + suggestions. Le Web Lead corrige et relance un audit (itération suivante).
6. **Max 3 itérations.** Si toujours < 8/10 au 3ᵉ tour → escalade au Tech Lead (accepter le risque / rallonger / re-scoper).

**Phase 2 — Intégration & déploiement**
7. Code validé → Tech Lead consolide ; Infra Lead déploie sur l'hébergement préparé.
8. Tech Lead rapporte au CEO ; CEO livre au board.

### Barème de la note /10 (reproductible)

`note = max(0, 10 − pénalités)` avec pénalités par finding :

| Sévérité | Pénalité |
|----------|----------|
| Critical | −4.0 |
| High     | −2.0 |
| Medium   | −0.5 |
| Low      | −0.1 |

Seuil de passage : **≥ 8/10**.

### Traçabilité

- À chaque audit : rapport `docs/security/audit-vN.md` (N = itération) = note /10 + tableau des findings (id | file:line | sévérité | fix) + suggestions.
- Note + verdict PASS/FAIL en commentaire de l'issue d'audit Paperclip.

## 4. Conventions repo

```
app/
  frontend/          owner: Frontend Engineer
  backend/           owner: Backend Engineer
  tests/             owner: Fullstack/QA
docs/
  security/audit-vN.md   owner: Cybersecurity Lead
terraform/ ansible/      owner: équipe Infra (déploiement)
```

**Règle absolue (conservée) :** un fichier = un seul owner. La Cyber **n'édite jamais** le code applicatif : elle audite et émet des findings ; le Dev corrige. Le Web Lead applique le découpage d'ownership non-chevauchant comme le fait le Tech Lead.

## 5. Stratégie d'optimisation des tokens (qualité de production maintenue)

1. **Tooling-first, LLM-second.** Les scanners déterministes font le gros du travail ; les agents interprètent/priorisent les rapports JSON, ne relisent pas tout le code.
   - Cyber : `semgrep`, `trivy`, `gitleaks`, `npm/pip audit`, `checkov`.
   - Web/QA : `eslint`, `tsc`, tests unitaires.
2. **Audits incrémentaux.** 1er audit = complet. Itérations 2-3 = uniquement `git diff audit-v{N-1}..HEAD` + findings encore ouverts. Jamais ré-expliquer ce qui est corrigé.
3. **Fan-out paresseux.** Le Cyber Lead lance d'abord les scanners ; il n'escalade vers un spécialiste (Pentester/SOC/GRC/SecEng) que pour les zones non couvertes par l'outillage (logique métier, authz) ou les findings à confirmer. Petit diff → audit en un seul passage.
4. **Lecture scopée.** Chaque spécialiste lit uniquement les fichiers nommés dans sa sous-issue + le brief — jamais tout le repo. Règle écrite dans chaque AGENTS.md.
5. **Événementiel, pas de polling.** Heartbeat uniquement sur CEO + Tech Lead + 3 leads. Les 9 spécialistes se réveillent sur assignation (wake event) et restent dormants sinon.
6. **Rapports compacts & structurés.** Findings en tableau, pas de prose. Note /10 par barème → pas de raisonnement verbeux.
7. **Early-exit.** Itération 1 ≥ 8/10 → stop. Diff trivial → pas de fan-out.
8. **(Optionnel) Model tiering.** Spécialistes mécaniques sur modèle léger, leads/consolidation sur modèle fort — à confirmer selon les capacités de l'adaptateur `claude_local`.

## 6. Artefacts à produire / modifier

### Fichiers d'instructions (`scripts/agents/*.AGENTS.md`)

| Fichier | Statut | Rôle |
|---|---|---|
| `ceo.AGENTS.md` | renommé depuis `infra-lead.AGENTS.md` | CEO pur (cadrage/client) |
| `tech-lead.AGENTS.md` | modifié | orchestre 3 leads (au lieu de 5 spécialistes) |
| `infra-lead.AGENTS.md` | réécrit | team-lead infra (Cloud/Sys/Net/DevOps) |
| `web-lead.AGENTS.md` | nouveau | team-lead web + lance la boucle audit |
| `cybersecurity-lead.AGENTS.md` | nouveau | team-lead cyber + calcule la note /10 |
| `frontend-engineer.AGENTS.md` | nouveau | |
| `backend-engineer.AGENTS.md` | nouveau | |
| `qa-engineer.AGENTS.md` | nouveau | Fullstack/QA |
| `soc-analyst.AGENTS.md` | nouveau | Blue team |
| `pentester.AGENTS.md` | nouveau | Red team |
| `grc-analyst.AGENTS.md` | nouveau | conformité |
| `security-engineer.AGENTS.md` | modifié | migre vers cyber, reportsTo = Cyber Lead |
| `cloud-architect.AGENTS.md` | modifié | reportsTo = Infra Lead |
| `system-engineer.AGENTS.md` | modifié | reportsTo = Infra Lead |
| `network-engineer.AGENTS.md` | modifié | reportsTo = Infra Lead |
| `devops.AGENTS.md` | modifié | reportsTo = Infra Lead |

### Script de déploiement

- **`scripts/create-all-teams.sh`** (évolution de `create-infra-agents.sh`) : crée les 9 nouveaux agents via l'API Paperclip avec le bon `reportsTo`, repointe les agents existants, déploie tous les `AGENTS.md`. Idempotent.

### Documentation

- **`INSTALL.md §15`** : nouvel organigramme + étapes UI (activer le heartbeat sur les 3 nouveaux leads).

## 7. Hors périmètre (YAGNI)

- Pas de 4ᵉ équipe (data, mobile…) pour l'instant.
- Pas de model tiering tant que l'adaptateur ne l'expose pas clairement (point 8 = piste).
- Pas de refonte du mécanisme d'issues Paperclip : on réutilise sous-issues + wake events existants.
```

