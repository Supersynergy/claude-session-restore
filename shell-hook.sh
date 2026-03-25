#!/bin/bash
# =============================================================================
# ghostty-session v3.1 — Shell Hook (source in ~/.zshrc or ~/.bashrc)
#
# Failsafe auto-features:
#   ✓ Every new window: auto-assigns unique name + sets terminal title
#   ✓ Every prompt:     registers CWD + Claude Code detection
#   ✓ Every 5 min:      auto-saves entire session
#   ✓ Terminal close:    saves before exit
#   ✓ Ghostty start:    restores last session (with cascade prevention)
# =============================================================================

# Run in any supported terminal (ghostty, iterm2, kitty, wezterm, terminal.app, alacritty)
# Skip only if clearly not a terminal (e.g., running from cron or script)
[ ! -t 0 ] && return 0 2>/dev/null

# Find binary
_GS_BIN=""
for _c in "$HOME/.local/bin/ghostty-session" "/usr/local/bin/ghostty-session"; do
    [ -x "$_c" ] && _GS_BIN="$_c" && break
done
[ -z "$_GS_BIN" ] && return 0 2>/dev/null

_GS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-sessions"
_GS_RESTORE_FLAG="$_GS_DIR/.restore_done"
_GS_RESTORE_LOCK="$_GS_DIR/.restore.lock"
_GS_STATE_FILE="$_GS_DIR/.state.json"
_GS_NAMES_DIR="$_GS_DIR/names"
mkdir -p "$_GS_NAMES_DIR" 2>/dev/null

# =============================================================================
# Auto-Name: give every Ghostty window a unique, trackable name
# =============================================================================

_gs_assign_name() {
    # If already named (e.g. by restore script), keep it
    [ -n "$GHOSTTY_SESSION_NAME" ] && return 0

    # Check if restore script pre-assigned a name for this PID
    if [ -f "$_GS_NAMES_DIR/$$.name" ]; then
        GHOSTTY_SESSION_NAME=$(cat "$_GS_NAMES_DIR/$$.name" 2>/dev/null)
        export GHOSTTY_SESSION_NAME
        printf '\033]0;%s\033\\' "$GHOSTTY_SESSION_NAME"
        return 0
    fi

    # Generate name from directory basename + short PID
    local dir_name short_pid
    dir_name=$(basename "$PWD")
    short_pid=$(printf '%04d' $(($$  % 10000)))

    # Common names for known directories
    case "$dir_name" in
        master)           GHOSTTY_SESSION_NAME="shell-${short_pid}" ;;
        openclaw-crm)     GHOSTTY_SESSION_NAME="openclaw-${short_pid}" ;;
        sscrmapp)         GHOSTTY_SESSION_NAME="crm-${short_pid}" ;;
        supersynergyapp)  GHOSTTY_SESSION_NAME="synergy-${short_pid}" ;;
        zeroClawUltimate) GHOSTTY_SESSION_NAME="zeroclaw-${short_pid}" ;;
        superscraper|megascraper) GHOSTTY_SESSION_NAME="scraper-${short_pid}" ;;
        *)                GHOSTTY_SESSION_NAME="${dir_name}-${short_pid}" ;;
    esac

    export GHOSTTY_SESSION_NAME
    # Persist name for this PID
    echo "$GHOSTTY_SESSION_NAME" > "$_GS_NAMES_DIR/$$.name" 2>/dev/null
    # Set terminal title
    printf '\033]0;%s\033\\' "$GHOSTTY_SESSION_NAME"
}

# --- Auto-save on exit + clean up name file ---
trap '
    "$_GS_BIN" autosave 2>/dev/null
    rm -f "$_GS_NAMES_DIR/$$.name" 2>/dev/null
' HUP EXIT

# --- Prompt hook: register pane + periodic save + dynamic title ---
_GS_LAST_SAVE=${_GS_LAST_SAVE:-0}

_gs_prompt() {
    # Register this pane (background, non-blocking)
    "$_GS_BIN" register-pane $$ "$PWD" 2>/dev/null &

    # Auto-save every 300s (5 min)
    local _now; _now=$(date +%s)
    if (( _now - _GS_LAST_SAVE >= 300 )); then
        _GS_LAST_SAVE=$_now
        "$_GS_BIN" autosave 2>/dev/null &
    fi

    # Update title if claude is running (it sets its own via --name)
    # Otherwise keep our assigned name
    if [ -n "$GHOSTTY_SESSION_NAME" ]; then
        # Check if claude is running in this shell
        local _claude_running
        _claude_running=$(pgrep -P $$ -f "claude" 2>/dev/null | head -1 || true)
        if [ -z "$_claude_running" ]; then
            # No claude running — show our name + current dir
            local _short_dir
            _short_dir=$(basename "$PWD")
            printf '\033]0;%s · %s\033\\' "$GHOSTTY_SESSION_NAME" "$_short_dir"
        fi
        # If claude is running, let claude --name handle the title
    fi

    # OSC 7: report CWD to Ghostty
    printf '\e]7;file://%s%s\e\\' "${HOSTNAME:-localhost}" "$PWD"
}

# Hook into shell
if [ -n "$ZSH_VERSION" ]; then
    autoload -U add-zsh-hook 2>/dev/null
    add-zsh-hook precmd _gs_prompt
elif [ -n "$BASH_VERSION" ]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_gs_prompt"
fi

