#!/usr/bin/env bash
# worklog — hook chung cho mọi CLI agent.
#   hook.sh <tool> <event>
#   tool : claude | gemini | codex | copilot
#   event: start | end | agentstop (agentstop chỉ dùng cho copilot)
# Đọc payload JSON từ stdin, chuẩn hoá, rồi giao cho core.sh chạy nền.

[ -n "$WORKLOG_RUNNING" ] && exit 0      # chặn đệ quy khi chính worklog gọi CLI để tóm tắt
command -v jq >/dev/null || exit 0

TOOL="$1"; EVENT="$2"
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"

input=$(cat)
j() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
sid=$(j '.session_id // .sessionId')
tpath=$(j '.transcript_path // .transcriptPath')
cwd=$(j '.cwd'); cwd="${cwd:-$PWD}"
key="$TOOL-${sid:-nosession}"

# Tách hẳn khỏi CLI để CLI thoát ngay (Codex chỉ cho hook tối đa 3 giây).
detach() {
  if command -v setsid >/dev/null; then setsid "$@"
  elif command -v perl >/dev/null; then perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' "$@"   # macOS
  else "$@"; fi
}

case "$EVENT" in
  start)
    date +%s > "$STATE/$key.start"
    # Bộ nhớ dài hạn: nạp ngữ cảnh dự án (việc còn dở + mục nhật ký gần nhất) vào đầu session.
    # Đọc bản local có sẵn, không chờ pull. Hiện chỉ cho Claude Code (CLI khác chưa kiểm chứng định dạng).
    if [ "$TOOL" = claude ]; then
      ctx=$("$HERE/context.sh" "$cwd" 2>/dev/null)
      [ -n "$ctx" ] && jq -nc --arg c "$ctx" \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
    fi
    ( WORKLOG_RUNNING=1
      lock_data && { pull_data; unlock_data; }
      # Tự cập nhật code worklog-tool (tắt bằng WORKLOG_AUTO_UPDATE=0)
      [ "${WORKLOG_AUTO_UPDATE:-1}" = 1 ] && git -C "$HERE/.." pull -q --ff-only
      # Lưu trữ transcript còn sót (tối đa 1 lần/giờ, xem sweep.sh)
      detach nohup "$HERE/sweep.sh" >>"$STATE/core.log" 2>&1 </dev/null &
    ) >/dev/null 2>&1 </dev/null &
    ;;
  agentstop)
    [ -n "$tpath" ] && printf '%s\n' "$tpath" > "$STATE/$key.transcript"
    ;;
  end)
    [ -z "$tpath" ] && [ -f "$STATE/$key.transcript" ] && tpath=$(cat "$STATE/$key.transcript")
    start=$(cat "$STATE/$key.start" 2>/dev/null)
    rm -f "$STATE/$key.start" "$STATE/$key.transcript"
    WORKLOG_RUNNING=1 detach nohup "$HERE/core.sh" "$TOOL" "$cwd" "$tpath" "$start" "$sid" \
      >>"$STATE/core.log" 2>&1 </dev/null &
    ;;
esac
exit 0
