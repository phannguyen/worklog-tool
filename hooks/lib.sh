#!/usr/bin/env bash
# worklog — hàm dùng chung cho hook.sh và core.sh (được source, không chạy trực tiếp).

# Cấu hình: biến môi trường > file config > mặc định.
# File config (KEY=value, dòng # là chú thích) cần thiết vì CLI mở từ menu/IDE thường không đọc ~/.bashrc.
WORKLOG_CONFIG="${WORKLOG_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/worklog/config}"
if [ -f "$WORKLOG_CONFIG" ]; then
  while IFS='=' read -r _k _v; do
    case "$_k" in WORKLOG_*|CLAUDE_CONFIG_DIR|CODEX_HOME|COPILOT_HOME) ;; *) continue ;; esac
    [ -n "${!_k+x}" ] && continue                       # biến môi trường được ưu tiên
    _v="${_v%\"}"; _v="${_v#\"}"; _v="${_v/#\~/$HOME}"
    export "$_k=$_v"
  done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$WORKLOG_CONFIG")
  unset _k _v
fi

DATA="${WORKLOG_DIR:-$HOME/worklog}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/worklog"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mkdir -p "$STATE"

# Tên máy trong tên file và tiêu đề. Đặt WORKLOG_HOST khi nhiều máy trùng hostname (vd. "ubuntu", "localhost").
HOST="${WORKLOG_HOST:-$(hostname -s 2>/dev/null || hostname)}"
HOST=$(printf '%s' "$HOST" | tr -c 'A-Za-z0-9._-' '-')

# Ngôn ngữ viết nhật ký: vi | en. Mặc định theo locale (vi_* → vi, còn lại → en).
case "${WORKLOG_LANG:-}" in
  vi|en) WL_LANG="$WORKLOG_LANG" ;;
  *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in vi*) WL_LANG=vi ;; *) WL_LANG=en ;; esac ;;
esac

# Thông báo cho người dùng theo ngôn ngữ:  L "<tiếng Việt>" "<English>"
L() { if [ "$WL_LANG" = vi ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# Chuỗi ghi vào nhật ký theo ngôn ngữ.
msg() {
  case "$WL_LANG:$1" in
    vi:none)  echo "(không có việc đáng kể)" ;;
    en:none)  echo "(nothing significant)" ;;
    vi:fail)  echo "(CHƯA TÓM TẮT ĐƯỢC — xem transcript gốc bên dưới hoặc core.log)" ;;
    en:fail)  echo "(NOT SUMMARIZED YET — see the raw transcript below or core.log)" ;;
    vi:raw)   echo "Transcript gốc" ;;
    en:raw)   echo "Raw transcript" ;;
    vi:cont)  echo "(Đây là phần tiếp theo của một session đã được ghi trước đó.)" ;;
    en:cont)  echo "(This continues a session that was logged before.)" ;;
    vi:gitlog) echo "(Không có transcript — đây là các commit trong lúc session diễn ra)" ;;
    en:gitlog) echo "(No transcript — these are the commits made during the session)" ;;
    vi:todo)  echo "Còn dở" ;;
    en:todo)  echo "TODO" ;;
    vi:done)  echo "Đã xong việc trước đó" ;;
    en:done)  echo "Done (earlier item)" ;;
    vi:open_head) echo "----- VIỆC CÒN DỞ TỪ TRƯỚC CỦA DỰ ÁN (id: nội dung) -----" ;;
    en:open_head) echo "----- PREVIOUSLY OPEN ITEMS OF THIS PROJECT (id: text) -----" ;;
    vi:open_end)  echo "----- HẾT DANH SÁCH. DƯỚI ĐÂY LÀ SESSION -----" ;;
    en:open_end)  echo "----- END OF LIST. THE SESSION FOLLOWS -----" ;;
  esac
}

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
