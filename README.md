# worklog-tool

**English** · [Tiếng Việt](README.vi.md)

An automatic work journal for AI coding agents: **Claude Code, Gemini CLI, Codex CLI and GitHub Copilot CLI**. When a session ends, an AI summarizes what was done, what was decided and what is still open, then commits it to a **private** git repo that you own. It works across all your machines, and the entries still make sense years later.

The same repo also becomes long-term memory and a data source: every session's full transcript and numbers (active time, tokens, cost) are archived, open items are tracked with ids, and new sessions start with the project's recent history.

## How it works

- **This repo (public):** code only.
- **Your data repo (private):** the journal, one file per month per machine:

```
2026/11-laptop.md                              ← summaries, quick to read
2026/11-server-a.md
raw/2026/11/laptop-claude-<session>.md         ← cleaned-up conversation, readable as is (secrets redacted)
meta/2026/11-laptop.jsonl                      ← numbers per session: active time, tokens, cost, tools
archive/claude/2026/11/laptop-<sid>.jsonl.zst  ← FULL original transcript, compressed (secrets redacted, images removed)
todo/laptop.jsonl                              ← open items (opened / done events)
summaries/2026-11.md                           ← monthly / yearly reviews (Vietnamese journals: tong-ket/)
```

`archive/` is the long-term source of truth: summaries, numbers and any future statistics can be recomputed from it. With base64 images removed and zstd compression, transcripts shrink to about 5% (one real example: 365 MB → 18 MB for 86 sessions).

A journal entry:

```
## 2026-11-18 15:20–16:05 · laptop · codex · my-project
- What was done (specific: files, commands, servers)
- Decision: ... (and why)
- TODO [#a1b2c3]: one open item per line
- Raw transcript: `raw/2026/11/laptop-codex-<session>.jsonl`
```

| CLI | Hooks | Notes |
|---|---|---|
| Claude Code | `SessionStart`, `SessionEnd` in `~/.claude/settings.json` | Also installs the `worklog` skill and loads project context at session start |
| Gemini CLI | `SessionStart`, `SessionEnd` in `~/.gemini/settings.json` | Adds a note to `~/.gemini/GEMINI.md` |
| Codex CLI | `SessionStart`, `SessionEnd` in `~/.codex/hooks.json` | **You must trust the hooks once via `/hooks`**; adds a note to `~/.codex/AGENTS.md` |
| Copilot CLI | `sessionStart`, `agentStop`, `sessionEnd` in `~/.copilot/hooks/worklog.json` | `sessionEnd` has no transcript, so the path is taken from `agentStop` |

Pipeline:

1. `hooks/hook.sh` receives each CLI's JSON payload, normalizes it and detaches into the background (the CLI exits immediately; Codex gives hooks at most 3 seconds).
2. `hooks/core.sh` gathers the material:
   - Claude Code: extracts the conversation (user messages, AI replies, tool calls; drops thinking and images, truncates tool output). A 40 MB session becomes ~130 KB.
   - Other CLIs: raw data with long lines cut. Long sessions keep both the beginning and the end.
   - No transcript: uses `git log` for the session's time range. Resumed sessions only summarize the new part.
   - Automated sessions (`claude -p`, Agent SDK, `codex exec`) are not summarized into the journal; they are still archived and counted, as `mode: auto`.
3. Summarizes with whichever CLI is installed (`claude` → `gemini` → `codex`), in a temp directory, with no tools, no saved session and a 5-minute timeout. Data goes through stdin, so it never shows up in `ps`.
4. Saves the cleaned-up conversation to `raw/` as plain text (common secrets redacted; git compresses it in storage). With `age` configured it is compressed and encrypted to `.gz.age` instead. If summarizing fails, the entry is still written with the raw path, so it can be summarized later.
5. Long-term archive (`hooks/store.sh`): the original transcript goes to `archive/` (redacted, images removed, zstd or gzip, `age`-encrypted if configured), and one line of numbers goes to `meta/` (`hooks/meta.jq`: active time, tokens per model — Claude usage is counted once per `message.id` to avoid double counting — cost as computed by Claude Code, tool calls, subagents, interactive vs. automated).
6. Appends, commits and pushes under a lock, so sessions that end at the same time do not collide. A failed rebase is aborted automatically; a failed push is retried and otherwise left for next time.
7. At session start: pulls the data repo, (by default) updates the `worklog-tool` code, and runs `hooks/sweep.sh` (at most once an hour) to archive any Claude Code / Codex transcripts that were missed — for example when a window was closed abruptly and the end hook never ran. `install.sh` runs `sweep.sh --all` to archive the old transcripts already on the machine, and sets `cleanupPeriodDays: 365` for Claude Code (which otherwise deletes transcripts after 30 days) unless you have set it yourself.

## Long-term memory

- **Open items with ids** (`todo/<machine>.jsonl`): each open item in a summary becomes `#a1b2c3`. The next time the same project is summarized, the AI receives the list of open items and marks the ones that session finished. Manage them by hand with `hooks/todo.sh list [project|--all]`, `todo.sh done <id>`, `todo.sh add <project> "<text>"`.
- **Context at session start** (Claude Code for now): the `SessionStart` hook adds the open items and the 3 most recent journal entries of the current project (`hooks/context.sh`, local files only, ~0.1 s). The context is marked as reference data, not instructions, and the agent is told to verify it before relying on it. Disable with `WORKLOG_CONTEXT=0`; tune with `WORKLOG_CONTEXT_ENTRIES`, `WORKLOG_CONTEXT_TODOS`.

