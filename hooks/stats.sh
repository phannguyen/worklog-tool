#!/usr/bin/env bash
# worklog stats — thống kê nhanh trên terminal từ meta/*.jsonl.
#   stats.sh [kỳ] [--project <tên>] [--json]
#   kỳ: 7d | 30d (mặc định) | 90d | YYYY-MM | YYYY | all
HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
. "$HERE/lib.sh"
. "$HERE/store.sh"

period=30d; project=""; json=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) project="$2"; shift ;;
    --json) json=1 ;;
    -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) period="$1" ;;
  esac
  shift
done

# Khoảng thời gian [from, to) theo UTC ISO (so sánh chuỗi với .start)
now=$(date -u +%s)
case "$period" in
  all) from="0000"; to="9999"; label=$(L "toàn bộ" "all time") ;;
  [0-9]*d) n=${period%d}; from=$(jq -nr --argjson s "$((now - n * 86400))" '$s | todate'); to="9999"
           label=$(L "$n ngày gần nhất" "last $n days") ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]) from="$period-01"; to=$(jq -nr --arg m "$period" \
           '($m + "-01T00:00:00Z" | fromdate + 32 * 86400 | todate | .[0:7]) + "-01"'); label="$period" ;;
  [0-9][0-9][0-9][0-9]) from="$period-01-01"; to="$((period + 1))-01-01"; label="$period" ;;
  *) echo "$(L "Kỳ không hợp lệ" "Invalid period"): $period" >&2; exit 1 ;;
esac

files=("$DATA"/meta/*/*.jsonl)
[ -e "${files[0]}" ] || { echo "$(L "Chưa có số liệu trong" "No data yet in") $DATA/meta" >&2; exit 1; }

data=$(cat "${files[@]}" | jq -s -f "$HERE/sessions.jq" | jq -c --arg from "$from" --arg to "$to" --arg p "$project" '
  map(select(.start >= $from and .start < $to and ($p == "" or .project == $p)))
  | (map(select(.kind == "main" and .mode != "auto"))) as $work
  | def sumn: if all(. == null) then null else map(. // 0) | add end;   # null = không có dữ liệu (vd. chi phí Codex)
    def tok: [.[].tokens | to_entries[]] | group_by(.key) | map({model: .[0].key,
        requests: (map(.value.requests) | sumn), input: (map(.value.input) | add),
        output: (map(.value.output) | add), cache_write: (map(.value.cache_write) | add),
        cache_read: (map(.value.cache_read) | add)})
      | map(. + {hit: (if (.input + .cache_write + .cache_read) > 0
                       then .cache_read / (.input + .cache_write + .cache_read) else null end)})
      | sort_by(-.output);
  {
    sessions: ($work | length),
    hours: (($work | map(.active_min) | add // 0) / 60),
    projects: ($work | map(.project) | unique | length),
    cost: (map(.cost_usd) | sumn),
    cost_auto: (map(select(.mode == "auto")) | map(.cost_usd) | sumn),
    auto_sessions: (map(select(.mode == "auto")) | length),
    by_project: ($work | group_by(.project) | map({project: .[0].project, sessions: length,
        hours: ((map(.active_min) | add) / 60), msgs: (map(.user_msgs) | add),
        tools: (map(.n_tool_calls) | add), cost: (map(.cost_usd) | sumn)}) | sort_by(-.hours)),
    by_tool: ($work | group_by(.tool) | map({tool: .[0].tool, sessions: length,
        hours: ((map(.active_min) | add) / 60)}) | sort_by(-.hours)),
    by_model: tok
  }')

todos=$(open_items "$project")
if [ "$json" = 1 ]; then
  jq -c --argjson t "$(jq -sc . <<<"$todos")" --arg label "$label" '. + {period: $label, open_items: $t}' <<<"$data"
  exit 0
fi

jq -r --arg lang "$WL_LANG" --arg label "$label" --arg proj "$project" --argjson nt "$(grep -c . <<<"$todos")" \
      --arg oldest "$(head -1 <<<"$todos" | jq -r '.at[0:10] // empty' 2>/dev/null)" '
  def T($vi; $en): if $lang == "vi" then $vi else $en end;
  def r1: . * 10 | round / 10;
  def usd: if . == null then "–" else "$" + ((. * 100 | round / 100) | tostring) end;
  def compact: if . == null then "–" elif . >= 1e9 then "\(. / 1e9 | r1)B" elif . >= 1e6 then "\(. / 1e6 | r1)M"
               elif . >= 1e3 then "\(. / 1e3 | r1)K" else tostring end;
  def pad($n): tostring | if length < $n then . + (" " * ($n - length)) else .[0:$n] end;
  def lpad($n): tostring | if length < $n then (" " * ($n - length)) + . else . end;
  "Worklog · \($label)\(if $proj != "" then " · " + $proj else "" end)",
  "",
  "\(T("Giờ làm việc"; "Working time")): \(.hours | r1) h · \(.sessions) session · \(.projects) \(T("dự án"; "projects")) · \(T("chi phí ghi nhận"; "recorded cost")): \(.cost | usd)"
    + (if .auto_sessions > 0 then " (\(T("chạy tự động"; "automated")): \(.auto_sessions) session, \(.cost_auto | usd))" else "" end),
  "",
  "\(T("Theo dự án"; "By project"))",
  "  \(T("dự án"; "project") | pad(28)) \("h" | lpad(6)) \("session" | lpad(8)) \(T("tin nhắn"; "msgs") | lpad(9)) \("tool" | lpad(6)) \(T("chi phí"; "cost") | lpad(9))",
  (.by_project[] | "  \(.project | pad(28)) \(.hours | r1 | lpad(6)) \(.sessions | lpad(8)) \(.msgs | lpad(9)) \(.tools | lpad(6)) \(.cost | usd | lpad(9))"),
  "",
  "\(T("Theo CLI"; "By CLI")): " + ([.by_tool[] | "\(.tool) \(.hours | r1) h (\(.sessions))"] | join(" · ")),
  "",
  "\(T("Token theo model"; "Tokens by model")) (\(T("cache hit = đọc cache / tổng input"; "cache hit = cache read / all input")))",
  "  \("model" | pad(28)) \(T("lượt gọi"; "requests") | lpad(9)) \("input" | lpad(8)) \("output" | lpad(8)) \("cache w" | lpad(8)) \("cache r" | lpad(8)) \("hit" | lpad(5))",
  (.by_model[] | "  \(.model | pad(28)) \(.requests | compact | lpad(9)) \(.input | compact | lpad(8)) \(.output | compact | lpad(8)) \(.cache_write | compact | lpad(8)) \(.cache_read | compact | lpad(8)) \(if .hit == null then "–" else "\(.hit * 100 | round)%" end | lpad(5))"),
  "",
  "\(T("Chi phí: chỉ Claude Code tự ghi; – là CLI không có số liệu chi phí."; "Cost: only Claude Code records it; – means the CLI provides no cost data."))",
  "\(T("Việc còn dở"; "Open items")): \($nt)\(if $oldest != "" then " (\(T("cũ nhất từ"; "oldest since")) \($oldest))" else "" end)"
' <<<"$data"
