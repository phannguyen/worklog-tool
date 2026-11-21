#!/usr/bin/env bash
# worklog todo — xem / đóng / thêm việc còn dở (lưu ở todo/<máy>.jsonl trong repo nhật ký).
#   todo.sh [list] [dự án | --all]    liệt kê việc còn mở (mặc định: dự án của thư mục hiện tại)
#   todo.sh done <id>...              đánh dấu xong
#   todo.sh add <dự án> <nội dung>    thêm tay
export WORKLOG_RUNNING=1
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"
[ -d "$DATA/.git" ] || { echo "Chưa có repo nhật ký $DATA" >&2; exit 1; }

cmd="${1:-list}"; [ $# -gt 0 ] && shift
case "$cmd" in
  list)
    p="${1:-$(project_of "$PWD")}"; [ "$p" = --all ] && p=""
    open_items "$p" | jq -r '"#\(.id)  \(.at[0:10])  \(.project)  \(.text)"' ;;
  done|add)
    ev=$(mktemp); CLEANUP="$ev"; trap 'rm -rf $CLEANUP' EXIT
    if [ "$cmd" = done ]; then
      all=$(open_items "")
      for id in "$@"; do
        id="${id#\#}"
        x=$(jq -c --arg i "$id" 'select(.id == $i)' <<<"$all" | head -1)
        [ -n "$x" ] || { echo "Không thấy việc còn mở #$id" >&2; continue; }
        todo_event done "$id" "$(jq -r .project <<<"$x")" "$(jq -r .text <<<"$x")" manual >>"$ev"
      done
    else
      [ $# -ge 2 ] || { echo "Cách dùng: $0 add <dự án> <nội dung>" >&2; exit 1; }
      p="$1"; shift; t="$*"
      todo_event open "$(todo_id "$p" "$t")" "$p" "$t" manual >>"$ev"
    fi
    [ -s "$ev" ] || exit 1
    lock_data || exit 1
    mkdir -p "$DATA/todo"; cat "$ev" >>"$DATA/todo/$HOST.jsonl"
    git -C "$DATA" add todo && git -C "$DATA" commit -qm "todo: $cmd $(jq -r '.id' "$ev" | tr '\n' ' ')" || exit 1
    push_data
    jq -r '"\(if .op == "done" then "Đã đóng" else "Đã thêm" end) #\(.id): \(.text)"' "$ev" ;;
  *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
