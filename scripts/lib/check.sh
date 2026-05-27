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
