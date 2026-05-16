#!/usr/bin/env bash
# claude-shim-guard
# -----------------
# Claude Code self-update setzt ~/.local/bin/claude wieder auf ein Symlink
# zum neuen Versions-Binary -> unser resume-safe Shim waere weg.
# Dieser Guard (launchd, alle 120s + bei Login) heilt das:
#   - claude-real auf neueste Version zeigen lassen
#   - wenn ~/.local/bin/claude NICHT mehr unser Shim ist -> Shim reinstallieren
set -uo pipefail

BIN="${HOME}/.local/bin/claude"
REALLINK="${HOME}/.local/bin/claude-real"
CANON="${HOME}/.claude/bin/claude-resume-safe-shim.sh"
VDIR="${HOME}/.local/share/claude/versions"
MARK="claude resume-safe shim"

[[ -f "$CANON" ]] || exit 0

# 1. claude-real -> neueste installierte Version
if [[ -d "$VDIR" ]]; then
  newest="$(ls -1 "$VDIR" 2>/dev/null | sort -V | tail -1)"
  if [[ -n "$newest" && -x "$VDIR/$newest" ]]; then
    cur="$(readlink "$REALLINK" 2>/dev/null || true)"
    [[ "$cur" == "$VDIR/$newest" ]] || ln -sfn "$VDIR/$newest" "$REALLINK"
  fi
fi

# 2. Ist ~/.local/bin/claude noch unser Shim?
needs_reinstall=0
if [[ -L "$BIN" ]]; then
  needs_reinstall=1                       # Updater hat Symlink wiederhergestellt
elif [[ ! -f "$BIN" ]]; then
  needs_reinstall=1
elif ! grep -q "$MARK" "$BIN" 2>/dev/null; then
  needs_reinstall=1
fi

if [[ "$needs_reinstall" -eq 1 ]]; then
  # falls echtes Binary noch als Symlink dort: vorher claude-real sichern
  if [[ -L "$BIN" ]]; then
    tgt="$(readlink "$BIN" 2>/dev/null || true)"
    [[ -n "$tgt" && -x "$tgt" ]] && ln -sfn "$tgt" "$REALLINK"
  fi
  rm -f "$BIN"
  cp "$CANON" "$BIN"
  chmod +x "$BIN"
  echo "$(date '+%F %T') reinstalled resume-safe shim" >> "${HOME}/.claude/logs/claude-shim-guard.log"
fi

# 3. Rivalen abfangen: jedes andere 'claude' in einem $HOME-Dir im PATH,
#    das NICHT unser Shim ist (npm -g / bun / pipx / venvs ...), durch den
#    Shim ersetzen. Nur unter $HOME -> System-Pfade (/usr, /opt) bleiben tabu.
IFS=':' read -r -a _pdirs <<< "${PATH:-}"
for d in "${_pdirs[@]}"; do
  [[ -n "$d" ]] || continue
  case "$d" in "$HOME"/*) : ;; *) continue ;; esac   # nur $HOME-rooted
  c="$d/claude"
  [[ "$c" == "$BIN" ]] && continue                    # unser Hauptshim, skip
  [[ -e "$c" ]] || continue
  if grep -q "$MARK" "$c" 2>/dev/null; then continue; fi
  # echtes Binary? -> als claude-real sichern falls noch keins gesetzt
  if [[ -L "$c" ]]; then
    rt="$(readlink "$c" 2>/dev/null || true)"
    if [[ -n "$rt" && -x "$rt" && ! -e "$REALLINK" ]]; then ln -sfn "$rt" "$REALLINK"; fi
  fi
  cp -f "$c" "$c.pre-shim.bak" 2>/dev/null || true
  rm -f "$c"
  cp "$CANON" "$c" && chmod +x "$c" \
    && echo "$(date '+%F %T') shimmed rival $c" >> "${HOME}/.claude/logs/claude-shim-guard.log"
done
