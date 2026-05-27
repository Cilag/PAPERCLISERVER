# Installation Paperclip AI — Serveur MSI

Documentation complète du déploiement self-hosted de [Paperclip](https://paperclip.ing) sur le laptop MSI servant de serveur.

**Date d'installation :** 2026-05-27
**Réalisée par :** Claude Code (Opus 4.7) pilotant via SSH depuis `ozoux@DESKTOP-WIN` (Windows 11).

---

## 1. Récapitulatif des versions

| Composant | Version | Source |
|---|---|---|
| OS serveur | Ubuntu 26.04 LTS (Resolute Raccoon) | apt (existant) |
| Kernel | 7.0.0-15-generic | apt |
| Architecture | x86_64 | — |
| nvm | v0.40.1 | `raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh` |
| Node.js | 20.20.2 | nvm |
| npm | 10.8.2 | bundled avec Node 20 |
| pnpm | 9.15.0 | corepack |
| **paperclipai** | **2026.525.0** | npm registry (latest stable au 2026-05-25) |
| @paperclipai/db | 2026.525.0 | dépendance |
| @embedded-postgres/linux-x64 | 18.1.0-beta.16 | dépendance (Postgres embarqué) |
| **@anthropic-ai/claude-code** | **2.1.152** | `npm install -g` (adapter Claude Code local) |

> La version `paperclipai` est **pinnée** dans `~/paperclip/package.json` — `npm` ne mettra rien à jour automatiquement.

---

## 2. Infrastructure cible

| Élément | Valeur |
|---|---|
| Hostname | `homeassistant` (le laptop fait aussi tourner Home Assistant) |
| IP LAN | `192.168.1.16` |
| User serveur | `guigui` (uid 1000, groupes : `sudo`, `adm`, `lxd`, …) |
| RAM | 14 GiB (3.2 utilisés au moment de l'install) |
| Disque `/` | 468 G — 18 G utilisés (427 G libres) |
| SELinux | absent (Ubuntu) |
| firewalld | inactif (aucune règle bloquante) |
| sudo | demande mot de passe (pas NOPASSWD) |

---

## 3. Accès SSH

### Clé dédiée générée

Fichier : `C:\Users\ozoux\.ssh\paperclip_msi` (ed25519, **sans passphrase**).

```text
Fingerprint : SHA256:g1piCyrqz44YYWZIWeXn3cAeIHrMVkFcEqShq121fDU
Commentaire : paperclip-msi-20260527
```

> Une clé dédiée a été créée parce que `homelab_ed25519` (la clé existante) a une passphrase, ce qui empêchait l'usage non interactif via `BatchMode`.

### Dépôt de la clé publique sur le serveur

```powershell
Get-Content $env:USERPROFILE\.ssh\paperclip_msi.pub | ssh guigui@192.168.1.16 "cat >> ~/.ssh/authorized_keys"
```

### Connexion (Windows → MSI)

```powershell
ssh -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16
```

---

## 4. Installation pas à pas

Toutes les commandes ci-dessous ont été exécutées sur le serveur via SSH, en tant que `guigui`.

### 4.1 Installation de nvm + Node 20 + pnpm (sans sudo)

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"
nvm install 20
nvm alias default 20
corepack enable
corepack prepare pnpm@9.15.0 --activate
# Pré-créer les dossiers attendus par systemd ReadWritePaths
mkdir -p ~/.claude ~/.config ~/.cache ~/.npm
```

Résultat :
- `~/.nvm/versions/node/v20.20.2/bin/node` → 20.20.2
- `npm` → 10.8.2
- `pnpm` → 9.15.0

### 4.2 Onboarding Paperclip (création de l'instance)

```bash
mkdir -p ~/paperclip
cd ~/paperclip
npx --yes paperclipai onboard --yes
```

L'onboarding fait :
1. Télécharge `paperclipai@2026.525.0` et toutes ses dépendances (~ qq centaines de Mo)
2. Initialise le **Postgres embarqué** dans `~/.paperclip/instances/default/db`
3. Crée le fichier de config `~/.paperclip/instances/default/config.json`
4. Génère le JWT d'agent et applique les migrations
5. Démarre le serveur sur `127.0.0.1:3100`

> ⚠️ La commande `onboard` ne rend pas la main : elle **est** le serveur. On l'a tuée juste après pour la relancer via systemd.

### 4.3 Pinning de la version

```bash
cd ~/paperclip
pnpm init                          # crée package.json
pnpm add paperclipai@2026.525.0    # pin explicite
```

À partir de là, `node_modules/paperclipai/dist/index.js` est l'entrée stable utilisée par systemd.

### 4.4 Claude Code CLI (adapter de l'agent)

Paperclip exécute les agents via le **CLI `claude` installé localement** sur le serveur (adapter "Claude Code (local)"). Sans `claude` dispo, l'agent ne peut rien faire.

Installation (sans sudo, via Node de nvm) :

```bash
npm install -g @anthropic-ai/claude-code
```

Vérification :

```bash
$ which claude
/home/guigui/.nvm/versions/node/v20.20.2/bin/claude
$ claude --version
2.1.152 (Claude Code)
```

### 4.5 Authentification Claude (OAuth Pro/Max)

Auth via abonnement claude.ai (pas via API key) → token longue durée valable **1 an**.

Lancé depuis Windows en mode interactif :

```powershell
ssh -t -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 `
  "export NVM_DIR=`$HOME/.nvm; . `$NVM_DIR/nvm.sh; claude setup-token"
```

La commande affiche une URL → tu l'ouvres dans le navigateur Windows → tu te logges sur claude.ai → le token est imprimé dans le terminal (format `sk-ant-oat01-...`).

Ce token est ensuite stocké dans un fichier env protégé sur le serveur :

```bash
# /home/guigui/paperclip/agent-env  (mode 600, owner guigui)
CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

systemd charge ce fichier via `EnvironmentFile=` (voir unit ci-dessous), donc le token est exporté dans l'environnement quand paperclip lance `claude`.

> 🔑 Pour régénérer un nouveau token (et invalider l'ancien), relancer `claude setup-token` et remplacer la valeur dans `agent-env`, puis `sudo systemctl restart paperclip`.

### 4.6 Service systemd

Fichier : `/etc/systemd/system/paperclip.service`

```ini
[Unit]
Description=Paperclip AI (tailnet bind)
After=network.target tailscaled.service
Wants=network.target tailscaled.service
StartLimitIntervalSec=120
StartLimitBurst=3

[Service]
Type=simple
User=guigui
Group=guigui
WorkingDirectory=/home/guigui/paperclip
Environment=NODE_ENV=production
Environment=PATH=/home/guigui/.nvm/versions/node/v20.20.2/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EnvironmentFile=/home/guigui/paperclip/agent-env
ExecStart=/home/guigui/.nvm/versions/node/v20.20.2/bin/node /home/guigui/paperclip/node_modules/paperclipai/dist/index.js run
Restart=on-failure
RestartSec=10
KillSignal=SIGTERM
TimeoutStopSec=45
StandardOutput=journal
StandardError=journal
SyslogIdentifier=paperclip

# Durcissement (PrivateTmp retiré : cassait le DSM Postgres embarqué)
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/home/guigui/paperclip /home/guigui/.paperclip /home/guigui/.npm /home/guigui/.claude /home/guigui/.config /home/guigui/.cache

[Install]
WantedBy=multi-user.target
```

> ⚠️ **Important** : tous les chemins listés dans `ReadWritePaths` doivent **exister** avant que systemd démarre, sinon erreur `status=226/NAMESPACE`. Créer manuellement les manquants :
> ```bash
> mkdir -p ~/.claude ~/.config ~/.cache ~/.npm
> ```

Installation et activation :

```bash
sudo install -m 644 /tmp/paperclip.service /etc/systemd/system/paperclip.service
sudo systemctl daemon-reload
sudo systemctl enable --now paperclip
```

### 4.7 Configuration initiale via l'UI (wizard onboarding)

Une fois le service up, accès à l'UI via tunnel SSH (cf. §7), puis wizard automatique en 4 étapes :

| Étape | Choix fait |
|---|---|
| Company | Nom : `Guigui Lab` — mission vide |
| Agent | Nom : `CEO`, adapter `Claude Code` (local), modèle `Default`, test environnement passé ✅ |
| Task | Task de démo "Hire your first engineer and create a hiring plan" gardée telle quelle |
| Launch | "Create & Open Issue" — l'agent a tourné 39m45s, généré 3 sous-issues + un plan d'embauche |

Après cette première run, l'UI montre :
- 1 Company : Guigui Lab
- 2 Agents : PDG (CEO renommé) + CTO (auto-créé par l'agent CEO)
- 4 Issues : GUI-1 (parent) + GUI-2/3/4 (sous-tâches)

#### Notes sur le unit

- **ExecStart** appelle directement `dist/index.js` plutôt que `node_modules/.bin/paperclipai` (qui est un shim bash et faisait planter Node avec `SyntaxError`).
- **`--bind loopback`** garantit que le binding est sur `127.0.0.1` uniquement, même si la config était changée.
- **ProtectHome=read-only** + **ReadWritePaths** : le home est en lecture seule sauf pour les répertoires explicitement listés (config, données, cache npm).
- **KillSignal=SIGINT** : Paperclip gère SIGINT proprement (fermeture des connexions Postgres).

---

## 5. État final — vérifications

| Vérif | Commande | Résultat |
|---|---|---|
| Service actif | `systemctl is-active paperclip` | `active` |
| Activé au boot | `systemctl is-enabled paperclip` | `enabled` |
| Port 3100 lié à 127.0.0.1 | `ss -tlnp \| grep 3100` | `127.0.0.1:3100` ✅ pas `0.0.0.0` |
| Postgres embarqué | `ss -tlnp \| grep 54329` | `127.0.0.1:54329` |
| Health endpoint | `curl http://127.0.0.1:3100/api/health` | HTTP 200, JSON `{"status":"ok","version":"2026.525.0",...}` |
| UI | `curl http://127.0.0.1:3100/` | HTTP 200 |

Sortie complète de `/api/health` :

```json
{
  "status": "ok",
  "version": "2026.525.0",
  "deploymentMode": "local_trusted",
  "deploymentExposure": "private",
  "authReady": true,
  "bootstrapStatus": "ready",
  "bootstrapInviteActive": false,
  "features": { "companyDeletionEnabled": true }
}
```

---

## 6. Arborescence des fichiers importants

```
/etc/systemd/system/paperclip.service     # unit systemd
/home/guigui/
├── .nvm/                                  # nvm + Node 20
│   └── versions/node/v20.20.2/bin/{node,claude}
├── paperclip/                             # installation pinnée
│   ├── package.json                       # "paperclipai": "2026.525.0"
│   ├── pnpm-lock.yaml
│   ├── agent-env                          # CLAUDE_CODE_OAUTH_TOKEN (mode 600)
│   └── node_modules/
│       └── paperclipai/dist/index.js      # entrée appelée par systemd
├── .claude/                               # config Claude Code CLI
├── .config/                               # créé pour ReadWritePaths
├── .cache/                                # créé pour ReadWritePaths
└── .paperclip/                            # données d'instance Paperclip
    └── instances/default/
        ├── config.json                    # config (JWT agent, etc.)
        ├── db/                            # cluster Postgres embarqué
        ├── secrets/master.key             # clé de chiffrement secrets
        └── data/
            ├── storage/                   # storage local (uploads)
            └── backups/                   # backups auto (60min, gardés 30j)
```

---

## 7. Accès à l'UI

### 7.1 Méthode actuelle : Tailscale Serve (HTTPS sur le tailnet)

**URL : https://homeassistant.tailbfd3ab.ts.net**

Tailscale Serve expose le `127.0.0.1:3100` local de la MSI sur le tailnet en HTTPS, avec cert Let's Encrypt auto-renouvelé. Accessible depuis n'importe quel appareil membre du tailnet, où qu'il soit (Wi-Fi maison, 4G, autre réseau).

**Setup réalisé** :

```bash
# Une fois, sur le serveur (en root)
sudo tailscale set --operator=guigui              # gérer 'tailscale serve' sans sudo
sudo tailscale serve --bg 3100                    # proxy HTTPS persistant → localhost:3100
```

> **Prérequis tailnet** :
> - HTTPS Certificates activé dans https://login.tailscale.com/admin/dns
> - MagicDNS activé (par défaut)
> - Tailscale installé+loggé sur chaque appareil client

**Vérifier le statut** :

```bash
tailscale serve status
# Sortie attendue :
# https://homeassistant.tailbfd3ab.ts.net (tailnet only)
# |-- / proxy http://127.0.0.1:3100
```

**Désactiver** (si besoin de revenir au tunnel SSH) :

```bash
tailscale serve --https=443 off
```

### 7.2 allowedHostnames (Host header)

Paperclip valide le `Host:` HTTP. Comme Tailscale Serve forwarde avec `Host: homeassistant.tailbfd3ab.ts.net`, ce hostname est ajouté à `server.allowedHostnames` dans `config.json` :

```json
"allowedHostnames": [
  "homeassistant.tailbfd3ab.ts.net",
  "homeassistant",
  "100.94.154.103",
  "localhost",
  "127.0.0.1"
]
```

### 7.3 Méthode alternative : tunnel SSH local (fallback)

Si Tailscale est down ou pour debug, on peut toujours utiliser un tunnel SSH :

```powershell
ssh -i $env:USERPROFILE\.ssh\paperclip_msi -N -L 3100:127.0.0.1:3100 guigui@192.168.1.16
```

Puis ouvrir → http://127.0.0.1:3100

### 7.4 Sécurité — pourquoi pas d'auth sur Paperclip ?

Paperclip est en mode `local_trusted` (pas d'auth UI). L'accès est sécurisé par **Tailscale** : seuls les appareils membres du tailnet (compte `Cilag@github`) peuvent atteindre la MSI sur `homeassistant.tailbfd3ab.ts.net`. Ajouter un appareil nécessite login au tailnet → c'est l'auth.

Pour passer en mode `private` (auth user/password dans Paperclip), il faudrait :
- `deploymentMode: "private"` + `bind: tailnet` dans config.json
- Créer un compte admin via l'UI au premier accès
- Toutes les routes UI deviennent gatées par login

---

## 8. Commandes utiles

### Sur le serveur

```bash
# Status / contrôle
sudo systemctl status paperclip
sudo systemctl restart paperclip
sudo systemctl stop paperclip
sudo systemctl start paperclip

# Logs
sudo journalctl -u paperclip -f                # live
sudo journalctl -u paperclip -n 200 --no-pager # 200 dernières
sudo journalctl -u paperclip --since today

# Vérifs réseau
ss -tlnp | grep -E ':3100|:54329'
curl -s http://127.0.0.1:3100/api/health | jq

# Doctor (diagnostic Paperclip)
cd ~/paperclip && node node_modules/paperclipai/dist/index.js doctor
```

### Upgrade Paperclip

```bash
cd ~/paperclip
pnpm add paperclipai@latest       # ou @2026.X.Y pour une version précise
sudo systemctl restart paperclip
sudo journalctl -u paperclip -n 50 # vérifier que ça repart bien
```

### Sauvegardes manuelles

```bash
cd ~/paperclip
node node_modules/paperclipai/dist/index.js db:backup
# backups stockés dans ~/.paperclip/instances/default/data/backups
```

---

## 9. Sécurité — état du déploiement

| Risque | Mitigation actuelle |
|---|---|
| Exposition LAN | ❌ Aucune — `bind loopback`, ports sur 127.0.0.1 |
| Exposition Internet directe | ❌ Aucune — pas de port forward |
| Exposition tailnet | ✅ Via `tailscale serve` HTTPS (mTLS WireGuard + cert Let's Encrypt) |
| Auth tailnet | Compte Cilag@github — chaque device approuvé manuellement |
| Auth Paperclip | Aucune (mode `local_trusted`) — fié à l'auth tailnet |
| Élévation de privilèges | Service tourne en user `guigui` (pas root) |
| Écriture FS arbitraire | `ProtectHome=read-only` + `ReadWritePaths` explicites |
| `/tmp` partagé | `PrivateTmp=true` (vue isolée) |
| `NoNewPrivileges` | activé |
| SSH | clé ed25519 dédiée sans passphrase, password auth toujours actif sur le serveur |

### Améliorations possibles (non faites)

- Désactiver `PasswordAuthentication` dans `sshd_config` une fois la clé confirmée fonctionnelle
- Ajouter une règle UFW pour bloquer explicitement les connexions externes vers 3100 (redondant avec bind loopback mais defense in depth)
- Mettre en place un reverse proxy avec auth si exposition LAN un jour souhaitée

---

## 10. Historique des décisions

- **Pourquoi Ubuntu et pas Rocky ?** L'utilisateur croyait que le serveur tournait sous Rocky Linux. L'inspection a révélé Ubuntu 26.04. Pas de re-install — Ubuntu fonctionne très bien pour Paperclip.
- **Pourquoi nvm et pas le paquet `nodejs` d'apt ?** Pour éviter `sudo` à chaque étape et avoir une version Node récente (Ubuntu 26.04 fournit Node 22, mais nvm permet de pinner précisément 20.20.2 si besoin de downgrade).
- **Pourquoi pinner `paperclipai@2026.525.0` ?** Pour que `systemctl restart` ne tire pas accidentellement une nouvelle version (canary ou breaking change). La mise à jour est explicite via `pnpm add`.
- **Pourquoi `--bind loopback` ?** L'utilisateur a choisi "Local uniquement" lors du setup. C'est aussi le plus sûr par défaut.
- **Pourquoi systemd et pas pm2/forever ?** Service au boot natif, logs via `journalctl`, redémarrage auto sur crash, et Ubuntu a déjà systemd.
- **Pourquoi Claude Code CLI + OAuth Pro/Max et pas une API key ?** Le user a un abonnement Claude Pro/Max — utiliser le token OAuth est gratuit (inclus dans l'abonnement) plutôt qu'une API key facturée au token. Le token est valable 1 an.
- **Pourquoi `EnvironmentFile=` plutôt qu'`Environment=` ?** Pour ne pas exposer le token OAuth dans le unit (lisible par tous les users via `systemctl cat paperclip`). Le fichier `agent-env` est en mode 600.

## 11. Conso & coûts

| Run | Tokens | Runtime | Coût $ (Pro/Max) |
|---|---|---|---|
| GUI-1 démo "Hire engineer" | 14.1M | 39m 45s | 0 (inclus abo) |

**Remarques** :
- 14M tokens est conséquent pour une démo. Pour les vraies tasks, **changer le modèle** dans Agent → Model (Sonnet < Opus en coût/quota).
- Claude Pro a des limites hebdomadaires ; Max est plus généreux. Si le quota est atteint, l'agent va échouer avec une erreur d'auth/quota.
- Suivre la conso : journalctl montre les appels claude, et `claude doctor` peut donner des stats.

## 12. Incidents rencontrés

### `database_unreachable` après plusieurs heures d'uptime

**Symptômes** : l'UI affiche `database_unreachable` en rouge, paperclip et postgres tournent toujours, ports ouverts, mais les requêtes SQL échouent avec :

```
could not open shared memory segment "/PostgreSQL.NNNN": No such file or directory
```

**Cause** : segment DSM (Dynamic Shared Memory) orphelin de Postgres dans le namespace systemd. Probablement aggravé par `PrivateTmp=true` qui isole partiellement `/dev/shm`. Déclenché par les multiples restarts rapides pendant l'expérimentation tailnet.

**Fix immédiat** : `sudo systemctl reset-failed paperclip && sudo systemctl start paperclip`

**Fix durable appliqué** :
- Retiré `PrivateTmp=true` du unit (perte mineure de durcissement, postgres reste stable)
- `StartLimitIntervalSec=120` + `StartLimitBurst=3` pour éviter les boucles de restart
- `KillSignal=SIGTERM` (au lieu de SIGINT qui n'était pas catché par paperclip)
- `TimeoutStopSec=45` pour shutdown propre de postgres

## 13. Reproduire ce setup ailleurs

Si tu refais la même installation sur un autre Ubuntu 24+ :

```bash
# 1. Sur la nouvelle machine, en tant que user non-root :
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh"
nvm install 20 && nvm alias default 20
corepack enable && corepack prepare pnpm@9.15.0 --activate
mkdir -p ~/.claude ~/.config ~/.cache ~/.npm ~/paperclip
cd ~/paperclip && pnpm init && pnpm add paperclipai@2026.525.0
npm install -g @anthropic-ai/claude-code

# 2. Auth (interactif, dans un terminal avec TTY) :
claude setup-token
# → copier le token et le mettre dans ~/paperclip/agent-env (mode 600)

# 3. Déposer le unit systemd (cf. §4.6) puis :
sudo install -m 644 /tmp/paperclip.service /etc/systemd/system/paperclip.service
sudo systemctl daemon-reload && sudo systemctl enable --now paperclip

# 4. Premier accès UI via tunnel SSH (cf. §7), puis wizard onboarding (§4.7)
```
