# Phase 1 (Toolchain) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install all CLIs, sops/age, GitHub auth and scaffolding scripts on the MSI server (Ubuntu 26.04) so the 5 Paperclip agents have everything they need to operate.

**Architecture:** Idempotent bash bootstrap script written in `PAPERCLISERVER/scripts/`, deployed to MSI via scp, executed there. Cloud creds NOT installed system-wide — only the **tooling** and the **age key** for sops decryption. Per-client credentials come later (in agent-env and sops-encrypted files in client repos).

**Tech Stack:** bash (idempotent installers), apt, pipx (Python tools), Go static binaries from GitHub releases, scp/ssh for deployment, GitHub CLI (`gh`), sops + age, Paperclip systemd service.

**Reference spec:** `docs/specs/2026-05-27-agents-infra-design.md` §4 (Infrastructure technique) and §5 Phase 1.

**Target server:** `guigui@192.168.1.16` (homeassistant.tailbfd3ab.ts.net), SSH key `~/.ssh/paperclip_msi`.

---

## File Structure

In PAPERCLISERVER (control plane, Windows):

```
scripts/
├── README.md                              # what the scripts do, how to run
├── bootstrap-agents-toolchain.sh          # main idempotent installer (run on MSI)
├── new-client.sh                          # scaffolder: new project + repo + clone
├── lib/
│   └── check.sh                            # helper functions (have_cmd, version_at_least, log)
└── templates/
    └── repo-template/                      # skeleton for client repos
        ├── .sops.yaml                      # placeholder (real key injected by new-client.sh)
        ├── README.md
        ├── docs/.gitkeep
        ├── terraform/.gitkeep
        ├── ansible/.gitkeep
        ├── secrets/.gitkeep
        └── .github/workflows/.gitkeep
```

On MSI (deployed runtime state):

```
/home/guigui/
├── .config/sops/age/keys.txt              # age private key (mode 600) [NEW]
├── .local/bin/                             # Go binaries land here [NEW]
├── paperclip/agent-env                     # updated with GH/SOPS env vars
└── work/                                   # [NEW]
    ├── _bootstrap/
    │   ├── bootstrap-agents-toolchain.sh   # deployed copy
    │   ├── new-client.sh                   # deployed copy
    │   ├── lib/check.sh
    │   └── README.md
    └── (client projects later)
```

---

## Task 1: Scripts directory + helper library

**Files:**
- Create: `scripts/README.md`
- Create: `scripts/lib/check.sh`

- [ ] **Step 1: Create `scripts/lib/check.sh`**

```bash
#!/usr/bin/env bash
# Helper functions for idempotent install scripts.
# Source this file: `source "$(dirname "$0")/lib/check.sh"`
#
# Do not source from a script that hasn't set its own strict mode;
# this library doesn't impose options (no set -euo pipefail here).

# log <level> <message>
log() {
  local level="$1"; shift
  local color_reset='\033[0m'
  local color out_fd=1
  case "$level" in
    INFO)  color='\033[36m' ;;
    OK)    color='\033[32m' ;;
    WARN)  color='\033[33m'; out_fd=2 ;;
    ERROR) color='\033[31m'; out_fd=2 ;;
    *)     color='' ;;
  esac
  printf "${color}[%s]${color_reset} %s\n" "$level" "$*" >&$out_fd
}

# have_cmd <cmd> — returns 0 if command exists in PATH
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ensure_dir <path> [mode]
ensure_dir() {
  local path="$1"
  local mode="${2:-755}"
  if [ ! -d "$path" ]; then
    mkdir -p "$path"
    chmod "$mode" "$path"
    log INFO "Created $path (mode $mode)"
  fi
}

# require_root — abort if not running as root (only used inside specific install functions)
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log ERROR "This step requires root. Re-run with sudo or as root."
    exit 1
  fi
}

# version_extract <cmd> — best-effort version extraction; returns "missing" if cmd absent
version_extract() {
  if ! have_cmd "$1"; then
    echo "missing"
    return 0
  fi
  "$1" --version 2>/dev/null | head -1 || echo "unknown"
}
```

- [ ] **Step 2: Create `scripts/README.md`**

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/check.sh scripts/README.md
git commit -m "feat(scripts): scaffold scripts dir with check.sh helpers and README"
```

---

## Task 2: Bootstrap script — header and apt packages

**Files:**
- Create: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Create bootstrap script header + apt block**

```bash
#!/usr/bin/env bash
# bootstrap-agents-toolchain.sh
# Idempotent install of all CLIs needed by the 5 Paperclip agents.
# Target: Ubuntu 24+. Run as user `guigui` (will sudo when needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/check.sh"

# Track tmpdirs for automatic cleanup on EXIT (success or failure).
# Functions that create tmpdirs append to _TMPDIRS; they no longer need to rm themselves.
_TMPDIRS=()
_cleanup_tmpdirs() {
  local d
  for d in "${_TMPDIRS[@]+"${_TMPDIRS[@]}"}"; do
    [ -d "$d" ] && rm -rf "$d"
  done
}
trap _cleanup_tmpdirs EXIT

