#!/usr/bin/env bash
# =============================================================================
# install.sh — claude-session-restore installer
# =============================================================================

set -euo pipefail

VERSION="1.1.0"
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

# --- 1.5. Install resume-safe Shim + Guard (v1.1 — der eigentliche Fix) ---
# claude --resume <id> ist projekt-scoped. Wird ein Pane mit anderer cwd
# restored als beim Session-Start -> "No conversation found". Der Shim faengt
# --resume ab und macht es cwd-unabhaengig. Funktioniert fuer JEDES Terminal.
CB="$HOME/.claude/bin"; mkdir -p "$CB" "$HOME/.claude/logs"
cp "$SCRIPT_DIR/shim/claude-resume-safe-shim.sh" "$CB/claude-resume-safe-shim.sh"
cp "$SCRIPT_DIR/shim/claude-shim-guard.sh"       "$CB/claude-shim-guard.sh"
chmod +x "$CB/claude-resume-safe-shim.sh" "$CB/claude-shim-guard.sh"

# claude-real auf echtes Binary sichern (vor Shim-Install)
if [ -L "$INSTALL_DIR/claude" ]; then
    tgt="$(readlink "$INSTALL_DIR/claude")"
    [ -n "$tgt" ] && [ -x "$tgt" ] && ln -sfn "$tgt" "$INSTALL_DIR/claude-real"
fi
if [ ! -e "$INSTALL_DIR/claude-real" ]; then
    nv="$(ls -1 "$HOME/.local/share/claude/versions" 2>/dev/null | sort -V | tail -1)"
    [ -n "$nv" ] && ln -sfn "$HOME/.local/share/claude/versions/$nv" "$INSTALL_DIR/claude-real"
fi

if ! grep -q "claude resume-safe shim" "$INSTALL_DIR/claude" 2>/dev/null; then
    rm -f "$INSTALL_DIR/claude"
    cp "$CB/claude-resume-safe-shim.sh" "$INSTALL_DIR/claude"
    chmod +x "$INSTALL_DIR/claude"
    echo -e "${G}✓${N} resume-safe Shim installed: ${C}${INSTALL_DIR}/claude${N}"
else
    echo -e "${G}✓${N} resume-safe Shim already active"
fi

# Guard-Launchd (macOS): heilt Shim nach Claude-Self-Update + faengt Rivalen
if [ "$(uname)" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.supersynergy.claude-shim-guard.plist"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.supersynergy.claude-shim-guard</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$CB/claude-shim-guard.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>120</integer>
  <key>StandardErrorPath</key><string>$HOME/.claude/logs/claude-shim-guard.err</string>
  <key>StandardOutPath</key><string>$HOME/.claude/logs/claude-shim-guard.out</string>
</dict></plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" 2>/dev/null && \
        echo -e "${G}✓${N} Shim-Guard launchd loaded (self-heal vs claude-update)" || true
elif command -v systemctl &>/dev/null; then
    # Linux: systemd --user timer (Aequivalent zum macOS launchd-Guard)
    UD="$HOME/.config/systemd/user"; mkdir -p "$UD"
    cat > "$UD/claude-shim-guard.service" <<EOF
[Unit]
Description=claude-session-restore shim self-heal
[Service]
Type=oneshot
ExecStart=/bin/bash $CB/claude-shim-guard.sh
EOF
    cat > "$UD/claude-shim-guard.timer" <<EOF
[Unit]
Description=Run claude shim-guard every 2 min
[Timer]
OnBootSec=30
OnUnitActiveSec=120
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now claude-shim-guard.timer 2>/dev/null && \
        echo -e "${G}✓${N} Shim-Guard systemd-timer aktiviert (self-heal)" || \
        echo -e "${Y}!${N} systemd-timer angelegt, enable manuell: systemctl --user enable --now claude-shim-guard.timer"
else
    echo -e "${Y}!${N} Kein launchd/systemd — Shim aktiv, Self-Heal via cron:"
    echo -e "  (crontab -l 2>/dev/null; echo '*/2 * * * * bash $CB/claude-shim-guard.sh') | crontab -"
fi

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
