# worklog sessions — gộp các dòng meta thành một bản ghi cho mỗi session.
#   cat meta/*/*.jsonl | jq -s -f sessions.jq
# Một session có thể có nhiều dòng (resume, sweep): gộp theo (tool, sid), dòng sau đè dòng trước.
# Giờ làm việc thật: kind == "main" và mode != "auto". Token / chi phí: tính mọi session.

group_by(.tool + ":" + .sid)
| map(reduce .[] as $x ({}; . + $x))
| map(select(.start != null))
| map({
    tool, host, project, sid, start, end, branch,
    active_min: (.active_min // 0),
    wall_min,
    user_msgs: (.user_msgs // 0),
    n_tool_calls: (.n_tool_calls // 0),
    tool_calls: (.tool_calls // {}),
    tokens: (.tokens // {}),
    cost_usd,
    lines_added, lines_removed,
    mode: (.mode // "interactive"),
    kind: (.kind // "main"),
    how: (.active_by_hour // {}),
    entry: (.entry.file // null)
  })
| sort_by(.start)
