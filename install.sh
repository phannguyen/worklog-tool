#!/usr/bin/env bash
# Cài worklog cho mọi CLI agent có trên máy này: Claude Code, Gemini CLI, Codex CLI, Copilot CLI.
# Chạy lại nhiều lần cũng an toàn (cũng dùng để cập nhật từ v1).
#
#   Lần đầu:   ~/worklog-tool/install.sh git@github.com:<user>/worklog.git
#   Về sau:    ~/worklog-tool/install.sh
set -euo pipefail

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$TOOL_DIR/hooks/lib.sh"          # đọc cấu hình: DATA, HOST, CLAUDE_DIR, WL_LANG
HOOK="$TOOL_DIR/hooks/hook.sh"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
skip() { printf '  \033[90m–\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

echo "Cài worklog trên máy: $HOST"

# 1. Công cụ bắt buộc
for c in git jq; do
  command -v "$c" >/dev/null || fail "Thiếu '$c' (Fedora: sudo dnf install -y $c | Ubuntu: sudo apt install -y $c | macOS: brew install $c)"
done
found=""; for c in claude gemini codex copilot; do command -v "$c" >/dev/null && found="$found $c"; done
[ -n "$found" ] || fail "Không thấy CLI nào (claude, gemini, codex, copilot)"
ok "Có git, jq. CLI tìm thấy:$found"

# 2. Repo dữ liệu (private)
if [ ! -d "$DATA/.git" ]; then
  [ $# -ge 1 ] || fail "Chưa có $DATA. Chạy lại kèm URL repo dữ liệu private:  $0 git@github.com:<user>/worklog.git"
  git clone -q "$1" "$DATA" || fail "Không clone được $1"
fi
# Danh tính commit riêng cho repo nhật ký (không dùng email công ty trong git global).
#   WORKLOG_GIT_EMAIL / WORKLOG_GIT_NAME, hoặc hỏi khi chạy tay; đã đặt rồi thì giữ nguyên.
if [ -z "$(git -C "$DATA" config --local user.email)" ]; then
  email="${WORKLOG_GIT_EMAIL:-}"
  if [ -z "$email" ] && [ -t 0 ]; then
    read -rp "  Email cho commit nhật ký [$(git config --global user.email || true)]: " email
  fi
  email="${email:-$(git config --global user.email || true)}"
  [ -n "$email" ] || fail "Chưa có email cho git. Đặt WORKLOG_GIT_EMAIL=<email> rồi chạy lại"
  git -C "$DATA" config user.email "$email"
  name="${WORKLOG_GIT_NAME:-$(git config --global user.name || true)}"
  git -C "$DATA" config user.name "${name:-$(whoami)}"
fi
ok "Commit nhật ký dưới tên: $(git -C "$DATA" config user.name) <$(git -C "$DATA" config user.email)>"
if ! git -C "$DATA" rev-parse --verify -q HEAD >/dev/null; then
  printf '# Worklog\n\nNhật ký làm việc tự động từ các AI coding agent. Công cụ: worklog-tool.\n' > "$DATA/README.md"
  git -C "$DATA" add README.md && git -C "$DATA" commit -qm "khởi tạo worklog"
  git -C "$DATA" push -q -u origin HEAD || fail "Không push được commit đầu lên repo dữ liệu"
fi
ok "Repo dữ liệu ở $DATA"

# Cấu hình của máy này (KEY=value). Hook đọc file này vì CLI mở từ IDE/menu thường không có biến của ~/.bashrc.
CONF="$WORKLOG_CONFIG"; mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || printf '%s\n' "# Cấu hình worklog cho máy này (KEY=value). Biến môi trường cùng tên được ưu tiên." \
                                "# Các biến: xem phần Tuỳ chỉnh trong README của worklog-tool." >"$CONF"
conf_get() { grep -E "^$1=" "$CONF" | tail -1 | cut -d= -f2-; }
conf_set() { grep -qE "^$1=" "$CONF" || printf '%s=%s\n' "$1" "$2" >>"$CONF"; }
if [ -z "$(conf_get WORKLOG_LANG)" ]; then
  lang="${WORKLOG_LANG:-}"
  if [ -z "$lang" ] && [ -t 0 ]; then read -rp "  Ngôn ngữ viết nhật ký / journal language (vi|en) [$WL_LANG]: " lang; fi
  case "$lang" in vi|en) ;; *) lang="$WL_LANG" ;; esac
  conf_set WORKLOG_LANG "$lang"
