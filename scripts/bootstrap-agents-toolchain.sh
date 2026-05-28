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
    curl git jq unzip ca-certificates gnupg lsb-release
    dnsutils nmap traceroute mtr
    wireguard-tools
    podman buildah skopeo
    python3-pip pipx
    age
  )
  if dpkg -s "${pkgs[@]}" >/dev/null 2>&1; then
    log OK "apt packages already installed"
    return
  fi
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
  _TMPDIRS+=("$tmpdir")
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmpdir/awscli.zip"
  unzip -q "$tmpdir/awscli.zip" -d "$tmpdir"
  sudo "$tmpdir/aws/install" --update
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
  _TMPDIRS+=("$tmpdir")
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o "$tmpdir/install-opentofu.sh"
  chmod +x "$tmpdir/install-opentofu.sh"
  sudo "$tmpdir/install-opentofu.sh" --install-method deb
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
  install_github_binary terragrunt gruntwork-io/terragrunt latest "terragrunt_linux_amd64$" "terragrunt_linux_amd64"
  # age is installed via apt (Task 2) on Ubuntu 24+, so no need here
  # TODO Phase 2+: tailscale, argocd, flux CLIs (operational tools, install when infra context is known)
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
  install_go_binaries
  log OK "Bootstrap completed — run again anytime; it's idempotent"
}

main "$@"
