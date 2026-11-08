#!/usr/bin/env bash
#
# zsh-explain-autofix — one-line installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/cybercoretech/zsh-explain-autofix/main/install.sh | bash
#

set -euo pipefail

REPO_DIR="${ZEA_REPO_DIR:-$HOME/Devspace/Cybercore/tooling/zsh-explain-autofix}"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"
SOURCE_LINE="source \"$REPO_DIR/explain-autofix.zsh\""

echo "==> zsh-explain-autofix installer"
echo "    Target: $REPO_DIR"
echo "    zshrc:  $ZSHRC"

# Clone or update the repo
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "==> Repo exists — pulling latest"
    git -C "$REPO_DIR" pull --ff-only || true
else
    echo "==> Cloning repository"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone https://github.com/cybercoretech/zsh-explain-autofix.git "$REPO_DIR"
fi

# Add source line to zshrc if not already present
if ! grep -qF "zsh-explain-autofix/explain-autofix.zsh" "$ZSHRC" 2>/dev/null; then
    echo "==> Appending source line to $ZSHRC"
    printf '\n# zsh-explain-autofix (Alt+E error diagnostic)\nsource "%s"\n' "$REPO_DIR/explain-autofix.zsh" >> "$ZSHRC"
else
    echo "==> Source line already in $ZSHRC"
fi

echo
echo "==> Done! Restart your shell or run:"
echo "    source $ZSHRC"
echo
echo "Then press Alt+E after any failed command."