fi
# Biến đang đặt lúc cài thì lưu lại để hook cũng thấy
for k in WORKLOG_DIR WORKLOG_HOST WORKLOG_SUMMARIZER WORKLOG_CLAUDE_MODEL WORKLOG_AGE_RECIPIENT \
         WORKLOG_AGE_RECIPIENTS_FILE CLAUDE_CONFIG_DIR CODEX_HOME COPILOT_HOME; do
  [ -n "${!k:-}" ] && conf_set "$k" "${!k}"
done
ok "Cấu hình: $CONF (ngôn ngữ nhật ký: $(conf_get WORKLOG_LANG), tên máy: $HOST)"
chmod +x "$TOOL_DIR"/hooks/*.sh

# Gỡ hook worklog cũ rồi thêm hook mới vào một file JSON kiểu {hooks:{Event:[{hooks:[...]}]}}
# Hook cũ nhận diện chính xác: lệnh trỏ tới $HOOK (cả khi đổi thư mục: */hooks/hook.sh <tool> start|end),
# tên worklog-*, hoặc bản v1 ~/.claude/hooks/worklog.sh. Hook khác của người dùng giữ nguyên.
# $1=file  $2=jq filter thêm hook (dùng biến $hook)
set_json_hooks() {
  local f="$1" add="$2"
  mkdir -p "$(dirname "$f")"; [ -s "$f" ] || echo '{}' > "$f"
  jq -e . "$f" >/dev/null 2>&1 || { warn "$f không phải JSON hợp lệ, bỏ qua"; return 1; }
  [ -e "$f.bak.worklog" ] || cp "$f" "$f.bak.worklog"          # giữ bản gốc trước lần cài đầu tiên
  jq --arg hook "$HOOK" '
      def ours: (.command // "") as $c
        | ($c | contains($hook)) or ($c | test("/hooks/hook\\.sh\"? (claude|gemini|codex) (start|end)$"))
          or ($c | contains("/.claude/hooks/worklog.sh")) or ((.name // "") | startswith("worklog-"));
      .hooks = ((.hooks // {}) | with_entries(
        if (.value | type) == "array" then
          .value |= (map(if (.hooks | type) == "array" then .hooks |= map(select(ours | not)) else . end)
                     | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
        else . end))
      | '"$add" "$f" > "$f.tmp" || { rm -f "$f.tmp"; warn "Không cập nhật được $f"; return 1; }
  cat "$f.tmp" > "$f" && rm -f "$f.tmp"                          # ghi đè nội dung, giữ symlink nếu có
}

# 3a. Claude Code
if command -v claude >/dev/null; then
  rm -f "$CLAUDE_DIR/hooks/worklog.sh"                       # bản v1
  # cleanupPeriodDays: Claude Code mặc định xoá transcript sau 30 ngày — giữ 1 năm để sweep kịp lưu trữ
  # (chỉ đặt khi người dùng chưa tự cấu hình).
  set_json_hooks "$CLAUDE_DIR/settings.json" '
    .hooks.SessionStart += [{"hooks":[{"type":"command","command":"\"\($hook)\" claude start"}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"type":"command","command":"\"\($hook)\" claude end"}]}]
  | .cleanupPeriodDays //= 365' \
    && { mkdir -p "$CLAUDE_DIR/skills"; ln -sfn "$TOOL_DIR/skill" "$CLAUDE_DIR/skills/worklog"
         ok "Claude Code: hook + skill (giữ transcript $(jq -r .cleanupPeriodDays "$CLAUDE_DIR/settings.json") ngày)"; }
else skip "Claude Code: không có"; fi

# 3b. Gemini CLI
if command -v gemini >/dev/null; then
  set_json_hooks "$HOME/.gemini/settings.json" '
    .hooks.SessionStart += [{"hooks":[{"name":"worklog-start","type":"command","command":"\"\($hook)\" gemini start","timeout":10000}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"name":"worklog-end","type":"command","command":"\"\($hook)\" gemini end","timeout":10000}]}]' \
    && ok "Gemini CLI: hook"
else skip "Gemini CLI: không có"; fi

# 3c. Codex CLI
if command -v codex >/dev/null; then
  set_json_hooks "${CODEX_HOME:-$HOME/.codex}/hooks.json" '
    .hooks.SessionStart += [{"hooks":[{"type":"command","command":"\"\($hook)\" codex start","timeout":10}]}]
  | .hooks.SessionEnd   += [{"hooks":[{"type":"command","command":"\"\($hook)\" codex end","timeout":3}]}]' \
    && { ok "Codex CLI: hook"
         warn "Codex: mở codex, gõ /hooks và chọn trust 2 hook worklog (Codex không chạy hook chưa được trust)"; }
else skip "Codex CLI: không có"; fi

# 3d. Copilot CLI (file riêng, ghi đè an toàn)
if command -v copilot >/dev/null; then
  cdir="${COPILOT_HOME:-$HOME/.copilot}/hooks"; mkdir -p "$cdir"
  jq -n --arg hook "$HOOK" '{version:1, hooks:{
      sessionStart:[{type:"command", bash:"\"\($hook)\" copilot start",     timeoutSec:10}],
      agentStop:   [{type:"command", bash:"\"\($hook)\" copilot agentstop", timeoutSec:5}],
      sessionEnd:  [{type:"command", bash:"\"\($hook)\" copilot end",       timeoutSec:10}]}}' > "$cdir/worklog.json"
  ok "Copilot CLI: hook"