# Ensure ~/.local/bin exists and is in PATH
ensure_dir "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    log WARN "$HOME/.local/bin not in PATH. Add to ~/.profile:"
    log WARN '  export PATH="$HOME/.local/bin:$PATH"'
    export PATH="$HOME/.local/bin:$PATH"
    ;;
esac

# ─── 1. APT base packages ──────────────────────────────────────────────────
install_apt_packages() {
  local pkgs=(
    curl jq unzip ca-certificates gnupg lsb-release
    dnsutils nmap traceroute mtr
    wireguard-tools
    podman buildah skopeo
    python3-pip pipx
    age
  )
  log INFO "Installing apt packages: ${pkgs[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${pkgs[@]}"
  log OK "apt packages installed"
}
```

- [ ] **Step 2: Add main() stub at end of file (will fill in as we add more functions)**

```bash
# ─── MAIN ──────────────────────────────────────────────────────────────────
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  log OK "Bootstrap completed"
}

main "$@"
```

- [ ] **Step 3: Make executable and commit**

```bash
chmod +x scripts/bootstrap-agents-toolchain.sh
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): bootstrap script with apt packages install"
```

---

## Task 3: Bootstrap script — AWS CLI v2

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh` (add install_aws function and call from main)

- [ ] **Step 1: Add install_aws function (after install_apt_packages)**

```bash
# ─── 2. AWS CLI v2 ─────────────────────────────────────────────────────────
install_aws() {
  if have_cmd aws && aws --version 2>&1 | grep -q "aws-cli/2\."; then
    log OK "AWS CLI v2 already installed: $(aws --version 2>&1)"
    return
  fi
  log INFO "Installing AWS CLI v2"
  local tmpdir; tmpdir=$(mktemp -d)
  _TMPDIRS+=("$tmpdir")
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmpdir/awscli.zip"
  unzip -q "$tmpdir/awscli.zip" -d "$tmpdir"
  sudo "$tmpdir/aws/install" --update
  log OK "AWS CLI installed: $(aws --version 2>&1)"
}
```

