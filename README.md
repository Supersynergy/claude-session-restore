# claude-session-restore

> Restore Claude Code sessions across terminal restarts

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/supersynergy/claude-session-restore/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2012--15-lightgrey.svg)](https://github.com/supersynergy/claude-session-restore)
[![Shell](https://img.shields.io/badge/shell-bash%20%7C%20zsh-orange.svg)](https://github.com/supersynergy/claude-session-restore)

Pick up exactly where you left off. `claude-session-restore` automatically saves your Claude Code sessions and restores them — across reboots, terminal restarts, and crashes — in any terminal.

```
┌─ claude-session-restore v1.0.0 ──────────────────────────┐
│  Restore sessions? (restore-all.json)                    │
│  12 Sessions                                             │
│  [Y]es / [n]o / [s]kip permanently                      │
└──────────────────────────────────────────────────────────┘
```

---

## Supported Terminals

| Terminal | Window Restore | Auto-Title | Auto-Save |
|----------|:--------------:|:----------:|:---------:|
| **Ghostty** | osascript (Cmd+N) | OSC 0 | |
| **iTerm2** | AppleScript native | OSC 0 | |
| **Terminal.app** | AppleScript `do script` | OSC 0 | |
| **Kitty** | `kitty @ launch` | OSC 0 | |
| **WezTerm** | `wezterm cli spawn` | OSC 0 | |
| **Alacritty** | process spawn | OSC 0 | |
| **tmux** | `tmux new-window` | window name | |

---

## Quick Start

**Step 1 — Install**

```bash
git clone https://github.com/supersynergy/claude-session-restore.git
cd claude-session-restore
bash install.sh
source ~/.zshrc
```

**Step 2 — Generate your restore plan**

Scans your `~/.claude/projects/` and creates a plan from your 12 most recent sessions:

```bash
claude-session-restore new-plan
```

**Step 3 — Restore**

Next time you open your terminal, you'll be prompted to restore. Or run manually:

```bash
claude-session-restore launch
```

---

## Commands

| Command | Description |
|---------|-------------|
| `claude-session-restore launch [plan.json]` | Restore sessions from plan (default: `restore-all.json`) |
| `claude-session-restore new-plan [N] [out]` | Auto-generate plan from N most recent Claude sessions |
| `claude-session-restore save [name]` | Save current session state |
| `claude-session-restore status` | Show tracked windows + live panes |
| `claude-session-restore list` | List all saved sessions |
| `claude-session-restore delete <name>` | Delete a saved session |
| `claude-session-restore detect` | Show detected terminal + capabilities |
| `claude-session-restore trust [dir]` | Pre-accept Claude workspace trust dialog |
| `claude-session-restore help` | Show help |

### Aliases (set up automatically by shell hook)

```bash
alias ccrestore='claude-session-restore launch'
alias ccsave='claude-session-restore save'
alias ccstatus='claude-session-restore status'
alias ccplan='claude-session-restore new-plan'
```

---

## How It Works

### Session Plan (restore-all.json)

Sessions are defined in a JSON plan file stored at `~/.local/share/ghostty-sessions/restore-all.json`. The `new-plan` command generates this automatically from your Claude project history.

```json
{
  "name": "restore-all",
  "description": "My development sessions",
  "windows": [
    {
      "id": "s1-myproject",
      "type": "claude",
      "cwd": "/Users/yourname/projects/my-app",
      "cmd": "claude --resume abc123def456",
      "claude_session": "abc123def456",
      "label": "my-app — feature/auth"
    },
    {
      "id": "s2-api",
      "type": "claude",
      "cwd": "/Users/yourname/projects/api",
      "cmd": "claude --resume 789xyz000111",
      "claude_session": "789xyz000111",
      "label": "api — refactor"
    },
    {
      "id": "s3-shell",
      "type": "shell",
      "cwd": "/Users/yourname",
      "cmd": "",
      "label": "General shell"
    }
  ]
}
```

Each entry can be:
- `type: claude` — opens a window and resumes a specific Claude Code session
- `type: shell` — opens a plain terminal window at `cwd`

### Terminal Detection

The script detects your terminal via environment variables (fastest path) and falls back through `$TERM_PROGRAM` and `$TERM`:

```
$TMUX              → tmux
$GHOSTTY_RESOURCES_DIR → ghostty
$ITERM_SESSION_ID  → iterm2
$KITTY_PID         → kitty
$WEZTERM_PANE      → wezterm
$TERM_PROGRAM      → ghostty / iTerm.app / Apple_Terminal / Alacritty / WezTerm
$TERM              → xterm-ghostty / xterm-kitty / alacritty / wezterm
```

```bash
# Check what was detected
claude-session-restore detect
```

### Cascade Prevention

The shell hook uses a 4-layer cascade prevention system to ensure the restore prompt only appears once per boot — not on every new window:

1. **Daily skip flag** — `touch ~/.local/share/ghostty-sessions/.skip_restore_YYYYMMDD` to skip for a day
2. **Boot-time comparison** — stale flags (pre-boot) are ignored
3. **Lock file** — prevents concurrent restores
4. **State file** — tracks last restore timestamp

---

## Shell Hook

The shell hook (`shell-hook.sh`) is sourced from your `~/.zshrc` or `~/.bashrc` and provides:

| Feature | How |
|---------|-----|
| **Auto-name** | Every new window gets a unique name (`project-1234`) |
| **Terminal title** | OSC 0 escape sequence updates the tab/window title |
| **Pane registration** | Every prompt reports current CWD + active Claude session |
| **Auto-save** | Every 5 minutes, silently saves state to `.autosave.json` |
| **Save on exit** | `trap` on HUP/EXIT saves before window closes |
| **Auto-restore prompt** | On first window of fresh terminal start, prompts to restore |

The hook is non-blocking — all registration calls run in the background and never slow down your prompt.

**Source manually:**

```bash
source ~/.local/share/ghostty-sessions/shell-hook.sh
```

**Or add to your shell config:**

```bash
# ~/.zshrc or ~/.bashrc
[ -f "$HOME/.local/share/ghostty-sessions/shell-hook.sh" ] && \
  source "$HOME/.local/share/ghostty-sessions/shell-hook.sh"
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_SESSION_MAX_WINDOWS` | `16` | Maximum windows to restore in one run |
| `XDG_DATA_HOME` | `~/.local/share` | Base path for session data |

### File Locations

| Path | Description |
|------|-------------|
| `~/.local/share/ghostty-sessions/restore-all.json` | Main restore plan |
| `~/.local/share/ghostty-sessions/.autosave.json` | Auto-saved state |
| `~/.local/share/ghostty-sessions/.state.json` | Runtime state (tracked windows) |
| `~/.local/share/ghostty-sessions/panes/` | Live pane registry |
| `~/.local/bin/claude-session-restore` | Installed binary |

### Custom Plan Location

```bash
# Use a specific plan file
claude-session-restore launch ~/my-plans/morning.json

# Generate to a custom location
claude-session-restore new-plan 8 ~/my-plans/work.json
```

### Skip Auto-Restore

```bash
# Skip today only
touch ~/.local/share/ghostty-sessions/.skip_restore_$(date +%Y%m%d)

# Skip permanently: remove the hook from ~/.zshrc
```

---

## Requirements

- macOS 12–15 (Monterey through Sequoia)
- `python3` (system Python is fine)
- [Claude Code CLI](https://claude.ai/download) (`claude` in PATH)
- One of the supported terminals listed above

---

## Troubleshooting

**Restore prompt not appearing**

```bash
# Check detection
claude-session-restore detect

# Check if a skip flag exists
ls ~/.local/share/ghostty-sessions/.skip_restore_*

# Remove stale skip flag
rm ~/.local/share/ghostty-sessions/.skip_restore_*
```

**Wrong terminal detected**

```bash
claude-session-restore detect
# Shows: Terminal, $TERM, $TERM_PROGRAM, capabilities
```

**Sessions not saving**

```bash
# Check hook is loaded
type _gs_prompt  # should show function

# Manual save
claude-session-restore save work
claude-session-restore list
```

**Claude trust dialog on every restore**

```bash
# Pre-accept trust for your home directory
claude-session-restore trust ~

# Or for a specific project
claude-session-restore trust /path/to/project
```

---

## License

MIT — Copyright 2026 SuperSynergy

---

## Credits

Built for [Claude Code](https://claude.ai/download) by [SuperSynergy](https://github.com/supersynergy).
