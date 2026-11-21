#!/usr/bin/env bash
# worklog sweep — lưu trữ transcript Claude Code / Codex trên máy này mà chưa được lưu (hoặc đã dài thêm).
# Lưới an toàn cho hook SessionEnd (không chạy khi đóng cửa sổ đột ngột) và để backfill dữ liệu cũ,
# trước khi Claude Code tự xoá transcript (mặc định sau 30 ngày).
#   sweep.sh          bỏ qua file vừa sửa trong 30 phút (session đang chạy); hook SessionStart gọi, tối đa 1 lần/giờ
#   sweep.sh --all    xử lý tất cả (chạy tay / khi cài)
export WORKLOG_RUNNING=1
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"
[ -d "$DATA/.git" ] || exit 0

quiet=30; [ "${1:-}" = --all ] && quiet=0
if [ "$quiet" -gt 0 ]; then                       # gọi từ hook: tối đa một lần mỗi giờ
  [ -n "$(find "$STATE/sweep.last" -mmin -60 2>/dev/null)" ] && exit 0
fi
# Chỉ một sweep chạy một lúc (khoá bỏ quên quá 1 giờ thì gỡ)
SLOCK="$STATE/sweep.lock"
[ -n "$(find "$SLOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ] && rm -rf "$SLOCK"
mkdir "$SLOCK" 2>/dev/null || exit 0
touch "$STATE/sweep.last"

WORK=$(mktemp -d); CLEANUP="$WORK $SLOCK"; trap 'rm -rf $CLEANUP' EXIT
stage="$WORK/stage"; mkdir -p "$stage" "$STATE/archived"

candidates() {
  local c="$CLAUDE_DIR/projects" x="${CODEX_HOME:-$HOME/.codex}/sessions"
  [ -d "$c" ] && find "$c" -name '*.jsonl' -type f -mmin +"$quiet" | sed 's/^/claude /'
  [ -d "$x" ] && find "$x" -name '*.jsonl' -type f -mmin +"$quiet" | sed 's/^/codex /'
}

n=0
while read -r tool f; do
  b=$(basename "$f" .jsonl)
  case "$tool" in codex) sid="${b: -36}" ;; *) sid="$b" ;; esac   # rollout-<ngày>-<uuid>
  size=$(wc -c <"$f" | tr -d ' ')
  [ "$size" -ge 2000 ] || continue
  [ "$(cat "$STATE/archived/$tool-$sid" 2>/dev/null)" = "$size" ] && continue
  stage_session "$tool" "$f" "$sid" "$stage" '{"source":"sweep"}'
  case $? in
    0) n=$((n + 1)) ;;
    2) echo "$size" >"$STATE/archived/$tool-$sid" ;;            # session tóm tắt của chính worklog
  esac
done < <(candidates)
[ "$n" -gt 0 ] || exit 0

lock_data || exit 1
apply_stage "$stage"
git -C "$DATA" add -A -- meta archive \
  && git -C "$DATA" commit -qm "archive: $HOST $n session" \
  || { log "sweep: commit lỗi"; exit 1; }
mark_archived "$stage"
push_data
unlock_data
refresh_dashboard
[ -t 1 ] && echo "$(L "Đã lưu $n session vào" "Archived $n sessions into") $DATA (archive/, meta/)"
exit 0
