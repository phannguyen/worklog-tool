#!/usr/bin/env bash
# worklog — hàm dùng chung cho hook.sh và core.sh (được source, không chạy trực tiếp).

DATA="${WORKLOG_DIR:-$HOME/worklog}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/worklog"
mkdir -p "$STATE"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$$" "$*" >> "$STATE/core.log"; }

# Khoá repo dữ liệu giữa các tiến trình worklog trên cùng máy (mkdir là atomic, chạy cả trên macOS).
LOCK="$STATE/data.lock"
lock_data() {
  local n=0
  until mkdir "$LOCK" 2>/dev/null; do
    # khoá bỏ quên quá 10 phút (tiến trình bị kill) thì gỡ
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] && { rm -rf "$LOCK"; continue; }
    n=$((n + 1)); [ "$n" -ge 180 ] && { log "không lấy được khoá $LOCK"; return 1; }
    sleep 1
  done
  trap 'rm -rf "$LOCK" $CLEANUP' EXIT
}
unlock_data() { rm -rf "$LOCK"; trap 'rm -rf $CLEANUP' EXIT; }
CLEANUP=""   # các đường dẫn tạm (không chứa dấu cách) cần xoá khi thoát

# Kéo bản mới; nếu rebase hỏng thì huỷ để repo không kẹt ở trạng thái rebase dở.
pull_data() {
  git -C "$DATA" pull -q --rebase --autostash && return 0
  git -C "$DATA" rebase --abort >/dev/null 2>&1
  log "pull --rebase thất bại trong $DATA (đã abort)"
  return 1
}

push_data() {
  local i
  for i in 1 2 3; do   # vài máy cùng push một lúc thì thử lại
    pull_data && git -C "$DATA" push -q && return 0
    sleep $((i * 5))
  done
  log "push thất bại sau 3 lần — commit vẫn nằm local, lần sau sẽ đẩy tiếp"
  return 1
}

# Chạy lệnh với giới hạn thời gian nếu máy có `timeout` (macOS mặc định không có).
with_timeout() {
  local t="$1"; shift
  if command -v timeout >/dev/null; then timeout "$t" "$@"
  elif command -v gtimeout >/dev/null; then gtimeout "$t" "$@"
  else "$@"; fi
}