# --- Cascade-proof auto-restore on Ghostty launch ---
_gs_should_restore() {
    # Layer 0: Permanent daily skip flag
    if [ -f "$_GS_DIR/.skip_restore_$(date +%Y%m%d)" ]; then
        return 1
    fi

    # Layer 1: Get system boot time — if flag is OLDER than boot, it's stale (safe to restore)
    local boot_time now flag_mtime
    boot_time=$(sysctl -n kern.boottime 2>/dev/null | python3 -c "
import sys, re
m = re.search(r'sec = (\d+)', sys.stdin.read())
print(m.group(1) if m else '0')
" 2>/dev/null || echo "0")
    now=$(date +%s)

    # Layer 2: Flag file check — only block if flag is NEWER than boot time (= same session)
    if [ -f "$_GS_RESTORE_FLAG" ]; then
        flag_mtime=$(stat -f%m "$_GS_RESTORE_FLAG" 2>/dev/null || echo 0)
        # Flag is from BEFORE boot → stale, allow restore
        # Flag is from AFTER boot AND < 120s old → block (cascade prevention)
        if [ "$flag_mtime" -gt "$boot_time" ]; then
            local flag_age=$(( now - flag_mtime ))
            [ "$flag_age" -lt 120 ] && return 1
        fi
    fi

    # Layer 3: Lock file — active restore in progress
    if [ -f "$_GS_RESTORE_LOCK" ]; then
        local lock_age lock_pid
        lock_pid=$(cat "$_GS_RESTORE_LOCK" 2>/dev/null || echo "0")
        lock_age=$(( now - $(stat -f%m "$_GS_RESTORE_LOCK" 2>/dev/null || echo 0) ))
        if [ "$lock_age" -lt 60 ] && kill -0 "$lock_pid" 2>/dev/null; then
            return 1
        fi
    fi

    # Layer 4: State file — check if last_restore was recent (same session)
    if [ -f "$_GS_STATE_FILE" ]; then
        local recent
        recent=$(python3 -c "
import json, time, datetime
try:
    s = json.load(open('$_GS_STATE_FILE'))
    lr = s.get('last_restore', '')
    if lr:
        t = datetime.datetime.fromisoformat(lr.replace('Z', '+00:00'))
        age = time.time() - t.timestamp()
        # Only block if restored recently AND after boot
        boot = $boot_time
        if t.timestamp() > boot and age < 120:
            print('1'); exit()
    print('0')
except:
    print('0')
" 2>/dev/null)
        [ "$recent" = "1" ] && return 1
    fi

    return 0
}

if [ -z "$_GS_HOOK_LOADED" ]; then
    export _GS_HOOK_LOADED=1
    _GS_LAST_SAVE=$(date +%s)

    # Assign a name to this window
    _gs_assign_name

    _GS_PLAN="$_GS_DIR/restore-all.json"
    _GS_AUTOSAVE="$_GS_DIR/.autosave.json"

    # Determine restore source: prefer fixed plan over autosave
    _gs_restore_src=""
    [ -f "$_GS_PLAN" ] && _gs_restore_src="$_GS_PLAN"
    [ -z "$_gs_restore_src" ] && [ -f "$_GS_AUTOSAVE" ] && _gs_restore_src="$_GS_AUTOSAVE"

    if [ -n "$_gs_restore_src" ] && _gs_should_restore; then
        # Check if only 1 window open (fresh Ghostty start, not a restored window)
        _gs_win_count=$(osascript -e 'tell application "Ghostty" to count windows' 2>/dev/null || echo "99")
        if [ "$_gs_win_count" -le 1 ]; then
            touch "$_GS_RESTORE_FLAG"
            echo -e ""
            # Read session count dynamically from plan file
            _gs_session_count=$(python3 -c "
import json, os
f = '$_gs_restore_src'
try:
    d = json.load(open(f))
    wins = d.get('windows', d.get('restore_plan', d.get('panes', [])))
    print(f'{len(wins)} Sessions')
except:
    print('Sessions')
" 2>/dev/null || echo "Sessions")
            echo -e "\033[0;36m┌─ claude-session-restore v1.0.0 ─────────────────────────┐\033[0m"
            echo -e "\033[0;36m│  Restore sessions? (\033[1;33mrestore-all.json\033[0;36m)                    │\033[0m"
            echo -e "\033[0;36m│  $_gs_session_count                                              │\033[0m"
            echo -e "\033[0;36m│  [Y]es / [n]o / [s]kip permanently                       │\033[0m"
            echo -e "\033[0;36m└──────────────────────────────────────────────────────────┘\033[0m"
            read -r _gs_ans </dev/tty 2>/dev/null

            case "${_gs_ans:-y}" in
                [nN])
                    echo -e "\033[2mSkipped. Run 'ccrestore' to restore manually.\033[0m"
                    ;;
                [sS])
                    # Create a permanent skip flag for today
                    touch "$_GS_DIR/.skip_restore_$(date +%Y%m%d)"
                    echo -e "\033[2mSkipped for today.\033[0m"
                    ;;
                *)
                    echo -e "\033[0;32m→ Restoring sessions...\033[0m"
                    if [ "$_gs_restore_src" = "$_GS_PLAN" ]; then
                        "$_GS_BIN" launch "$_gs_restore_src"
                    else
                        "$_GS_BIN" auto-restore
                    fi
                    ;;
            esac
        fi
    fi
fi

# Aliases
alias gs='ghostty-session'
alias gss='ghostty-session save'
alias gsr='ghostty-session restore'
alias gsl='ghostty-session list'
alias gstat='ghostty-session status'