- [ ] **Step 2: Wire into main() — replace the existing main with**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add AWS CLI v2 install (idempotent)"
```

---

## Task 4: Bootstrap script — Azure CLI

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_az function**

```bash
# ─── 3. Azure CLI ──────────────────────────────────────────────────────────
install_az() {
  if have_cmd az; then
    log OK "Azure CLI already installed: $(az version --output tsv 2>/dev/null | head -1)"
    return
  fi
  log INFO "Installing Azure CLI"
  # Official Microsoft installer for Debian/Ubuntu
  curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash
  log OK "Azure CLI installed: $(az version --output tsv 2>/dev/null | head -1)"
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add Azure CLI install"
```

---

## Task 5: Bootstrap script — Google Cloud SDK

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_gcloud function**

```bash
# ─── 4. Google Cloud SDK ───────────────────────────────────────────────────
install_gcloud() {
  if have_cmd gcloud; then
    log OK "gcloud already installed: $(gcloud version --format='value(\"Google Cloud SDK\")' 2>/dev/null | head -1)"
    return
  fi
  log INFO "Installing Google Cloud SDK via apt"
  # Use Google's apt repo for clean upgrades
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
  echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y google-cloud-cli
  log OK "gcloud installed"
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  install_gcloud
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add gcloud install (apt repo, clean upgrades)"
```

---

## Task 6: Bootstrap script — Terraform + OpenTofu

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_terraform + install_opentofu functions**

```bash
# ─── 5. Terraform (HashiCorp) ──────────────────────────────────────────────
install_terraform() {
  if have_cmd terraform; then
    log OK "Terraform already installed: $(terraform version | head -1)"
    return
  fi
  log INFO "Installing Terraform via HashiCorp apt repo"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
  echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y terraform
  log OK "Terraform installed: $(terraform version | head -1)"
}

# ─── 6. OpenTofu ───────────────────────────────────────────────────────────
install_opentofu() {
  if have_cmd tofu; then
    log OK "OpenTofu already installed: $(tofu --version | head -1)"
    return
  fi
  log INFO "Installing OpenTofu via official installer"
  local tmpdir; tmpdir=$(mktemp -d)
  _TMPDIRS+=("$tmpdir")
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o "$tmpdir/install-opentofu.sh"
  chmod +x "$tmpdir/install-opentofu.sh"
  sudo "$tmpdir/install-opentofu.sh" --install-method deb
  log OK "OpenTofu installed: $(tofu --version | head -1)"
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  install_gcloud
  install_terraform
  install_opentofu
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add Terraform + OpenTofu installs"
```

---

## Task 7: Bootstrap script — kubectl, helm, kustomize, gh

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_kubernetes_clis + install_gh functions**

```bash
# ─── 7. kubectl / helm / kustomize ─────────────────────────────────────────
install_kubernetes_clis() {
  # kubectl via official k8s apt repo (specify major version 1.31 - update as needed)
  if ! have_cmd kubectl; then
    log INFO "Installing kubectl"
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
      | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y kubectl
    log OK "kubectl installed: $(kubectl version --client --output=yaml | grep gitVersion | head -1)"
  else
    log OK "kubectl already installed"
  fi

  # helm via official script
  if ! have_cmd helm; then
    log INFO "Installing helm"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log OK "helm installed: $(helm version --short)"
  else
    log OK "helm already installed"
  fi

  # kustomize binary into ~/.local/bin
  if ! have_cmd kustomize; then
    log INFO "Installing kustomize"
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
      | bash -s -- "$HOME/.local/bin"
    log OK "kustomize installed: $(kustomize version)"
  else
    log OK "kustomize already installed"
  fi
}

# ─── 8. GitHub CLI ─────────────────────────────────────────────────────────
install_gh() {
  if have_cmd gh; then
    log OK "gh already installed: $(gh --version | head -1)"
    return
  fi
  log INFO "Installing GitHub CLI"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y gh
  log OK "gh installed: $(gh --version | head -1)"
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  install_gcloud
  install_terraform
  install_opentofu
  install_kubernetes_clis
  install_gh
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add kubectl/helm/kustomize and GitHub CLI installs"
```

---

## Task 8: Bootstrap script — pipx tools (ansible, checkov, prowler, yq)

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_pipx_tools function**

```bash
# ─── 9. pipx Python tools ──────────────────────────────────────────────────
install_pipx_tools() {
  log INFO "Ensuring pipx is configured for current user"
  pipx ensurepath >/dev/null 2>&1 || true

  local pipx_pkgs=(ansible-core checkov yq prowler)
  for pkg in "${pipx_pkgs[@]}"; do
    if pipx list 2>/dev/null | grep -q "package $pkg "; then
      log OK "pipx pkg $pkg already installed"
    else
      log INFO "Installing pipx pkg: $pkg"
      pipx install "$pkg"
    fi
  done

  # ansible community collections for cloud providers
  if have_cmd ansible-galaxy; then
    log INFO "Installing ansible collections (community.aws, azure.azcollection, google.cloud)"
    ansible-galaxy collection install -U \
      community.aws \
      azure.azcollection \
      google.cloud >/dev/null
    log OK "ansible collections installed"
  fi
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  install_gcloud
  install_terraform
  install_opentofu
  install_kubernetes_clis
  install_gh
  install_pipx_tools
  log OK "Bootstrap completed"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add pipx Python tools (ansible, checkov, prowler, yq)"
```

---

## Task 9: Bootstrap script — Go binaries (sops, tfsec, gitleaks, trivy, infracost, kube-bench)

**Files:**
- Modify: `scripts/bootstrap-agents-toolchain.sh`

- [ ] **Step 1: Add install_go_binaries function (downloads from GitHub releases)**

```bash
# ─── 10. Go static binaries ────────────────────────────────────────────────
# Helper: download a tarball/zip from a GitHub release and extract the binary.
# Args: <name> <github_owner>/<repo> <release_tag_or_latest> <asset_filename_pattern> <binary_inside_archive>
install_github_binary() {
  local name="$1" repo="$2" tag="$3" asset="$4" bin_path_in_archive="$5"
  if have_cmd "$name"; then
    log OK "$name already installed"
    return
  fi
  log INFO "Installing $name from github.com/$repo ($tag)"
  local tmpdir; tmpdir=$(mktemp -d)
  _TMPDIRS+=("$tmpdir")
  local url
  if [ "$tag" = "latest" ]; then
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
          | jq -r --arg pat "$asset" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
          | head -1)
  else
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$tag" \
          | jq -r --arg pat "$asset" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
          | head -1)
  fi
  if [ -z "$url" ]; then
    log ERROR "Could not find asset matching $asset in $repo $tag"
    return 1
  fi
  curl -fsSL "$url" -o "$tmpdir/asset"
  case "$url" in
    *.tar.gz|*.tgz) tar -xzf "$tmpdir/asset" -C "$tmpdir" ;;
    *.zip)          unzip -q "$tmpdir/asset" -d "$tmpdir" ;;
    *)              cp "$tmpdir/asset" "$tmpdir/$name"; bin_path_in_archive="$name" ;;
  esac
  local resolved
  resolved=$(compgen -G "$tmpdir/$bin_path_in_archive" | head -1 || true)
  [ -z "$resolved" ] && resolved="$tmpdir/$bin_path_in_archive"
  install -m 755 "$resolved" "$HOME/.local/bin/$name"
  log OK "$name installed: $("$name" --version 2>&1 | head -1)"
}

