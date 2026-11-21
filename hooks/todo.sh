#!/usr/bin/env bash
# worklog todo — list / close / add open items (stored in todo/<host>.jsonl in the data repo).
#   todo.sh [list] [project | --all]   list open items (default: the project of the current directory)
#   todo.sh done <id>...               mark as done
#   todo.sh add <project> <text>       add by hand
export WORKLOG_RUNNING=1
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"
[ -d "$DATA/.git" ] || { echo "$(L "Chưa có repo nhật ký" "No journal repo at") $DATA" >&2; exit 1; }

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
        [ -n "$x" ] || { echo "$(L "Không thấy việc còn mở" "No open item") #$id" >&2; continue; }
        todo_event done "$id" "$(jq -r .project <<<"$x")" "$(jq -r .text <<<"$x")" manual >>"$ev"
      done
    else
      [ $# -ge 2 ] || { echo "$(L "Cách dùng" "Usage"): $0 add <project> <text>" >&2; exit 1; }
      p="$1"; shift; t="$*"
      todo_event open "$(todo_id "$p" "$t")" "$p" "$t" manual >>"$ev"
    fi
    [ -s "$ev" ] || exit 1
    lock_data || exit 1
    mkdir -p "$DATA/todo"; cat "$ev" >>"$DATA/todo/$HOST.jsonl"
    git -C "$DATA" add todo && git -C "$DATA" commit -qm "todo: $cmd $(jq -r '.id' "$ev" | tr '\n' ' ')" || exit 1
    push_data
    jq -r --arg d "$(L "Đã đóng" "Closed")" --arg a "$(L "Đã thêm" "Added")" \
      '"\(if .op == "done" then $d else $a end) #\(.id): \(.text)"' "$ev" ;;
  *) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
