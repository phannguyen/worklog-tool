#!/usr/bin/env bash
# Install worklog for every CLI agent on this machine: Claude Code, Gemini CLI, Codex CLI, Copilot CLI.
# Safe to run again at any time (also upgrades older installs).
#
#   First time:  ~/worklog-tool/install.sh git@github.com:<user>/worklog.git
#   Later:       ~/worklog-tool/install.sh
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$TOOL_DIR/hooks/lib.sh"          # loads config: DATA, HOST, CLAUDE_DIR, WL_LANG
HOOK="$TOOL_DIR/hooks/hook.sh"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
skip() { printf '  \033[90m–\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

# 0. Per-machine config (KEY=value). Hooks read this file because CLIs started from an IDE/menu
#    often do not get the variables from ~/.bashrc. Environment variables of the same name win.
CONF="$WORKLOG_CONFIG"; mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || printf '%s\n' "# worklog config for this machine (KEY=value). Environment variables of the same name take precedence." \
                                "# Variables: see the Configuration section of the worklog-tool README." >"$CONF"
conf_get() { grep -E "^$1=" "$CONF" | tail -1 | cut -d= -f2-; }
conf_set() { grep -qE "^$1=" "$CONF" || printf '%s=%s\n' "$1" "$2" >>"$CONF"; }
if [ -z "$(conf_get WORKLOG_LANG)" ]; then
  lang="${WORKLOG_LANG:-}"
  if [ -z "$lang" ] && [ -t 0 ]; then read -rp "Journal language / Ngôn ngữ viết nhật ký (en|vi) [$WL_LANG]: " lang; fi
  case "$lang" in vi|en) ;; *) lang="$WL_LANG" ;; esac
  conf_set WORKLOG_LANG "$lang"
fi
WL_LANG="$(conf_get WORKLOG_LANG)"; [ -n "${WORKLOG_LANG:-}" ] && WL_LANG="$WORKLOG_LANG"
# Variables set while installing are saved so the hooks see them too
for k in WORKLOG_DIR WORKLOG_HOST WORKLOG_SUMMARIZER WORKLOG_CLAUDE_MODEL WORKLOG_AGE_RECIPIENT \
         WORKLOG_AGE_RECIPIENTS_FILE CLAUDE_CONFIG_DIR CODEX_HOME COPILOT_HOME; do
  [ -n "${!k:-}" ] && conf_set "$k" "${!k}"
done

echo "$(L "Cài worklog trên máy" "Installing worklog on machine"): $HOST"
ok "$(L "Cấu hình" "Config"): $CONF ($(L "ngôn ngữ nhật ký" "journal language"): $WL_LANG)"

# 1. Required tools
for c in git jq; do
  command -v "$c" >/dev/null || fail "$(L "Thiếu" "Missing") '$c' (Fedora: sudo dnf install -y $c | Debian/Ubuntu: sudo apt install -y $c | macOS: brew install $c)"
done
found=""; for c in claude gemini codex copilot; do command -v "$c" >/dev/null && found="$found $c"; done
[ -n "$found" ] || fail "$(L "Không thấy CLI nào" "No supported CLI found") (claude, gemini, codex, copilot)"
ok "git, jq. $(L "CLI tìm thấy" "CLIs found"):$found"
command -v zstd >/dev/null || warn "$(L "Không có zstd — archive sẽ nén bằng gzip (to hơn). Nên cài zstd." \
                                       "zstd not found — archives will use gzip (larger). Installing zstd is recommended.")"

