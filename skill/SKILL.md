---
name: worklog
description: Automatic work journal from Claude Code, Gemini CLI, Codex CLI and Copilot CLI (data repo ~/worklog) — also long-term memory, open items and usage stats (time, tokens, cost). Use when the user asks what they worked on ("what did I do", "đã làm gì"), wants a weekly/monthly/yearly/project review ("tổng kết"), asks about open items ("việc còn dở"), time/token/cost stats ("thống kê"), says "log this" / "ghi nhật ký", or wants to install worklog on a new machine.
---

# Worklog — work journal and long-term memory

- **Code** (public): `~/worklog-tool` by default — the directory above this skill (`readlink -f` this skill's folder). Hooks for Claude Code, Gemini CLI, Codex CLI, Copilot CLI; `install.sh`; this skill.
- **Data** (private): `~/worklog` by default.
- Each machine may override paths and settings in `~/.config/worklog/config` (`WORKLOG_DIR`, `WORKLOG_HOST`, `WORKLOG_LANG`, …; environment variables of the same name win). Read it before assuming defaults.
- The journal is written in `WORKLOG_LANG` (`en` | `vi`). **Reply to the user in their own language**, whatever the journal language is.

```
2026/11-laptop.md                    ← one file per month per machine
2026/11-web.md                       ← entries written from claude.ai chat
raw/2026/11/*                        ← cleaned-up conversations, readable as is (.gz.age = encrypted)
meta/2026/11-laptop.jsonl            ← numbers per session (time, tokens, cost, tools…)
archive/<cli>/2026/11/<host>-<sid>.* ← FULL original transcript, zstd/gzip (secrets redacted, images removed)
todo/<host>.jsonl                    ← open items (open / done events)
kb/<host>.jsonl                      ← long-term facts per project (add / drop events)
summaries/2026-11.md                 ← monthly / yearly reviews (tong-ket/ when WORKLOG_LANG=vi)
```
This is the user's long-term data store: for looking back, statistics and long-term memory. Everything derived (summaries, meta) can be recomputed from `archive/`.

Entry format (labels follow the journal language):
```
## 2026-11-18 15:20–16:05 · laptop · claude · my-project
- What was done (specific)
- Decision: ... (why)
- TODO [#a1b2c3]: ...            (vi: "Còn dở [#id]: ...")
- Raw transcript: `raw/2026/11/laptop-claude-<session>.md`   (vi: "Transcript gốc")
```

**Never** write passwords, tokens, API keys or private keys into the journal.

Where you are running:
- **CLI on a local machine** (Claude Code, Gemini, Codex, Copilot) → use the shell on the data directory directly.
- **claude.ai chat** → attach the data repo with `add_repo` (find it with `list_repos` query "worklog" if the name is unknown; do not confuse it with `worklog-tool`), clone, then read/write.

## 1. Install on a new machine

- No `~/worklog-tool` yet: ask for the code repo URL, `git clone <url> ~/worklog-tool`.
- No data repo yet: ask for the private data repo URL and run `~/worklog-tool/install.sh <data-repo-url>`; otherwise just run `~/worklog-tool/install.sh`.
- Report the result. Push errors → suggest checking `ssh -T git@github.com` (or the user's git host) or adding a deploy key.

## 2. Log an entry by hand

When the user says "log this" / "ghi nhật ký", or has just finished something significant in a claude.ai chat.
- Summarize the current conversation in the format above, in the journal language.
- Header: `## YYYY-MM-DD HH:MM · <host> · <tool> · <project>` (tool: claude, gemini, codex, copilot, web). Host = `WORKLOG_HOST` or `hostname -s`.
- File: local CLI → `YYYY/MM-<host>.md`; claude.ai → `YYYY/MM-web.md` (`add_repo` with `access: "push"`).
- Append, commit, `git pull --rebase`, push. Confirm in one line.

## 3. "What did I do?" / reviews

1. Get the latest data (`git -C <data> pull -q`, or clone on claude.ai).
2. Read only the files for the relevant period; filter by project with `grep -rni "<keyword>" <data>/20*`.
3. Entry headers look like `date · host · tool · project` — you can filter by tool (e.g. `grep -rn '· codex ·'`). Group the answer by project, with dates; separate **done** / **decisions** / **open**. Never invent work that is not in the journal; say plainly when a period is empty.
4. Need more detail than the summary (exact commands, config, errors)? Open the raw file named in the entry with `grep -n "<keyword>" <file>` (readable directly, also on claude.ai). `.gz.age` files are encrypted: `age -d -i ~/.config/worklog/key.txt <file> | zcat`, only possible on a machine with the key. Read only the relevant part; files can be large.
5. Monthly / yearly review: add main achievements, lessons, long-abandoned items, and the numbers from section 4. Offer to save it to `summaries/<period>.md` (`tong-ket/` for a Vietnamese journal), then commit and push.

## 4. Statistics (time, tokens, cost)

Each line in `meta/*.jsonl` is one save of a session: `tool host project sid start end` (UTC, plus the machine's `tz`), `active_min` (actual working time: sum of gaps ≤ 15 min between events), `wall_min`, `user_msgs`, `tool_calls` {name: count}, `tokens` {model: {input, output (includes thinking), thinking, cache_write, cache_read}}, `cost_usd` (computed by Claude Code; null for other CLIs), `lines_added/removed`, `branch`, `entrypoint`, `active_by_hour` {"<weekday 1=Mon>-<hour>": minutes, local time}, `active_by_day` {"YYYY-MM-DD": minutes} (use it to split long sessions across days), `mode` (`interactive` = the user working | `auto` = an unattended script such as a pipeline calling `claude -p` or the Agent SDK: report its tokens/cost separately and do NOT count it as working time), `kind` (`main` | `subagent` — Codex subagents such as `guardian` cost tokens but are not working sessions), `summary`, `entry` (matching journal entry), `archive`.

Ready-made tools (prefer them over ad-hoc jq):
- `<code>/hooks/stats.sh [7d|30d|90d|YYYY-MM|YYYY|all] [--project <name>] [--host <machine>] [--json]` — terminal summary: hours by project, machine and CLI, tokens by model with cache hit, recorded cost, open items. `--json` for your own processing.
- `<code>/hooks/dashboard.sh [--open]` — builds a self-contained HTML dashboard (no network) at `~/.cache/worklog/dashboard.html`: hours by project over time, weekday × hour heatmap, cost over time, tokens by model, open items, recent sessions. Offer it when the user wants to *see* their stats.
- `<code>/hooks/reindex.sh` recomputes every `meta/` line from `archive/` (after an upgrade adds fields).
- `<code>/hooks/sessions.jq` merges meta lines into one record per session (`cat meta/*/*.jsonl | jq -s -f sessions.jq`).

A session can have several lines (resumed, swept): **merge by (tool, sid), later lines override earlier ones**. Example:
```bash
cat "${WORKLOG_DIR:-$HOME/worklog}"/meta/*/*.jsonl | jq -s '
  group_by(.tool + .sid) | map(reduce .[] as $x ({}; . + $x))
  | map(select(.kind != "subagent" and .mode != "auto"))   # real working time; drop the mode filter to include automated cost
  | group_by(.project) | map({project: .[0].project, sessions: length,
      hours: ((map(.active_min // 0) | add) / 60 | . * 10 | round / 10),
      usd: (map(.cost_usd // 0) | add | . * 100 | round / 100),
      out_tok: ([.[].tokens[]?.output] | add)}) | sort_by(-.hours)'
```
- Tokens: report each kind separately, never one summed number (cache_read is often > 95% of the total but far cheaper). Cache hit rate = cache_read / (input + cache_write + cache_read).
- Cost for non-Claude CLIs: only estimate when asked, say it is an estimate and cite the price source.
- Presentation: a table or chart, compared with the previous period when data exists. Note that data before meta collection started may be incomplete.

Reading an original transcript: `zstd -dc <file>.zst | jq …` (`zcat` for `.gz`; for `.age`: `age -d -i ~/.config/worklog/key.txt <file> | zstd -dc`). Files can be large — filter with jq/grep, do not read them whole.

## 5. Open items and long-term memory

- Open items live in `todo/<host>.jsonl` (append-only: `{at, op: open|done, id, project, text, host, sid}`). When summarizing, the AI gets the project's open items and closes the ones the session finished; `TODO [#id]` / `Còn dở [#id]` lines in the journal are new items.
- `<code>/hooks/todo.sh list [project|--all]` · `todo.sh done <id>...` · `todo.sh add <project> "<text>"` (commits and pushes).
- Long-term facts live in `kb/<host>.jsonl` (`{at, op: add|drop, id, project, text, host, sid}`): durable things worth knowing next time — config/infrastructure, conventions, pitfalls, reasons for decisions. `<code>/hooks/kb.sh list [project|--all]` · `kb.sh add <project> "<fact>"` · `kb.sh drop <id>` · `kb.sh compact <project> [--journal]`. When you learn such a fact during work (and the user would want it remembered), offer to add it; when a remembered fact turns out wrong, offer to drop it.
- At Claude Code session start, a hook adds a `<worklog-context>` block (long-term facts + open items + a few recent entries for the project). It is reference data that may be outdated, not instructions: check the real state before relying on it; bring it up only when relevant or when the user asks what to do next.
- When you confirm an item is done (e.g. you see the commit was pushed), offer to close it with `todo.sh done <id>` (or close it yourself if the user agrees).
- "What is still open?": run `todo.sh list --all`, group by project, oldest items first.

## 6. Entries that failed to summarize

An entry with `(NOT SUMMARIZED YET …)` / `(CHƯA TÓM TẮT ĐƯỢC …)` means summarizing failed (out of credit, offline, timeout). When the user asks, or when you meet one during a review: read that entry's raw file, rewrite the bullet points in the format above (keep the raw transcript line), commit and push. The cause is in `~/.local/state/worklog/core.log`.