install_go_binaries() {
  install_github_binary sops      getsops/sops      latest "sops-.*\\.linux\\.amd64$"      "sops-*.linux.amd64"
  install_github_binary tfsec     aquasecurity/tfsec latest "tfsec-linux-amd64$"            "tfsec-linux-amd64"
  install_github_binary gitleaks  gitleaks/gitleaks latest "gitleaks_.*_linux_x64\\.tar\\.gz$" "gitleaks"
  install_github_binary trivy     aquasecurity/trivy latest "trivy_.*_Linux-64bit\\.tar\\.gz$" "trivy"
  install_github_binary infracost infracost/infracost latest "infracost-linux-amd64\\.tar\\.gz$" "infracost-linux-amd64"
  install_github_binary kube-bench aquasecurity/kube-bench latest "kube-bench_.*_linux_amd64\\.tar\\.gz$" "kube-bench"
  # age is installed via apt (Task 2) on Ubuntu 24+, so no need here
}
```

- [ ] **Step 2: Wire into main()**

```bash
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  install_gcloud
  install_terraform
  install_opentofu
  install_kubernetes_clis
  install_gh
  install_pipx_tools
  install_go_binaries
  log OK "Bootstrap completed — run again anytime; it's idempotent"
}
```

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-agents-toolchain.sh
git commit -m "feat(scripts): add Go binaries (sops, tfsec, gitleaks, trivy, infracost, kube-bench)"
```

---

## Task 10: Deploy bootstrap script to MSI and run

**Files:** (no local changes, this task executes the script on the MSI)

- [ ] **Step 1: Copy scripts to MSI _bootstrap dir**

```bash
ssh -o BatchMode=yes -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "mkdir -p ~/work/_bootstrap"
scp -i ~/.ssh/paperclip_msi -r scripts/* guigui@192.168.1.16:~/work/_bootstrap/
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "chmod +x ~/work/_bootstrap/bootstrap-agents-toolchain.sh"
```

Expected: scp completes, files visible at `~/work/_bootstrap/` on MSI.

- [ ] **Step 2: Run bootstrap on MSI (will prompt for sudo password)**

```powershell
ssh -t -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "~/work/_bootstrap/bootstrap-agents-toolchain.sh 2>&1 | tee ~/work/_bootstrap/bootstrap.log"
```

Expected output ends with: `[OK] Bootstrap completed — run again anytime; it's idempotent`
Exit code: 0
The whole thing should take 3-8 minutes depending on network.

- [ ] **Step 3: Verify all CLIs installed**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "for c in aws az gcloud terraform tofu kubectl helm kustomize gh ansible checkov prowler yq sops tfsec gitleaks trivy infracost kube-bench age; do printf '%-12s ' \$c; if command -v \$c >/dev/null 2>&1; then \$c --version 2>&1 | head -1 || echo present; else echo 'MISSING'; fi; done"
```

Expected: each CLI on its own line, none should be MISSING. Note: PATH may need refresh for `~/.local/bin` — re-ssh if needed.

- [ ] **Step 4: Idempotency test — run again, should be a no-op**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "~/work/_bootstrap/bootstrap-agents-toolchain.sh 2>&1 | grep -c '^\\[OK\\] .* already installed'"
```

Expected: a number ≥ 15 (= count of "already installed" log lines). No errors.

- [ ] **Step 5: Commit deployment log**

```bash
# Pull log back into the repo for record
scp -i ~/.ssh/paperclip_msi guigui@192.168.1.16:~/work/_bootstrap/bootstrap.log scripts/bootstrap.log.example
git add scripts/bootstrap.log.example
git commit -m "chore(scripts): capture sample bootstrap.log from MSI run"
```

---

## Task 11: Generate age key on MSI and configure SOPS_AGE_KEY_FILE

**Files:**
- Create (on MSI): `/home/guigui/.config/sops/age/keys.txt`
- Modify (on MSI): `/home/guigui/paperclip/agent-env`

- [ ] **Step 1: Generate the age key (one-off)**

```powershell
ssh -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt && echo '---PUB---' && grep -E '^# public key:' ~/.config/sops/age/keys.txt"
```

Expected output ends with `# public key: age1xxxxxxxxxxxxxx...`. **Copy this public key — it goes into `.sops.yaml` of every client repo.**

- [ ] **Step 2: Add SOPS_AGE_KEY_FILE to agent-env**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "grep -q '^SOPS_AGE_KEY_FILE=' ~/paperclip/agent-env || echo 'SOPS_AGE_KEY_FILE=/home/guigui/.config/sops/age/keys.txt' >> ~/paperclip/agent-env && cat ~/paperclip/agent-env | grep -v OAUTH_TOKEN"
```

Expected: file shows `SOPS_AGE_KEY_FILE=/home/guigui/.config/sops/age/keys.txt` line, other vars unchanged (token redacted from output).

- [ ] **Step 3: Smoke test sops encrypt+decrypt**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "set -e; cd /tmp; PUBKEY=\$(grep -oE 'age1[a-z0-9]+' ~/.config/sops/age/keys.txt | head -1); echo \"hello: world\" > t.yaml; sops --age \$PUBKEY -e t.yaml > t.enc.yaml; export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt; sops -d t.enc.yaml; rm -f t.yaml t.enc.yaml"
```

Expected output: `hello: world` (decrypted back from encrypted file).

- [ ] **Step 4: Record the public key in the repo (no secret, safe to commit)**