# 2. Data repo (private)
if [ ! -d "$DATA/.git" ]; then
  [ $# -ge 1 ] || fail "$(L "Chưa có $DATA. Chạy lại kèm URL repo dữ liệu private:" "$DATA does not exist yet. Run again with the URL of your private data repo:")  $0 git@github.com:<user>/worklog.git"
  git clone -q "$1" "$DATA" || fail "$(L "Không clone được" "Could not clone") $1"
fi
# Separate commit identity for the journal repo (e.g. keep a work email in the global git config).
#   WORKLOG_GIT_EMAIL / WORKLOG_GIT_NAME, or asked interactively; kept once set.
if [ -z "$(git -C "$DATA" config --local user.email || true)" ]; then
  email="${WORKLOG_GIT_EMAIL:-}"
  if [ -z "$email" ] && [ -t 0 ]; then
    read -rp "  $(L "Email cho commit nhật ký" "Email for journal commits") [$(git config --global user.email || true)]: " email
  fi
  email="${email:-$(git config --global user.email || true)}"
  [ -n "$email" ] || fail "$(L "Chưa có email cho git. Đặt WORKLOG_GIT_EMAIL=<email> rồi chạy lại" "No git email. Set WORKLOG_GIT_EMAIL=<email> and run again")"
  git -C "$DATA" config user.email "$email"
  name="${WORKLOG_GIT_NAME:-$(git config --global user.name || true)}"
  git -C "$DATA" config user.name "${name:-$(whoami)}"
fi
ok "$(L "Commit nhật ký dưới tên" "Journal commits as"): $(git -C "$DATA" config user.name) <$(git -C "$DATA" config user.email)>"
if ! git -C "$DATA" rev-parse --verify -q HEAD >/dev/null; then
  printf '# Worklog\n\n%s\n' "$(L "Nhật ký làm việc tự động từ các AI coding agent. Công cụ: worklog-tool." \
                                  "Automatic work journal from AI coding agents. Tool: worklog-tool.")" > "$DATA/README.md"
  git -C "$DATA" add README.md && git -C "$DATA" commit -qm "init worklog"
  git -C "$DATA" push -q -u origin HEAD || fail "$(L "Không push được commit đầu lên repo dữ liệu" "Could not push the first commit to the data repo")"
fi
ok "$(L "Repo dữ liệu" "Data repo"): $DATA"
chmod +x "$TOOL_DIR"/hooks/*.sh

# Remove old worklog hooks, then add the new ones, in a JSON file shaped {hooks:{Event:[{hooks:[...]}]}}.
# Ours are matched exactly: a command pointing at $HOOK (also after moving: */hooks/hook.sh <tool> start|end),
# a name starting with worklog-, or the v1 ~/.claude/hooks/worklog.sh. The user's other hooks are kept.
# $1=file  $2=jq filter adding hooks (uses $hook)
set_json_hooks() {
  local f="$1" add="$2"
  mkdir -p "$(dirname "$f")"; [ -s "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || { warn "$f $(L "không phải JSON hợp lệ, bỏ qua" "is not valid JSON, skipped")"; return 1; }
  [ -e "$f.bak.worklog" ] || cp "$f" "$f.bak.worklog"          # keep the original from before the first install
  jq --arg hook "$HOOK" '
      def ours: (.command // "") as $c
        | ($c | contains($hook)) or ($c | test("/hooks/hook\\.sh\"? (claude|gemini|codex) (start|end)$"))
          or ($c | contains("/.claude/hooks/worklog.sh")) or ((.name // "") | startswith("worklog-"));
      .hooks = ((.hooks // {}) | with_entries(
        if (.value | type) == "array" then
          .value |= (map(if (.hooks | type) == "array" then .hooks |= map(select(ours | not)) else . end)
                     | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
        else . end))
      | '"$add" "$f" > "$f.tmp" || { rm -f "$f.tmp"; warn "$(L "Không cập nhật được" "Could not update") $f"; return 1; }
  cat "$f.tmp" > "$f" && rm -f "$f.tmp"                          # overwrite contents, keeps symlinks
}
none="$(L "không có" "not installed")"

# 3a. Claude Code
if command -v claude >/dev/null; then
  rm -f "$CLAUDE_DIR/hooks/worklog.sh"                       # v1
  # cleanupPeriodDays: Claude Code deletes transcripts after 30 days by default — keep them a year so
  # sweep can archive them (only set when the user has not configured it).
  set_json_hooks "$CLAUDE_DIR/settings.json" '
    .hooks.SessionStart += [{"hooks":[{"type":"command","command":"\"\($hook)\" claude start"}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"type":"command","command":"\"\($hook)\" claude end"}]}]
  | .cleanupPeriodDays //= 365' \
    && { mkdir -p "$CLAUDE_DIR/skills"; ln -sfn "$TOOL_DIR/skill" "$CLAUDE_DIR/skills/worklog"
         ok "Claude Code: hook + skill ($(L "giữ transcript" "transcripts kept") $(jq -r .cleanupPeriodDays "$CLAUDE_DIR/settings.json") $(L "ngày" "days"))"; }
else skip "Claude Code: $none"; fi

# 3b. Gemini CLI
if command -v gemini >/dev/null; then
  set_json_hooks "$HOME/.gemini/settings.json" '
    .hooks.SessionStart += [{"hooks":[{"name":"worklog-start","type":"command","command":"\"\($hook)\" gemini start","timeout":10000}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"name":"worklog-end","type":"command","command":"\"\($hook)\" gemini end","timeout":10000}]}]' \
    && ok "Gemini CLI: hook"
else skip "Gemini CLI: $none"; fi

# 3c. Codex CLI
if command -v codex >/dev/null; then
  set_json_hooks "${CODEX_HOME:-$HOME/.codex}/hooks.json" '
    .hooks.SessionStart += [{"hooks":[{"type":"command","command":"\"\($hook)\" codex start","timeout":10}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"type":"command","command":"\"\($hook)\" codex end","timeout":3}]}]' \
    && { ok "Codex CLI: hook"
         warn "$(L "Codex: mở codex, gõ /hooks và chọn trust 2 hook worklog (Codex không chạy hook chưa được trust)" \
                   "Codex: open codex, type /hooks and trust the 2 worklog hooks (Codex does not run untrusted hooks)")"; }
else skip "Codex CLI: $none"; fi

# 3d. Copilot CLI (own file, safe to overwrite)
if command -v copilot >/dev/null; then
  cdir="${COPILOT_HOME:-$HOME/.copilot}/hooks"; mkdir -p "$cdir"
  jq -n --arg hook "$HOOK" '{version:1, hooks:{
      sessionStart:[{type:"command", bash:"\"\($hook)\" copilot start",     timeoutSec:10}],
      agentStop:   [{type:"command", bash:"\"\($hook)\" copilot agentstop", timeoutSec:5}],
      sessionEnd:  [{type:"command", bash:"\"\($hook)\" copilot end",       timeoutSec:10}]}}' > "$cdir/worklog.json"
  ok "Copilot CLI: hook"
