#!/usr/bin/env bash
# bootstrap-agents-toolchain.sh
# Idempotent install of all CLIs needed by the 5 Paperclip agents.
# Target: Ubuntu 24+. Run as user `guigui` (will sudo when needed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/check.sh"

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

# ─── 2. AWS CLI v2 ─────────────────────────────────────────────────────────
install_aws() {
  if have_cmd aws && aws --version 2>&1 | grep -q "aws-cli/2\."; then
    log OK "AWS CLI v2 already installed: $(aws --version 2>&1)"
    return
  fi
  log INFO "Installing AWS CLI v2"
  local tmpdir; tmpdir=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmpdir/awscli.zip"
  unzip -q "$tmpdir/awscli.zip" -d "$tmpdir"
  sudo "$tmpdir/aws/install" --update
  rm -rf "$tmpdir"
  log OK "AWS CLI installed: $(aws --version 2>&1)"
}

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
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o "$tmpdir/install-opentofu.sh"
  chmod +x "$tmpdir/install-opentofu.sh"
  sudo "$tmpdir/install-opentofu.sh" --install-method deb
  rm -rf "$tmpdir"
  log OK "OpenTofu installed: $(tofu --version | head -1)"
}

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

# ─── MAIN ──────────────────────────────────────────────────────────────────
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

main "$@"