```bash
# On Windows, save the public key for reference
echo "# Guigui Lab age public key (for .sops.yaml in client repos)" > scripts/age-pubkey.txt
# Paste the age1... key from Step 1 into this file
git add scripts/age-pubkey.txt
git commit -m "chore: record Guigui Lab age public key (for .sops.yaml in client repos)"
```

---

## Task 12: Create GitHub PAT and add to agent-env

**Files:**
- Modify (on MSI): `/home/guigui/paperclip/agent-env`

This step is **user-led** — only you can create GitHub PATs in your account.

- [ ] **Step 1: Create the PAT**

In a browser:
1. Open https://github.com/settings/personal-access-tokens/new
2. Fine-grained token name: `paperclip-agents-msi`
3. Expiration: 1 year
4. Resource owner: `guiguilab` (or your personal account if no org yet — task 15 will create the org)
5. Repository access: "All repositories" (or limit to a specific set later)
6. Permissions → Repository:
   - `Contents`: Read and write
   - `Pull requests`: Read and write
   - `Issues`: Read and write
   - `Workflows`: Read and write
   - `Metadata`: Read (auto)
7. Generate, **copy the `github_pat_...` token**

- [ ] **Step 2: Inject the token into agent-env**

Replace `<PASTE_TOKEN>` with the actual token:

```powershell
$token = "<PASTE_TOKEN>"
ssh -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "sed -i '/^GITHUB_TOKEN=/d; /^GH_TOKEN=/d' ~/paperclip/agent-env && printf 'GITHUB_TOKEN=%s\nGH_TOKEN=%s\n' '$token' '$token' >> ~/paperclip/agent-env && chmod 600 ~/paperclip/agent-env && wc -l ~/paperclip/agent-env"
```

Expected: agent-env now has at least 4 lines (CLAUDE_CODE_OAUTH_TOKEN + SOPS_AGE_KEY_FILE + GITHUB_TOKEN + GH_TOKEN). File mode 600.

- [ ] **Step 3: Validate token works (loaded manually in interactive ssh)**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "set -a; . ~/paperclip/agent-env; set +a; gh auth status 2>&1 | head -10"
```

Expected: `✓ Logged in to github.com account ...` (no "not logged in" error).

---

## Task 13: Restart Paperclip so the systemd service picks up new env vars

**Files:** none

- [ ] **Step 1: Restart paperclip via sudo**

```powershell
ssh -t -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "sudo systemctl restart paperclip && sleep 8 && sudo systemctl status paperclip --no-pager -n 5"
```

Expected: `Active: active (running)` after restart.

- [ ] **Step 2: Verify env vars visible inside service**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "MAIN_PID=\$(systemctl show paperclip -p MainPID --value); echo PID=\$MAIN_PID; sudo cat /proc/\$MAIN_PID/environ 2>/dev/null | tr '\\0' '\\n' | grep -E '^(SOPS_AGE_KEY_FILE|GH_TOKEN|GITHUB_TOKEN|CLAUDE_CODE_OAUTH_TOKEN)=' | sed 's/=.*/=***/' | sort"
```

Expected output (token values redacted):
```
CLAUDE_CODE_OAUTH_TOKEN=***
GH_TOKEN=***
GITHUB_TOKEN=***
SOPS_AGE_KEY_FILE=***
```

If something is missing → re-check Task 11/12 wrote to agent-env correctly.

---

## Task 14: Verify auth in service context using systemd-run

**Files:** none (validation only)

- [ ] **Step 1: Run `gh auth status` as guigui via systemd transient unit**

```powershell
ssh -t -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "sudo systemd-run --uid=guigui --gid=guigui --setenv=HOME=/home/guigui --property=EnvironmentFile=/home/guigui/paperclip/agent-env --pipe --wait --collect /home/guigui/.nvm/versions/node/v20.20.2/bin/node -e 'console.log(\"ok\")' || true; sudo systemd-run --uid=guigui --gid=guigui --setenv=HOME=/home/guigui --setenv=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/guigui/.local/bin --property=EnvironmentFile=/home/guigui/paperclip/agent-env --pipe --wait --collect /usr/bin/gh auth status"
```