else skip "Copilot CLI: $none"; fi

# 4. Tell Gemini / Codex where the journal is (marked block, updated in place)
note="<!-- worklog:start -->
$(L "Nhật ký làm việc của tôi nằm ở $DATA (mỗi tháng một file cho mỗi máy, ví dụ 2026/11-laptop.md).
Khi tôi hỏi đã làm gì, xin tổng kết, hỏi việc còn dở hay thống kê, hoặc nói \"ghi nhật ký\": đọc và làm theo $TOOL_DIR/skill/SKILL.md." \
"My work journal is in $DATA (one file per month per machine, e.g. 2026/11-laptop.md).
When I ask what I worked on, ask for a review, open items or stats, or say \"log this\": read and follow $TOOL_DIR/skill/SKILL.md.")
<!-- worklog:end -->"
put_note() {
  local f="$1"; mkdir -p "$(dirname "$f")"; touch "$f"
  awk '/<!-- worklog:start -->/{s=1} !s{print} /<!-- worklog:end -->/{s=0}' "$f" > "$f.tmp"
  local old; old=$(cat "$f.tmp"); rm -f "$f.tmp"
  if [ -n "${old//[[:space:]]/}" ]; then printf '%s\n\n%s\n' "$old" "$note" > "$f"; else printf '%s\n' "$note" > "$f"; fi
}
command -v gemini >/dev/null && put_note "$HOME/.gemini/GEMINI.md" && ok "Gemini: $(L "thêm chỉ dẫn vào" "note added to") ~/.gemini/GEMINI.md"
command -v codex  >/dev/null && put_note "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" && ok "Codex: $(L "thêm chỉ dẫn vào" "note added to") AGENTS.md"

# 5. Push access
git -C "$DATA" push --dry-run -q >/dev/null 2>&1 \
  && ok "$(L "Push được lên repo dữ liệu" "Can push to the data repo")" \
  || fail "$(L "Chưa push được repo dữ liệu. Kiểm tra SSH key:" "Cannot push to the data repo. Check your SSH key:")  ssh -T git@github.com"

# 6. Archive the old transcripts already on this machine (re-running stores nothing twice)
echo "  … $(L "lưu trữ transcript Claude Code / Codex có sẵn trên máy (lần đầu có thể mất vài phút)" \
              "archiving existing Claude Code / Codex transcripts (the first run can take a few minutes)")"
"$TOOL_DIR/hooks/sweep.sh" --all && ok "$(L "Lưu trữ xong" "Archived"): $DATA/archive/, $(L "số liệu" "numbers"): $DATA/meta/" \
  || warn "$(L "Lưu trữ chưa xong — xem log, hook mở session sẽ thử lại" "Archiving did not finish — see the log; the session-start hook will retry")"

echo
echo "$(L "Xong. Nhật ký của máy này" "Done. This machine's journal"): $DATA/$(date +%Y)/$(date +%m)-$HOST.md"
echo "$(L "Log lỗi (nếu có)" "Error log (if any)"): $STATE/core.log"
