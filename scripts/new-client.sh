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
GH_OWNER="${GH_OWNER:-Cilag}"
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