Expected: `✓ Logged in to github.com` printed by the transient unit. (We use `systemd-run` to mimic the same env paperclip's service sees.)

- [ ] **Step 2: Run a sops decrypt as service-context to confirm SOPS_AGE_KEY_FILE works**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "set -e; cd /tmp; PUBKEY=\$(grep -oE 'age1[a-z0-9]+' ~/.config/sops/age/keys.txt | head -1); echo \"secret: hello-from-systemd\" > t.yaml; sops --age \$PUBKEY -e t.yaml > t.enc.yaml; sudo systemd-run --uid=guigui --gid=guigui --setenv=HOME=/home/guigui --setenv=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/guigui/.local/bin --property=EnvironmentFile=/home/guigui/paperclip/agent-env --pipe --wait --collect /home/guigui/.local/bin/sops -d /tmp/t.enc.yaml; rm -f /tmp/t.yaml /tmp/t.enc.yaml"
```

Expected: `secret: hello-from-systemd` printed (decrypted in service env).

---

## Task 15: Create work/ structure on MSI

**Files:**
- Create (on MSI): `~/work/_bootstrap/README.md` (deployed copy from Task 1)

- [ ] **Step 1: Re-sync scripts (in case anything changed since Task 10)**

```bash
scp -i ~/.ssh/paperclip_msi -r scripts/* guigui@192.168.1.16:~/work/_bootstrap/
```

- [ ] **Step 2: Validate structure**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "ls -la ~/work/ ~/work/_bootstrap/ ~/work/_bootstrap/templates/repo-template/"
```

Expected:
- `~/work/` contains `_bootstrap/`
- `~/work/_bootstrap/` contains `bootstrap-agents-toolchain.sh` (executable), `new-client.sh` (will be added Task 16), `lib/check.sh`, `README.md`, `templates/`
- `templates/repo-template/` contains `.sops.yaml`, `README.md`, `docs/.gitkeep`, etc.

---

## Task 16: Write new-client.sh scaffolder

**Files:**
- Create: `scripts/new-client.sh`
- Create: `scripts/templates/repo-template/.sops.yaml`
- Create: `scripts/templates/repo-template/README.md`
- Create: `scripts/templates/repo-template/docs/.gitkeep`
- Create: `scripts/templates/repo-template/terraform/.gitkeep`
- Create: `scripts/templates/repo-template/ansible/.gitkeep`
- Create: `scripts/templates/repo-template/secrets/.gitkeep`
- Create: `scripts/templates/repo-template/.github/workflows/.gitkeep`

- [ ] **Step 1: Create the repo template files**

```bash
# In PAPERCLISERVER root
mkdir -p scripts/templates/repo-template/{docs,terraform,ansible,secrets,.github/workflows}
touch scripts/templates/repo-template/docs/.gitkeep
touch scripts/templates/repo-template/terraform/.gitkeep
touch scripts/templates/repo-template/ansible/.gitkeep
touch scripts/templates/repo-template/secrets/.gitkeep
touch scripts/templates/repo-template/.github/workflows/.gitkeep
```

- [ ] **Step 2: Write `scripts/templates/repo-template/.sops.yaml`**

```yaml
# .sops.yaml — controls how secrets/*.enc.yaml are encrypted/decrypted.
# The {{AGE_PUBKEY}} placeholder is replaced by new-client.sh at scaffold time
# with the public key from ~/.config/sops/age/keys.txt on the MSI server.
creation_rules:
  - path_regex: secrets/.*\.enc\.yaml$
    age: "{{AGE_PUBKEY}}"
```

- [ ] **Step 3: Write `scripts/templates/repo-template/README.md`**

```markdown
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
```

- [ ] **Step 4: Write `scripts/new-client.sh`**

```bash
#!/usr/bin/env bash
# new-client.sh — scaffold a new client mission.
# Usage: ./new-client.sh <slug> "<mission title>"
# Effects:
#   1. Creates a private GitHub repo guiguilab/<slug>
#   2. Clones it to ~/work/<slug>/
#   3. Copies the repo-template, substituting placeholders ({{CLIENT_SLUG}}, {{MISSION_TITLE}}, {{DATE_ISO}}, {{AGE_PUBKEY}})
#   4. Initial commit + push
#   5. Prints next-step hints (no Paperclip API call yet — see future task)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/check.sh"

if [ $# -lt 2 ]; then
  log ERROR "Usage: $0 <slug> \"<mission title>\""
  exit 2
fi

SLUG="$1"
TITLE="$2"
WORK="$HOME/work/$SLUG"
TEMPLATE="$SCRIPT_DIR/templates/repo-template"
GH_OWNER="${GH_OWNER:-guiguilab}"
AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
[ -f "$AGE_KEY_FILE" ] || { log ERROR "age key not found at $AGE_KEY_FILE — run bootstrap/age-keygen first"; exit 1; }
AGE_PUBKEY=$(grep -oE 'age1[a-z0-9]+' "$AGE_KEY_FILE" | head -1)
DATE_ISO=$(date -u +%Y-%m-%d)

# Escape characters that are special in sed replacement text (\, &, and the | delimiter)
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
SLUG_ESC=$(sed_escape "$SLUG")
TITLE_ESC=$(sed_escape "$TITLE")
DATE_ESC=$(sed_escape "$DATE_ISO")
PUBKEY_ESC=$(sed_escape "$AGE_PUBKEY")

# Sanity checks
[ -d "$TEMPLATE" ] || { log ERROR "Template not found at $TEMPLATE"; exit 1; }
[ -n "$AGE_PUBKEY" ] || { log ERROR "Could not extract age public key from $AGE_KEY_FILE"; exit 1; }
have_cmd gh || { log ERROR "gh CLI required"; exit 1; }
have_cmd git || { log ERROR "git required"; exit 1; }

if [ -d "$WORK" ]; then
  log ERROR "Workdir $WORK already exists. Refusing to overwrite."
  exit 1
fi

log INFO "Creating private GitHub repo $GH_OWNER/$SLUG"
gh repo create "$GH_OWNER/$SLUG" --private --description "$TITLE"

log INFO "Cloning to $WORK"
gh repo clone "$GH_OWNER/$SLUG" "$WORK"

log INFO "Copying template + substituting placeholders"
# Copy with rsync-like behavior — preserve dirs but skip the template root itself
(cd "$TEMPLATE" && tar cf - .) | (cd "$WORK" && tar xf -)

# Substitute placeholders in text files
find "$WORK" -type f \
  -not -path "$WORK/.git/*" \
  -exec sed -i \
    -e "s|{{CLIENT_SLUG}}|$SLUG_ESC|g" \
    -e "s|{{MISSION_TITLE}}|$TITLE_ESC|g" \
    -e "s|{{DATE_ISO}}|$DATE_ESC|g" \
    -e "s|{{AGE_PUBKEY}}|$PUBKEY_ESC|g" \
    {} \;

log INFO "Initial commit"
cd "$WORK"
git add -A
git commit -m "chore: scaffold $SLUG mission from template"
git push -u origin main

log OK "Mission $SLUG scaffolded:"
log OK "  Repo:    https://github.com/$GH_OWNER/$SLUG"
log OK "  Workdir: $WORK"
log OK "  Next:    Create a Paperclip project named $SLUG and assign the kick-off issue to Cloud Architect."
```

- [ ] **Step 5: Make executable and commit all template files + script**

```bash
chmod +x scripts/new-client.sh
git add scripts/new-client.sh scripts/templates/
git commit -m "feat(scripts): add new-client.sh scaffolder and repo-template skeleton"
```

---

## Task 17: Deploy new-client.sh + test end-to-end

**Files:** none new — deploying existing files

- [ ] **Step 1: Resync to MSI**

```bash
scp -i ~/.ssh/paperclip_msi -r scripts/* guigui@192.168.1.16:~/work/_bootstrap/
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "chmod +x ~/work/_bootstrap/new-client.sh"
```

- [ ] **Step 2: Decide test slug**

Test slug: `test-internal` (will be deleted at end of Task 18). Title: `"Phase 1 acceptance test"`.

- [ ] **Step 3: Pre-flight — ensure `guiguilab` GitHub owner exists**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "set -a; . ~/paperclip/agent-env; set +a; gh api 'users/guiguilab' 2>&1 | head -5 || gh api 'orgs/guiguilab' 2>&1 | head -5"
```

If returns 404 for both, the user/org doesn't exist. Either:
- Create the `guiguilab` org at https://github.com/account/organizations/new (free for personal use)
- OR change `GH_OWNER` in new-client.sh to your personal account (e.g., `ozoux`), commit, redeploy

Expected: a JSON with `login` field for guiguilab user or org.

- [ ] **Step 4: Run new-client.sh on MSI**

```powershell
ssh -t -i $env:USERPROFILE\.ssh\paperclip_msi guigui@192.168.1.16 "set -a; . ~/paperclip/agent-env; set +a; ~/work/_bootstrap/new-client.sh test-internal 'Phase 1 acceptance test'"
```

Expected output ends with:
```
[OK] Mission test-internal scaffolded:
[OK]   Repo:    https://github.com/guiguilab/test-internal
[OK]   Workdir: /home/guigui/work/test-internal
```

- [ ] **Step 5: Verify the repo on GitHub**

In your browser, open `https://github.com/guiguilab/test-internal`. Confirm:
- Private (lock icon)
- README.md shows "test-internal — Phase 1 acceptance test"
- `.sops.yaml` shows the actual `age1...` public key (no `{{AGE_PUBKEY}}` placeholder leftover)
- Directories: `docs/`, `terraform/`, `ansible/`, `secrets/`, `.github/workflows/`

- [ ] **Step 6: Verify locally on MSI**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "cat ~/work/test-internal/.sops.yaml; echo '---README first line:'; head -1 ~/work/test-internal/README.md"
```

Expected: `.sops.yaml` has the real age pubkey, README first line is `# test-internal — Phase 1 acceptance test`.

---

## Task 18: Phase 1 acceptance test + cleanup

**Files:** none new

- [ ] **Step 1: Tick the full acceptance checklist**

Run this aggregate check on MSI:

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 'bash -s' <<'EOF'
set -e
PASS=0; FAIL=0
check() { local label="$1"; local cmd="$2"; if eval "$cmd" >/dev/null 2>&1; then echo "[PASS] $label"; PASS=$((PASS+1)); else echo "[FAIL] $label"; FAIL=$((FAIL+1)); fi; }

check "AWS CLI"            "command -v aws"
check "Azure CLI"          "command -v az"
check "gcloud"             "command -v gcloud"
check "Terraform"          "command -v terraform"
check "OpenTofu"           "command -v tofu"
check "kubectl"            "command -v kubectl"
check "helm"               "command -v helm"
check "kustomize"          "command -v kustomize"
check "gh"                 "command -v gh"
check "ansible"            "command -v ansible"
check "checkov"            "command -v checkov"
check "prowler"            "command -v prowler"
check "yq"                 "command -v yq"
check "sops"               "command -v sops"
check "age"                "command -v age"
check "tfsec"              "command -v tfsec"
check "gitleaks"           "command -v gitleaks"
check "trivy"              "command -v trivy"
check "infracost"          "command -v infracost"
check "kube-bench"         "command -v kube-bench"

check "age key present"    "test -f ~/.config/sops/age/keys.txt && test \$(stat -c '%a' ~/.config/sops/age/keys.txt) = 600"
check "agent-env has SOPS_AGE_KEY_FILE"  "grep -q '^SOPS_AGE_KEY_FILE=' ~/paperclip/agent-env"
check "agent-env has GITHUB_TOKEN"        "grep -q '^GITHUB_TOKEN=' ~/paperclip/agent-env"
check "agent-env has GH_TOKEN"            "grep -q '^GH_TOKEN=' ~/paperclip/agent-env"
check "agent-env mode 600"                "test \$(stat -c '%a' ~/paperclip/agent-env) = 600"
check "paperclip service active"          "systemctl is-active paperclip"
check "paperclip listens on 3100"         "ss -tlnp 2>/dev/null | grep -q ':3100'"
check "work/_bootstrap deployed"          "test -x ~/work/_bootstrap/bootstrap-agents-toolchain.sh && test -x ~/work/_bootstrap/new-client.sh"
check "test-internal workdir exists"      "test -d ~/work/test-internal/.git"
check "test-internal repo on GitHub"      "gh repo view guiguilab/test-internal --json name -q .name | grep -q test-internal"

echo ""
echo "==================================="
echo "  Result: PASS=$PASS  FAIL=$FAIL"
echo "==================================="
[ $FAIL -eq 0 ]
EOF
```

Expected: all checks PASS, final line `Result: PASS=28  FAIL=0`, exit code 0.

- [ ] **Step 2: Cleanup test artifacts**

```bash
ssh -i ~/.ssh/paperclip_msi guigui@192.168.1.16 "set -a; . ~/paperclip/agent-env; set +a; gh repo delete guiguilab/test-internal --yes && rm -rf ~/work/test-internal && echo 'cleanup done'"
```

Expected: `cleanup done` printed; `~/work/test-internal` removed; GitHub repo deleted.

> **Note:** `gh repo delete` requires the PAT to have `Administration: Read and write` scope OR you delete via the GitHub UI. If the CLI fails with permission error, delete the repo manually in browser and just `rm -rf ~/work/test-internal`.

- [ ] **Step 3: Final commit + push of PAPERCLISERVER repo**

```bash
git status --short
git log --oneline -10
# Make sure nothing is uncommitted
git add -A && git commit -m "chore: Phase 1 acceptance passed (28/28 checks)" --allow-empty
```

- [ ] **Step 4: Update INSTALL.md with new "Toolchain installed" section**

Add at the end of `INSTALL.md`:

```markdown
## 13. Toolchain pour les agents (Phase 1)

Installé via `scripts/bootstrap-agents-toolchain.sh` :

- Cloud: aws, az, gcloud
- IaC: terraform, tofu, ansible, checkov, infracost
- K8s: kubectl, helm, kustomize
- Security: sops, age, tfsec, gitleaks, trivy, kube-bench, prowler
- Other: gh, yq, jq, nmap, mtr, podman, wireguard-tools

Secrets pipeline : sops + age. Clé privée à `~/.config/sops/age/keys.txt` (mode 600).
Var d'env service : `SOPS_AGE_KEY_FILE` dans `agent-env`.
GitHub : PAT fine-grained sur `guiguilab`, dans `GITHUB_TOKEN` + `GH_TOKEN`.

Scaffolder mission : `~/work/_bootstrap/new-client.sh <slug> "<title>"`.
```

```bash
git add INSTALL.md
git commit -m "docs(install): add §13 Toolchain (Phase 1 complete)"
```

---

## Self-Review Checklist (performed by author)

- **Spec coverage**:
  - §4.1 CLIs: ✅ Tasks 2–9 install every CLI listed (apt + cloud + IaC + K8s + Go binaries + pipx)
  - §4.2 MCPs: deferred per spec (acceptable — no task)
  - §4.3 sops+age: ✅ Task 11
  - §4.4 Directory structure: ✅ Tasks 10, 15, 16
  - §4.5 GitHub auth: ✅ Tasks 12, 14
  - §4.6 Update systemd unit env: ✅ Task 13
  - §5 Phase 1 exit criteria: ✅ Task 18 acceptance test covers all 28 items
- **Placeholders**: No "TODO/TBD/fill in" — every step has actual commands and code
- **Type consistency**: Function names consistent throughout (`install_apt_packages`, `install_aws`, `install_az`, `install_gcloud`, `install_terraform`, `install_opentofu`, `install_kubernetes_clis`, `install_gh`, `install_pipx_tools`, `install_go_binaries`)
- **Idempotency**: Every install function checks `have_cmd <bin>` first and skips if present
