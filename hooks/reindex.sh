#!/usr/bin/env bash
# worklog reindex — tính lại số liệu trong meta/ từ transcript gốc trong archive/.
# Dùng khi meta.jq có trường mới hoặc sửa cách tính: mọi số liệu đều phái sinh từ archive/.
#   reindex.sh [--dry-run]
# Giữ nguyên các trường không do meta.jq tính (project, entry, summary, source…). Bỏ qua file .age
# (cần key để giải mã) và archive của máy khác vẫn được tính, vì archive nằm chung trong repo.
export WORKLOG_RUNNING=1
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"
[ -d "$DATA/.git" ] || exit 1
dry=0; [ "${1:-}" = --dry-run ] && dry=1

WORK=$(mktemp -d); CLEANUP="$WORK"; trap 'rm -rf $CLEANUP' EXIT
lock_data || exit 1
pull_data

# archive path → số liệu tính lại
cat "$DATA"/meta/*/*.jsonl 2>/dev/null | jq -r '[.tool, .archive // empty] | select(length == 2) | @tsv' | sort -u |
while IFS=$'\t' read -r tool rel; do
  f="$DATA/$rel"; [ -f "$f" ] || continue
  case "$f" in
    *.zst) dec=(zstd -dc) ;;
    *.gz)  dec=(gzip -dc) ;;
    *) continue ;;                                   # .age hoặc không nén: bỏ qua
  esac
  "${dec[@]}" "$f" | jq -nRc --arg tool "$tool" -f "$HERE/meta.jq" | jq -c --arg k "$rel" '{($k): .}'
done | jq -sc 'add // {}' >"$WORK/map.json"
n=$(jq 'length' "$WORK/map.json")

for m in "$DATA"/meta/*/*.jsonl; do
  jq -c --slurpfile M "$WORK/map.json" '. + ($M[0][.archive // ""] // {})' "$m" >"$WORK/new" || exit 1
  [ "$dry" = 1 ] || cat "$WORK/new" >"$m"
done
if [ "$dry" = 1 ]; then echo "$(L "Sẽ tính lại" "Would recompute") $n session"; exit 0; fi
if git -C "$DATA" diff --quiet -- meta; then echo "$(L "Không có gì thay đổi" "Nothing changed")"; exit 0; fi
git -C "$DATA" add meta && git -C "$DATA" commit -qm "meta: reindex $n session ($HOST)" || exit 1
push_data
unlock_data
refresh_dashboard
echo "$(L "Đã tính lại" "Recomputed") $n session"
