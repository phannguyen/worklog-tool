#!/usr/bin/env bash
# worklog dashboard — sinh một trang HTML tự chứa (không cần mạng) từ meta/ và todo/.
#   dashboard.sh [--open] [-o <file>]
# Mặc định ghi ra ~/.cache/worklog/dashboard.html (ngoài repo, không đẩy đi đâu).
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"

out="${XDG_CACHE_HOME:-$HOME/.cache}/worklog/dashboard.html"; open=0
while [ $# -gt 0 ]; do
  case "$1" in
    --open) open=1 ;;
    -o) out="$2"; shift ;;
    -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$(L "Không hiểu tuỳ chọn" "Unknown option"): $1" >&2; exit 1 ;;
  esac
  shift
done

files=("$DATA"/meta/*/*.jsonl)
[ -e "${files[0]}" ] || { echo "$(L "Chưa có số liệu trong" "No data yet in") $DATA/meta" >&2; exit 1; }
WORK=$(mktemp -d); CLEANUP="$WORK"; trap 'rm -rf $CLEANUP' EXIT

cat "${files[@]}" | jq -s -f "$HERE/sessions.jq" >"$WORK/sessions.json" || exit 1
open_items "" | jq -s . >"$WORK/todos.json"
# "</" → "<\/" để dữ liệu không thể đóng thẻ <script> (JSON vẫn đọc ra đúng chuỗi)
jq -nc --slurpfile s "$WORK/sessions.json" --slurpfile t "$WORK/todos.json" --arg lang "$WL_LANG" \
  '{lang: $lang, generated: (now | floor | todate), hosts: ($s[0] | map(.host) | unique),
    sessions: $s[0], todos: $t[0]}' | sed 's#</#<\\/#g' >"$WORK/data.json"

mkdir -p "$(dirname "$out")"
DF="$WORK/data.json" perl -pe 'BEGIN { local $/; open(my $f, "<", $ENV{DF}) or die; $d = <$f>; chomp $d }
                               s/__WORKLOG_DATA__/$d/' "$HERE/dashboard.html" >"$out.tmp" && mv "$out.tmp" "$out"
echo "$out"

if [ "$open" = 1 ]; then
  if command -v xdg-open >/dev/null; then xdg-open "$out" >/dev/null 2>&1 &
  elif command -v open >/dev/null; then open "$out"
  fi
fi
