#!/usr/bin/env bash
# =============================================================================
# install.sh — claude-session-restore installer
# =============================================================================

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

G='\033[0;32m' C='\033[0;36m' Y='\033[1;33m' R='\033[0;31m' B='\033[1m' N='\033[0m'

echo -e "${B}claude-session-restore v${VERSION} — Installer${N}\n"

# --- 1. Install binary ---
INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "$INSTALL_DIR"

if cp "$SCRIPT_DIR/bin/claude-session-restore" "$INSTALL_DIR/claude-session-restore"; then
    chmod +x "$INSTALL_DIR/claude-session-restore"
    echo -e "${G}✓${N} Binary installed: ${C}${INSTALL_DIR}/claude-session-restore${N}"
else
    echo -e "${R}✗ Failed to install binary${N}"
    exit 1
fi

# Also create ghostty-session alias for backward compatibility
ln -sf "$INSTALL_DIR/claude-session-restore" "$INSTALL_DIR/ghostty-session" 2>/dev/null || true

# --- 2. Install shell hook ---
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-sessions"
mkdir -p "$DATA_DIR"

if cp "$SCRIPT_DIR/shell-hook.sh" "$DATA_DIR/shell-hook.sh"; then
    chmod +x "$DATA_DIR/shell-hook.sh"
    echo -e "${G}✓${N} Shell hook installed: ${C}${DATA_DIR}/shell-hook.sh${N}"
else
    echo -e "${R}✗ Failed to install shell hook${N}"
    exit 1
fi

# --- 3. Copy example plan (if no plan exists yet) ---
if [ ! -f "$DATA_DIR/restore-all.json" ] && [ -f "$SCRIPT_DIR/example-plan.json" ]; then
    cp "$SCRIPT_DIR/example-plan.json" "$DATA_DIR/restore-all.json"
    echo -e "${G}✓${N} Example plan copied to: ${C}${DATA_DIR}/restore-all.json${N}"
    echo -e "  ${Y}Edit this file with your actual session IDs and paths${N}"
fi

# --- 4. Add to PATH (if needed) ---
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
SHELL_RC="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && SHELL_RC="$HOME/.bashrc"

if ! grep -q 'HOME/.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# claude-session-restore: add ~/.local/bin to PATH" >> "$SHELL_RC"
    echo "$PATH_LINE" >> "$SHELL_RC"
    echo -e "${G}✓${N} Added ~/.local/bin to PATH in ${C}${SHELL_RC}${N}"
else
    echo -e "${G}✓${N} ~/.local/bin already in PATH"
fi

# --- 5. Add shell hook to shell rc ---
HOOK_LINE="[ -f \"${DATA_DIR}/shell-hook.sh\" ] && source \"${DATA_DIR}/shell-hook.sh\""

if ! grep -q 'ghostty-sessions/shell-hook.sh' "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# claude-session-restore: auto-save + auto-restore hook" >> "$SHELL_RC"
    echo "$HOOK_LINE" >> "$SHELL_RC"
    echo -e "${G}✓${N} Shell hook added to ${C}${SHELL_RC}${N}"
else
    echo -e "${G}✓${N} Shell hook already in ${SHELL_RC}"
fi

# --- 6. Set workspace trust for home directory ---
if command -v claude-session-restore &>/dev/null || [ -x "$INSTALL_DIR/claude-session-restore" ]; then
    "$INSTALL_DIR/claude-session-restore" trust "$HOME" 2>/dev/null && \
        echo -e "${G}✓${N} Claude workspace trust set for ~" || true
fi

# --- Done ---
echo ""
echo -e "${G}Installation complete!${N}"
echo ""
echo -e "  Reload your shell:  ${C}source ${SHELL_RC}${N}"
echo -e "  Check terminal:     ${C}claude-session-restore detect${N}"
echo -e "  Generate plan:      ${C}claude-session-restore new-plan${N}"
echo -e "  Restore sessions:   ${C}claude-session-restore launch${N}"
echo ""
echo -e "  ${Y}Next step: run 'claude-session-restore new-plan' to generate your restore plan${N}"
