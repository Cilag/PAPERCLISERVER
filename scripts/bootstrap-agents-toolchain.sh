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

# ─── MAIN ──────────────────────────────────────────────────────────────────
main() {
  log INFO "Starting agents toolchain bootstrap"
  install_apt_packages
  install_aws
  install_az
  log OK "Bootstrap completed"
}

main "$@"
