# claude-session-restore

> Restore Claude Code sessions across terminal restarts

[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/supersynergy/claude-session-restore/releases)
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
| **cmux** | `cmux new-workspace` (via `cmux-rescue`) | workspace title | ✓ |

---

## cmux-rescue — zero-dependency failsafe (cmux.app)

[cmux](https://github.com/manaflow-ai/cmux) wipes every workspace on app
update / accidental window-close. The other restore paths (snapshot daemon,
session-map, in-app server) each have a dependency that can be the very thing
that broke. **`cmux-rescue` depends on nothing but `~/.claude/projects/`** —
the transcript dir Claude itself always writes.

```bash
cmux-rescue                 # 10 newest + 5 leverage-scored picks (default)
cmux-rescue --top 15        # 15 newest only
cmux-rescue --all           # every closed session (cap 40)
cmux-rescue --dry-run       # print the plan, spawn nothing
cmux-rescue --restart       # quit+relaunch cmux first (launchd-owned, so it
                            #   SURVIVES the quit), then restore
```

How it stays correct:

- **Rank** sessions by `*.jsonl` mtime; drop subagents and empty/aborted ones.
- **Leverage score** — `prod`/`fix`/`revenue`/`strategy` keywords boost picks.
- **Dual dedup** — live `--session-id` (ps via cmux pids) **plus** normalized
  workspace title. Run it twice → zero duplicates.
- **`--restart` uses `launchctl submit`** so launchd is the parent process;
  the classic failure (a `nohup` child dying together with cmux) is gone.
- **Self-verify** — re-counts workspaces after, logs to `/tmp/cmux-rescue.log`.

Portable: no hardcoded paths. Override with `CLAUDE_PROJECTS_DIR` /
`CMUX_BIN`. Installed automatically by `install.sh` (works even before
cmux.app is present).

Failsafe automation — run after every cmux restart (launchd `RunAtLoad`,
or a shell-rc one-liner):

```bash
command -v cmux >/dev/null && cmux-rescue --top 10 --picks 5 >/dev/null 2>&1 &
```

---

## MCP server (Claude Code / Cursor / Codex / Desktop)

Zero-dependency stdio MCP — **stdlib only**, no `mcp` pip package, no
framework. Same ethos as the CLI. Exposes 3 tools:

| Tool | Does |
|------|------|
| `list_sessions` | ranked restorable sessions (cwd · first msg · leverage), spawns nothing |
| `cmux_rescue` | restore into cmux workspaces — `top` / `picks` / `all` / `dry_run` / `restart` |
| `claude_session_restore` | drive the generic restorer — `detect` / `new-plan` / `launch` |

Register with Claude Code (auto-done by `install.sh` if `claude` is on PATH):

```bash
claude mcp add cmux-rescue -- python3 \
  ~/.local/share/claude-session-restore/cmux-rescue-mcp.py
```

Cursor / Claude Desktop — add to the MCP config:

```json
{
  "mcpServers": {
    "cmux-rescue": {
      "command": "python3",
      "args": ["~/.local/share/claude-session-restore/cmux-rescue-mcp.py"]
    }
  }
}
```

Then in any session: *"list my restorable sessions"* or *"rescue the top 10
plus 5 leverage picks"* — the agent calls the tools directly.

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
