#!/usr/bin/env bash
# Helper functions for idempotent install scripts.
# Source this file: `source "$(dirname "$0")/lib/check.sh"`

set -euo pipefail

# log <level> <message>
log() {
  local level="$1"; shift
  local color_reset='\033[0m'
  local color
  case "$level" in
    INFO)  color='\033[36m' ;;  # cyan
    OK)    color='\033[32m' ;;  # green
    WARN)  color='\033[33m' ;;  # yellow
    ERROR) color='\033[31m' ;;  # red
    *)     color='' ;;
  esac
  printf "${color}[%s]${color_reset} %s\n" "$level" "$*"
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

# version_extract <cmd> — best-effort version extraction
version_extract() {
  "$1" --version 2>&1 | head -1 || echo "unknown"
}
