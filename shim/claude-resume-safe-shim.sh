#!/usr/bin/env bash
# claude resume-safe shim
# ------------------------
# Problem: `claude --resume <id>` ist projekt-scoped (sucht nur in
# ~/.claude/projects/<key(cwd)>/<id>.jsonl). cmux baut beim App-Restart
# selbst `cd <ws-cwd> && claude --resume <id>`; wenn die Session unter
# einer anderen cwd erstellt wurde -> "No conversation found".
#
# Dieser Shim faengt --resume/-r <id> ab, findet die jsonl IRGENDWO unter
# ~/.claude/projects/*/, und bridged sie (symlink) in den project dir der
# AKTUELLEN cwd, bevor das echte Binary uebernimmt. Damit ist Resume
# cwd-unabhaengig und kann nicht mehr fehlschlagen.
#
# Fail-safe Ebenen:
#   1. id-jsonl gefunden -> bridge + echtes --resume
#   2. id nirgends gefunden -> Warnung + `claude -c` (juengste Session in cwd)
#   3. irgendein Fehler im Shim -> echtes Binary mit Originalargs (nie blockieren)
set -uo pipefail

PROJECTS="${HOME}/.claude/projects"

# echtes Binary aufloesen: bevorzugt claude-real, sonst hoechste Version
resolve_real() {
  if [[ -L "${HOME}/.local/bin/claude-real" ]]; then
    local t; t="$(readlink "${HOME}/.local/bin/claude-real" 2>/dev/null || true)"
    [[ -n "$t" && -x "$t" ]] && { printf '%s' "$t"; return; }
  fi
  local vdir="${HOME}/.local/share/claude/versions"
  if [[ -d "$vdir" ]]; then
    local newest
    newest="$(ls -1 "$vdir" 2>/dev/null | sort -V | tail -1)"
    [[ -n "$newest" && -x "$vdir/$newest" ]] && { printf '%s' "$vdir/$newest"; return; }
  fi
  printf '%s' ""
}

REAL="$(resolve_real)"
if [[ -z "$REAL" ]]; then
  echo "claude-shim: echtes claude-Binary nicht gefunden (~/.local/share/claude/versions)" >&2
  exit 127
fi

# cwd -> project-dir key (gleiche Regel wie Claude Code: jeder
# non-alphanumerische Lauf -> '-', fuehrendes '-')
proj_key() {
  local p="$1"
  p="$(printf '%s' "$p" | sed -E 's/[^A-Za-z0-9]+/-/g')"
  [[ "$p" == -* ]] || p="-$p"
  printf '%s' "$p"
}

# --resume / -r <id> in den Args finden (id = nachfolgendes Token)
SID=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--resume" || "$prev" == "-r" ]]; then
    SID="$a"; break
  fi
  prev="$a"
done

# Kein Resume -> unveraendert durchreichen (Hot Path, kein Overhead)
if [[ -z "$SID" ]]; then
  exec "$REAL" "$@"
fi

# id grob validieren. Bei Murks: durchreichen, echtes claude meldet sauber.
if [[ ! "$SID" =~ ^[A-Za-z0-9_-]{6,128}$ ]]; then
  exec "$REAL" "$@"
fi

# jsonl irgendwo unter den Projekten suchen
SRC="$(find "$PROJECTS" -maxdepth 2 -name "${SID}.jsonl" -print -quit 2>/dev/null || true)"

if [[ -z "$SRC" ]]; then
  echo "claude-shim: Session ${SID} nirgends gefunden -> Fallback juengste Session in $(pwd) (claude -c)" >&2
  newargs=(); skip=0
  for a in "$@"; do
    if [[ $skip -eq 1 ]]; then skip=0; continue; fi
    if [[ "$a" == "--resume" || "$a" == "-r" ]]; then skip=1; continue; fi
    newargs+=("$a")
  done
  exec "$REAL" -c "${newargs[@]}"
fi

# Ziel-Projektdir aus aktueller cwd
CURPROJ="${PROJECTS}/$(proj_key "$PWD")"
DEST="${CURPROJ}/${SID}.jsonl"

if [[ "$SRC" != "$DEST" ]]; then
  mkdir -p "$CURPROJ"
  if [[ ! -e "$DEST" ]]; then
    # #4 concurrent-guard: laeuft dieselbe Session schon woanders?
    # Dann KOPIE statt symlink -> kein paralleler Write auf eine jsonl.
    if pgrep -f -- "--resume[= ]${SID}" >/dev/null 2>&1; then
      cp "$SRC" "$DEST" 2>/dev/null \
        && echo "claude-shim: Session ${SID:0:8} bereits offen — KOPIE in $(basename "$CURPROJ") (kein shared write)" >&2
    else
      ln -s "$SRC" "$DEST" 2>/dev/null \
        && echo "claude-shim: Session ${SID:0:8} sichtbar gemacht in $(basename "$CURPROJ")" >&2
    fi
  fi
fi

exec "$REAL" "$@"