## Install

Requirements: `git`, `jq`, at least one of the CLIs above, and push access (e.g. an SSH key) to a git host. `zstd` is recommended (gzip is used otherwise); `age` is optional.

```bash
# 1. Create an EMPTY, PRIVATE repo on GitHub (or any git host), e.g. "worklog"
# 2. On each machine:
git clone https://github.com/<owner>/worklog-tool.git ~/worklog-tool
~/worklog-tool/install.sh git@github.com:<you>/worklog.git
```

`install.sh` detects which CLIs are installed and only sets up those. It asks for the journal language and for an email for journal commits. Installed another CLI later? Run `~/worklog-tool/install.sh` again. Re-running is always safe: no duplicate hooks, other settings are kept (a backup is saved as `*.bak.worklog`).

## Configuration

Set these in each machine's `~/.config/worklog/config` (`KEY=value`, created by `install.sh`), or as environment variables of the same name (which take precedence). The config file is recommended: CLIs started from an IDE or a desktop menu often do not read `~/.bashrc`.

| Variable | Default | Meaning |
|---|---|---|
| `WORKLOG_DIR` | `~/worklog` | Where the data repo is cloned |
| `WORKLOG_LANG` | from the locale (`vi_*` → `vi`, otherwise `en`); asked during install | Language the journal is written in: `en` or `vi` |
| `WORKLOG_HOST` | `hostname -s` | Machine name used in file names and headers — set it when several machines share a hostname (`ubuntu`, `localhost`…) |
| `WORKLOG_CONTEXT` | `1` | `0` = do not load worklog context at session start |
| `WORKLOG_CONTEXT_ENTRIES` / `WORKLOG_CONTEXT_TODOS` | `3` / `15` | How many journal entries / open items to load |
| `WORKLOG_AUTO_SUMMARY` | `0` | `1` = also summarize automated sessions (`claude -p`, Agent SDK, `codex exec`) into the journal |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `COPILOT_HOME` | `~/.claude`, `~/.codex`, `~/.copilot` | Each CLI's config directory, if you moved it |
| `WORKLOG_SUMMARIZER` | auto | `claude`, `gemini` or `codex` — pin the CLI used for summarizing |
| `WORKLOG_CLAUDE_MODEL` | `haiku` | Model used when summarizing with Claude |
| `WORKLOG_RAW` | `1` | `0` = do not store transcripts (`raw/`, `archive/`), only summaries and `meta/` numbers |
| `WORKLOG_RAW_MAX` | `20000000` | Skip raw/archive files larger than this many bytes (after compression) |
| `WORKLOG_AGE_RECIPIENT` | — | (Optional) an `age1...` public key to encrypt raw and archive files — claude.ai can then no longer read them |
| `WORKLOG_AGE_RECIPIENTS_FILE` | — | Or a file with several `age` public keys |
| `WORKLOG_GIT_EMAIL` | asked during install | Commit email for the data repo (set locally, your global git config is untouched) |
| `WORKLOG_AUTO_UPDATE` | `1` | `0` = do not `git pull` the `worklog-tool` code at session start |

**Project name** defaults to the name of the git repo's top-level directory (worktrees count as their main repo), or the directory name outside git. If two repos share a directory name, or you want another name, run `git config worklog.project <name>` in that repo.

## Security

- The summarizing prompt forbids writing passwords, tokens and keys — but it is still an AI summary, so keep the data repo **private**.
- Transcripts are sent to the summarizing CLI, i.e. to that CLI's model provider.
- `raw/` and `archive/` contain nearly the whole conversation. The filter redacts common patterns (`password=…`, `sk-…`, `ghp_…`, `AKIA…`, private keys…) but cannot catch everything. If needed, enable encryption: `age-keygen -o ~/.config/worklog/key.txt`, then set `WORKLOG_AGE_RECIPIENT=age1...` on every machine; read files back with `age -d -i ~/.config/worklog/key.txt <file> | zstd -dc` (or `zcat` for `.gz`).
- Context loaded at session start comes from earlier AI summaries, which may have been influenced by untrusted content (web pages, tool output). It is wrapped and labeled as reference data, not instructions; turn it off with `WORKLOG_CONTEXT=0` if you prefer.
- `WORKLOG_AUTO_UPDATE=1` means the latest code from the remote of `~/worklog-tool` runs automatically. If you cloned someone else's repo, fork it to your own account or set `WORKLOG_AUTO_UPDATE=0`.
- On shared servers, use a **deploy key** with write access to the data repo only.

## Troubleshooting

Background errors are logged to `~/.local/state/worklog/core.log`. To run things by hand:

```bash
~/worklog-tool/hooks/core.sh claude "$PWD" /path/to/transcript.jsonl "" <session_id>
~/worklog-tool/hooks/sweep.sh --all          # archive every transcript on this machine not yet stored
~/worklog-tool/hooks/context.sh "$PWD"       # show the context a new session would get here
jq -nRc --arg tool claude -f ~/worklog-tool/hooks/meta.jq < transcript.jsonl   # numbers for one session
```

## Uninstall

Remove the hooks containing `worklog` from `~/.claude/settings.json`, `~/.gemini/settings.json` and `~/.codex/hooks.json`; delete `~/.copilot/hooks/worklog.json`, `~/.claude/skills/worklog` and `~/.config/worklog/`; and remove the `<!-- worklog:start -->…<!-- worklog:end -->` block from `GEMINI.md` / `AGENTS.md`.
