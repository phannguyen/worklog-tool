# worklog meta — trích số liệu của một session từ transcript gốc.
#   jq -nRc --arg tool claude|codex -f meta.jq < transcript.jsonl
# Đọc từng dòng (dòng hỏng thì bỏ qua), không nạp cả file vào bộ nhớ.
# CLI khác (gemini, copilot): trả về khung rỗng, core.sh tự điền giờ bắt đầu/kết thúc.

def ts: try ((.[0:19] + "Z") | fromdate) catch null;
def g(f): (try f catch null) // null;

# Cập nhật giờ đầu/cuối và thời gian làm thật (cộng các khoảng cách giữa hai sự kiện ≤ 15 phút).
def tick($t):
  if $t == null then . else
    .first = (.first // $t) | .last = ([.last // $t, $t] | max)
    | (if .prev != null and ($t - .prev) > 0 and ($t - .prev) <= 900 then
         .active += ($t - .prev)
         | .how[.prev | localtime | strftime("%u-%H")] += ($t - .prev)   # giờ địa phương: thứ (1=T2) - giờ
       else . end)
    | .prev = $t
  end;

def init: {first: null, last: null, prev: null, active: 0, how: {}, user: 0, tools: {}, tokens: {},
           cost: null, added: null, removed: null, cwd: null, branch: null, ver: null, entry: null,
           kind: "main", sub: null, parent: null};

# Claude Code: mỗi content block là một dòng riêng nhưng cùng chép lại `usage` của message,
# nên token phải cộng theo message.id duy nhất. `cost-state` là số cộng dồn do chính Claude Code tính.
def claude:
  reduce (inputs | fromjson? | objects) as $r (init + {seen: {}};
    if $r.type == "user" or $r.type == "assistant" then
      tick($r.timestamp | ts)
      | .cwd = (.cwd // $r.cwd) | .branch = ($r.gitBranch // .branch) | .ver = ($r.version // .ver)
      | .entry = (.entry // $r.entrypoint)
      | (if $r.isSidechain == true then .kind = "subagent" else . end)
      | if $r.type == "user" then
          if $r.isMeta != true and $r.isSidechain != true
             and (($r.message.content | type) == "string"
                  or ([$r.message.content[]?.type] | index("text") != null and index("tool_result") == null))
          then .user += 1 else . end
        else
          reduce ($r.message.content[]? | select(.type == "tool_use")) as $c (.; .tools[$c.name] += 1)
          | ($r.message.id // null) as $id | ($r.message.usage // null) as $u
          | if $id != null and $u != null and (.seen[$id] | not) and $r.message.model != "<synthetic>" then
              .seen[$id] = true
              | .tokens[$r.message.model] |= ((. // {input: 0, output: 0, thinking: 0, cache_write: 0, cache_read: 0, requests: 0})
                  | .input += ($u.input_tokens // 0)
                  | .output += ($u.output_tokens // 0)
                  | .thinking += (g($u.output_tokens_details.thinking_tokens) // 0)
                  | .cache_write += ($u.cache_creation_input_tokens // 0)
                  | .cache_read += ($u.cache_read_input_tokens // 0)
                  | .requests += 1)
            else . end
        end
    elif $r.type == "cost-state" then
      .cost = $r.totalCostUSD | .added = $r.totalLinesAdded | .removed = $r.totalLinesRemoved
    else . end)
  | del(.seen);

# Codex: token_count là số cộng dồn của cả session → lấy bản cuối. input_tokens đã gồm phần cached.
def codex:
  reduce (inputs | fromjson? | objects) as $r (init + {model: null, tu: null};
    tick($r.timestamp | ts)
    | ($r.payload // {}) as $p
    | if $r.type == "session_meta" then
        .cwd = $p.cwd | .branch = g($p.git.branch) | .ver = $p.cli_version | .entry = $p.originator
        | (g($p.source.subagent) as $s
           | if $s != null then .kind = "subagent"
               | .sub = (if ($s | type) != "object" then ($s | tostring)
                        elif ($s | keys[0]) == "other" then ($s.other | tostring)   # {"other":"guardian"}
                        else ($s | keys[0]) end)                                    # {"thread_spawn":{…}}
               | .parent = g($s.thread_spawn.parent_thread_id)
             else . end)
      elif $r.type == "turn_context" then .model = ($p.model // .model)
      elif $r.type == "event_msg" and $p.type == "user_message" then .user += 1
      # Bản mới không có user_message: đếm tin của người dùng, bỏ khối ngữ cảnh tự chèn (<environment_context>, AGENTS.md…)
      elif $r.type == "response_item" and $p.type == "message" and $p.role == "user"
           and any($p.content[]?; (.text // "") | test("^\\s*(<|# AGENTS\\.md)|^\\s*$") | not) then .user += 1
      elif $r.type == "event_msg" and $p.type == "token_count" and g($p.info.total_token_usage) != null then
        .tu = $p.info.total_token_usage
      elif $r.type == "response_item" and ($p.type == "function_call" or $p.type == "custom_tool_call") then
        .tools[$p.name // "?"] += 1
      else . end)
  | .tokens = (if .tu == null then {} else
      {(.model // "unknown"): {
        input: ((.tu.input_tokens // 0) - (.tu.cached_input_tokens // 0)),
        output: (.tu.output_tokens // 0),
        thinking: (.tu.reasoning_output_tokens // 0),
        cache_write: (.tu.cache_write_input_tokens // 0),
        cache_read: (.tu.cached_input_tokens // 0)}} end)
  | del(.tu, .model);

(if $tool == "claude" then claude elif $tool == "codex" then codex else init end)
| {
    start: (if .first == null then null else (.first | todate) end),
    end: (if .last == null then null else (.last | todate) end),
    wall_min: (if .first == null then null else (((.last - .first) / 60) | round) end),
    active_min: ((.active / 60) | round),
    # phút làm thật theo "thứ-giờ" địa phương của máy (vd. "1-09" = thứ Hai 9h), cho heatmap
    active_by_hour: (.how | map_values(. / 60 * 10 | round / 10) | with_entries(select(.value > 0))),
    user_msgs: .user,
    tool_calls: .tools,
    n_tool_calls: ([.tools[]] | add // 0),
    tokens: .tokens,
    cost_usd: .cost,
    lines_added: .added,
    lines_removed: .removed,
    cwd: .cwd,
    branch: .branch,
    client_version: .ver,
    entrypoint: .entry,
    # auto = chạy không người (claude -p / Agent SDK: "sdk-*"; codex exec), không tính là giờ làm việc
    mode: (if .entry == null then null
           elif (.entry | test("^sdk|exec"; "i")) then "auto" else "interactive" end),
    kind: .kind,
    subagent: .sub,
    parent: .parent
  }