else skip "Copilot CLI: không có"; fi

# 4. Chỉ dẫn cho Gemini / Codex biết nhật ký nằm đâu (khối có đánh dấu, cập nhật được)
note="<!-- worklog:start -->
Nhật ký làm việc của tôi nằm ở $DATA (mỗi tháng một file cho mỗi máy, ví dụ 2026/11-laptop.md).
Khi tôi hỏi đã làm gì, xin tổng kết, hoặc nói \"ghi nhật ký\": đọc và làm theo $TOOL_DIR/skill/SKILL.md.
<!-- worklog:end -->"
put_note() {
  local f="$1"; mkdir -p "$(dirname "$f")"; touch "$f"
  awk '/<!-- worklog:start -->/{s=1} !s{print} /<!-- worklog:end -->/{s=0}' "$f" > "$f.tmp"
  local old; old=$(cat "$f.tmp"); rm -f "$f.tmp"
  if [ -n "${old//[[:space:]]/}" ]; then printf '%s\n\n%s\n' "$old" "$note" > "$f"; else printf '%s\n' "$note" > "$f"; fi
}
command -v gemini >/dev/null && put_note "$HOME/.gemini/GEMINI.md" && ok "Gemini: thêm chỉ dẫn vào ~/.gemini/GEMINI.md"
command -v codex  >/dev/null && put_note "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" && ok "Codex: thêm chỉ dẫn vào AGENTS.md"

# 5. Quyền push
git -C "$DATA" push --dry-run -q >/dev/null 2>&1 \
  && ok "Push được lên repo dữ liệu" \
  || fail "Chưa push được repo dữ liệu. Kiểm tra SSH key:  ssh -T git@github.com"

# 6. Lưu trữ transcript cũ còn trên máy (chạy lại không lưu trùng)
echo "  … lưu trữ transcript Claude Code / Codex có sẵn trên máy (lần đầu có thể mất vài phút)"
"$TOOL_DIR/hooks/sweep.sh" --all && ok "Lưu trữ xong: $DATA/archive/, số liệu: $DATA/meta/" \
  || warn "Lưu trữ chưa xong — xem log, hook mở session sẽ thử lại"

echo
echo "Xong. Nhật ký của máy này: $DATA/$(date +%Y)/$(date +%m)-$HOST.md (transcript gốc: $DATA/raw/)"
echo "Log lỗi (nếu có): $STATE/core.log"
