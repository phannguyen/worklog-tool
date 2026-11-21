#!/usr/bin/env bash
# worklog store — lưu trữ dài hạn (được source sau lib.sh, không chạy trực tiếp).
#   archive/<tool>/YYYY/MM/<máy>-<session>.<ext>.zst  transcript gốc: che bí mật, bỏ ảnh base64, nén
#   meta/YYYY/MM-<máy>.jsonl                          mỗi lần lưu một dòng số liệu (xem hooks/meta.jq)
# Một session có thể có nhiều dòng meta (session được resume): dòng sau ghi đè dòng trước theo (tool, sid).
# Thư mục tháng lấy theo giờ BẮT ĐẦU session, nên một session luôn nằm cùng chỗ.

STORE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Che bí mật phổ biến + bỏ dữ liệu nhị phân base64 (best-effort, không thay được việc giữ repo private).
sanitize() {
  perl -pe '
    s/("data"\s*:\s*\\?")[A-Za-z0-9+\/=]{1000,}/$1\[đã bỏ dữ liệu nhị phân]/g;
    s/"(?:data:[a-zA-Z\/+.-]+;base64,)?[A-Za-z0-9+\/=]{2000,}"/"[đã bỏ dữ liệu nhị phân]"/g;
    s/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/[ĐÃ CHE: private key]/g;
    s/\b(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})/[ĐÃ CHE]/g;
    # key=giá trị. Giữ nguyên số của khoá JSON (vd. "input_tokens":14041) và không chạm mảng/object,
    # để transcript .jsonl vẫn hợp lệ; "pwd=12345678" dạng text vẫn bị che.
    s{((?:password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[A-Za-z_]*)((?:\\?")?\s*[:=]\s*)((?:\\?")?)([^\s"\\,;{}\[\]]{6,})}
     { my ($k, $s, $q, $v) = ($1, $2, $3, $4);
       ($s =~ /"\s*:\s*$/ && $q eq "" && $v =~ /^[0-9.]+$/) ? "$k$s$q$v" : "$k$s$q\[ĐÃ CHE]" }gie;
  '
}

# Số dòng JSON đọc được (để kiểm tra sanitize không làm hỏng transcript .jsonl)
json_lines() { jq -nR '[inputs | fromjson? | 1] | length' 2>/dev/null; }

# Tên dự án: `git config worklog.project <tên>` (đặt riêng từng repo, vd. khi hai repo trùng tên thư mục)
# > tên thư mục gốc của repo (worktree tính theo repo chính) > tên thư mục.
project_of() {
  local d="$1" p top common
  if top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null); then
    p=$(git -C "$d" config --get worklog.project 2>/dev/null)
    [ -n "$p" ] && { echo "$p"; return; }
    common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    case "$common" in */.git) top="${common%/.git}" ;; esac
    basename "$top"
  else
    basename "$d"
  fi
}

# Nén (zstd, không có thì gzip) rồi mã hoá bằng age nếu đã cấu hình.
#   seal_ext → đuôi file; seal < in > out
seal_ext() {
  local e; command -v zstd >/dev/null && e=zst || e=gz
  [ -n "${WORKLOG_AGE_RECIPIENT:-}${WORKLOG_AGE_RECIPIENTS_FILE:-}" ] && e="$e.age"
  echo "$e"
}
seal() {
  local c=(gzip -9c); command -v zstd >/dev/null && c=(zstd -q -19 -T0 -c)
  if [ -n "${WORKLOG_AGE_RECIPIENT:-}${WORKLOG_AGE_RECIPIENTS_FILE:-}" ]; then
    command -v age >/dev/null || { log "đã cấu hình mã hoá nhưng thiếu 'age'"; return 1; }
    if [ -n "${WORKLOG_AGE_RECIPIENTS_FILE:-}" ]; then "${c[@]}" | age -R "$WORKLOG_AGE_RECIPIENTS_FILE"
    else "${c[@]}" | age -r "$WORKLOG_AGE_RECIPIENT"; fi
  else "${c[@]}"; fi
}

# Chuẩn bị lưu một session vào thư mục stage (chưa đụng tới repo, không cần khoá).
#   stage_session <tool> <transcript|""> <sid> <stage> [extra_json] [start_epoch] [cwd]
# extra_json được gộp đè lên meta (vd. trạng thái tóm tắt, đường dẫn mục nhật ký).
# Trả về 2 nếu bỏ qua (session của chính worklog chạy trong thư mục tạm).
stage_session() {
  local tool="$1" src="$2" sid="$3" stage="$4" extra="${5:-}" hstart="${6:-}" hcwd="${7:-}"
  local host m cwd month project rel="" bytes=0 ext
  host="$HOST"; [ -n "$extra" ] || extra='{}'
  m='{}'
  if [ -n "$src" ] && [ -f "$src" ]; then
    m=$(jq -nRc --arg tool "$tool" -f "$STORE_HERE/meta.jq" <"$src" 2>/dev/null)
    [ -n "$m" ] || m='{}'
    bytes=$(wc -c <"$src" | tr -d ' ')
  fi
  m=$(jq -c --arg hs "$hstart" --arg hcwd "$hcwd" '
      .start //= (if $hs == "" then null else ($hs | tonumber | todate) end)
    | .end   //= (if $hs == "" then null else (now | floor | todate) end)
    | .cwd = (if $hcwd == "" then .cwd else $hcwd end)' <<<"$m") || return 1   # khớp với tiêu đề nhật ký
  cwd=$(jq -r '.cwd // empty' <<<"$m")
  case "$cwd" in */worklog-sum.*|/tmp/tmp.*) return 2 ;; esac        # session tóm tắt của chính worklog
  project=$(project_of "${cwd:-unknown}")
  month=$(jq -r '.start | fromdate | strflocaltime("%Y/%m")' <<<"$m" 2>/dev/null) || month=""
  [ -n "$month" ] || month=$(date +%Y/%m)

  if [ "$bytes" -gt 0 ] && [ "${WORKLOG_RAW:-1}" = 1 ]; then    # WORKLOG_RAW=0: chỉ giữ meta
    ext="${src##*.}"; [ "$ext" = "$src" ] && ext=txt
    rel="archive/$tool/$month/$host-$sid.$ext.$(seal_ext)"
    mkdir -p "$stage/$(dirname "$rel")"
    sanitize <"$src" >"$stage/.clean"
    if [ "$ext" = jsonl ] && [ "$(json_lines <"$stage/.clean")" != "$(json_lines <"$src")" ]; then
      log "cảnh báo: sau khi che bí mật có dòng JSON bị hỏng: $src"   # vẫn lưu, nhưng cần sửa sanitize
    fi
    if ! seal <"$stage/.clean" >"$stage/$rel"; then
      log "lưu archive lỗi: $src"; rm -f "$stage/$rel"; rel=""
    elif [ "$(wc -c <"$stage/$rel")" -gt "${WORKLOG_RAW_MAX:-20000000}" ]; then
      log "archive quá lớn ($(wc -c <"$stage/$rel") byte) — chỉ giữ meta: $src"; rm -f "$stage/$rel"; rel=""
    fi
    rm -f "$stage/.clean"
  fi

  mkdir -p "$stage/.meta/$(dirname "$month")"
  jq -c --arg tool "$tool" --arg host "$host" --arg project "$project" --arg sid "$sid" \
        --arg tz "$(date +%z)" --arg archive "$rel" --argjson bytes "$bytes" --argjson extra "$extra" '
      {v: 1, tool: $tool, host: $host, project: $project, sid: $sid} + .
    + {tz: $tz, transcript_bytes: $bytes, archive: (if $archive == "" then null else $archive end),
       logged: (now | floor | todate)} + $extra' <<<"$m" >>"$stage/.meta/$month-$host.jsonl" || return 1
  echo "$tool-$sid $bytes" >>"$stage/.state"
}

# Đưa stage vào repo dữ liệu (gọi khi đang giữ khoá): archive thì ghi đè, meta thì nối thêm.
apply_stage() {
  local stage="$1" f
  [ -d "$stage" ] || return 0
  ( cd "$stage" && find . -type f -not -path './.meta/*' -not -name .state -not -name .clean ) | while IFS= read -r f; do
    mkdir -p "$DATA/$(dirname "$f")"; mv -f "$stage/$f" "$DATA/$f"
  done
  [ -d "$stage/.meta" ] && ( cd "$stage/.meta" && find . -type f ) | while IFS= read -r f; do
    mkdir -p "$DATA/meta/$(dirname "$f")"; cat "$stage/.meta/$f" >>"$DATA/meta/$f"
  done
  return 0
}

# Sau khi commit: ghi nhớ kích thước đã lưu để sweep không lưu lại file chưa đổi.
mark_archived() {
  local stage="$1" k s
  mkdir -p "$STATE/archived"
  [ -f "$stage/.state" ] && while read -r k s; do echo "$s" >"$STATE/archived/$k"; done <"$stage/.state"
  return 0
}

# ---------- Việc còn dở ----------
# todo/<máy>.jsonl, chỉ nối thêm (mỗi máy một file → nhiều máy không xung đột khi merge):
#   {at, op: "open"|"done", id, project, text, host, sid}
# id = 6 ký tự đầu sha1(dự án + nội dung): cùng một việc ghi lại nhiều lần vẫn là một việc.
todo_id() { printf '%s\n%s' "$1" "$2" | { sha1sum 2>/dev/null || shasum; } | cut -c1-6; }

# live_items <thư mục> <op mở> <op đóng> [dự án] → mỗi dòng một mục còn hiệu lực {id, text, at, project}, cũ trước.
live_items() {
  cat "$DATA/$1"/*.jsonl 2>/dev/null | jq -c -s --arg on "$2" --arg off "$3" --arg p "${4:-}" '
    (map(select(.op == $off) | .id)) as $closed
    | map(select(.op == $on and ($p == "" or .project == $p) and ((.id | IN($closed[])) | not)))
    | unique_by(.id) | sort_by(.at) | .[]'
}
# open_items [dự án] → việc còn mở. Rỗng = mọi dự án.
open_items() { live_items todo open done "${1:-}"; }

# ---------- Điều cần nhớ (bộ nhớ tri thức theo dự án) ----------
# kb/<máy>.jsonl, chỉ nối thêm: {at, op: "add"|"drop", id, project, text, host, sid} — cùng cách với todo/.
# Sự thật bền vững: cấu hình/hạ tầng, quy ước, cạm bẫy và cách tránh, lý do của quyết định quan trọng.
kb_items() { live_items kb add drop "${1:-}"; }

# journal_entries <dự án> <số mục> [độ dài tối đa mỗi mục] → các mục nhật ký gần nhất của dự án (mọi máy), cũ trước.
journal_entries() {
  local files=() f
  while IFS= read -r f; do files+=("$f"); done < <(ls "$DATA"/20[0-9][0-9]/[01][0-9]-*.md 2>/dev/null | tail -n 36)
  [ ${#files[@]} -gt 0 ] || return 0
  perl -CSDA -Mutf8 -e '
    my ($p, $n, $max) = (shift, shift, shift); my @e;
    for my $f (@ARGV) {
      open(my $h, "<", $f) or next; local $/; my $s = <$h>;
      for my $b (split /^(?=## )/m, $s) {
        next unless $b =~ /\A## ([^\n]+?) · [^·\n]+ · [^·\n]+ · ([^\n]+?)\s*$/m;
        push @e, [$1, $b] if $2 eq $p;
      }
    }
    @e = sort { $a->[0] cmp $b->[0] } @e;
    splice(@e, 0, -$n) if @e > $n;
    for (@e) { my $b = $_->[1]; $b =~ s/\s+\z//; $b = substr($b, 0, $max) . " …" if length $b > $max; print "$b\n\n"; }
  ' "$1" "$2" "${3:-1500}" "${files[@]}"
}

# run_summarizer <chỉ dẫn> <file tư liệu> <thư mục tạm> → câu trả lời của AI ở stdout.
# CLI có sẵn (claude → gemini → codex, hoặc WORKLOG_SUMMARIZER), chạy trong thư mục tạm, không tool, không lưu session.
run_summarizer() {
  local instr="$1" mat="$2" dir="$3" s="${WORKLOG_SUMMARIZER:-}" c
  if [ -z "$s" ]; then
    for c in claude gemini codex; do command -v "$c" >/dev/null && { s=$c; break; }; done
  fi
  ( cd "$dir" || exit 1
    case "$s" in
      claude) with_timeout 300 claude -p --model "${WORKLOG_CLAUDE_MODEL:-haiku}" \
                --tools "" --no-session-persistence --strict-mcp-config --setting-sources user \
                "$instr" <"$mat" ;;
      gemini) with_timeout 300 gemini -p "$instr" <"$mat" ;;
      codex)  { printf '%s\n\n----- DATA -----\n' "$instr"; cat "$mat"; } \
                | with_timeout 300 codex exec --skip-git-repo-check --sandbox read-only \
                    --output-last-message "$dir/out" - >/dev/null \
                && cat "$dir/out" ;;
      *) exit 127 ;;
    esac )
}

# todo_event <op> <id> <dự án> <nội dung> <sid> [at] → một dòng JSON
todo_event() {
  jq -nc --arg op "$1" --arg id "$2" --arg p "$3" --arg t "$4" --arg sid "$5" --arg at "${6:-}" \
         --arg h "$HOST" \
    '{at: (if $at == "" then (now | floor | todate) else $at end), op: $op, id: $id,
      project: $p, text: $t, host: $h, sid: $sid}'
}

# Dashboard tự cập nhật sau khi có số liệu mới — chỉ khi người dùng đã từng tạo nó ở vị trí mặc định.
refresh_dashboard() {
  [ -f "${XDG_CACHE_HOME:-$HOME/.cache}/worklog/dashboard.html" ] || return 0
  "$STORE_HERE/dashboard.sh" >/dev/null 2>>"$STATE/core.log" || log "tạo lại dashboard lỗi"
}
