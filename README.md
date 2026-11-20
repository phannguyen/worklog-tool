# worklog-tool

Nhật ký làm việc tự động cho các AI coding agent: **Claude Code, Gemini CLI, Codex CLI, GitHub Copilot CLI**. Mỗi khi một session kết thúc, AI tự tóm tắt đã làm gì, quyết định gì, còn dở gì — rồi ghi vào một repo git **private** của bạn. Dùng được trên nhiều máy, vài năm sau đọc lại vẫn hiểu.

*Automatic work journal for AI coding agents (Claude Code, Gemini CLI, Codex CLI, Copilot CLI): summarizes every session into your own private git repo, across all your machines.*

## Cách hoạt động

- **Repo này (public):** chỉ có code.
- **Repo dữ liệu (private, của bạn):** các file nhật ký, mỗi tháng một file cho mỗi máy:

```
2026/11-laptop.md                          ← tóm tắt, đọc nhanh
2026/11-server-a.md
raw/2026/11/laptop-claude-<session>.md     ← toàn bộ hội thoại (đã che bí mật)
tong-ket/2026-11.md
```

```
## 2026-11-18 15:20 · laptop · codex · my-project
- Đã làm gì
- Quyết định: ... (vì sao)
- Còn dở: ...
- Transcript gốc: `raw/2026/11/laptop-codex-<session>.jsonl`
```

| CLI | Hook dùng | Ghi chú |
|---|---|---|
| Claude Code | `SessionStart`, `SessionEnd` trong `~/.claude/settings.json` | Kèm skill `worklog` |
| Gemini CLI | `SessionStart`, `SessionEnd` trong `~/.gemini/settings.json` | Thêm chỉ dẫn vào `~/.gemini/GEMINI.md` |
| Codex CLI | `SessionStart`, `SessionEnd` trong `~/.codex/hooks.json` | **Phải trust hook một lần qua `/hooks`**; thêm chỉ dẫn vào `~/.codex/AGENTS.md` |
| Copilot CLI | `sessionStart`, `agentStop`, `sessionEnd` trong `~/.copilot/hooks/worklog.json` | `sessionEnd` không có transcript nên lấy đường dẫn từ `agentStop` |

Luồng xử lý:

1. `hooks/hook.sh` nhận payload JSON của từng CLI, chuẩn hoá, rồi tách tiến trình chạy nền (CLI thoát ngay, Codex chỉ cho hook tối đa 3 giây).
2. `hooks/core.sh` gom tư liệu:
   - Claude Code: trích hội thoại (lời người dùng, trả lời của AI, lệnh tool; bỏ thinking/ảnh, cắt output tool). Session 40MB còn ~130KB.
   - CLI khác: dữ liệu thô, cắt dòng dài. Session dài giữ cả phần đầu lẫn phần cuối.
   - Không có transcript thì dùng `git log` trong thời gian session. Session được resume chỉ tóm tắt phần mới.
3. Tóm tắt bằng CLI có sẵn (`claude` → `gemini` → `codex`), chạy trong thư mục tạm, không cho dùng tool, không lưu session, có timeout 5 phút. Dữ liệu đi qua stdin (không lộ qua `ps`).
4. Lưu bản đầy đủ vào `raw/` dạng text thường (đã che bí mật phổ biến; git tự nén khi lưu). Nếu cấu hình `age` thì nén + mã hoá thành `.gz.age`. Tóm tắt lỗi thì vẫn ghi mục kèm đường dẫn raw để tóm tắt lại sau.
5. Append, commit, push dưới khoá (nhiều session cùng kết thúc không giẫm nhau); rebase hỏng thì tự abort, push lỗi thì thử lại và để lần sau đẩy tiếp.
6. Khi mở session: pull repo dữ liệu, và (mặc định) cập nhật code `worklog-tool`.

## Cài đặt

Yêu cầu: `git`, `jq`, ít nhất một CLI ở trên, SSH key với GitHub.

```bash
# 1. Tạo một repo PRIVATE trống trên GitHub, ví dụ: worklog
# 2. Trên mỗi máy:
git clone https://github.com/<owner>/worklog-tool.git ~/worklog-tool
~/worklog-tool/install.sh git@github.com:<you>/worklog.git
```

`install.sh` tự phát hiện CLI nào có trên máy và chỉ cài cho CLI đó. Cài thêm CLI mới sau này → chạy lại `~/worklog-tool/install.sh`. Chạy lại bao nhiêu lần cũng an toàn: không thêm hook trùng, giữ nguyên cấu hình khác (sao lưu ở `*.bak.worklog`).

## Tuỳ chỉnh

| Biến môi trường | Mặc định | Ý nghĩa |
|---|---|---|
| `WORKLOG_DIR` | `~/worklog` | Nơi clone repo dữ liệu |
| `WORKLOG_SUMMARIZER` | tự chọn | `claude`, `gemini` hoặc `codex` — cố định CLI dùng để tóm tắt |
| `WORKLOG_CLAUDE_MODEL` | `haiku` | Model khi tóm tắt bằng Claude |
| `WORKLOG_RAW` | `1` | `0` = không lưu transcript gốc, chỉ tóm tắt |
| `WORKLOG_RAW_MAX` | `20000000` | Bỏ qua bản raw (sau nén) lớn hơn số byte này |
| `WORKLOG_AGE_RECIPIENT` | — | (Tuỳ chọn) public key `age1...` để mã hoá file raw thành `.gz.age` — khi đó claude.ai không đọc được raw |
| `WORKLOG_AGE_RECIPIENTS_FILE` | — | Hoặc file chứa nhiều public key `age` |
| `WORKLOG_AUTO_UPDATE` | `1` | `0` = không tự `git pull` code `worklog-tool` khi mở session |

Biến môi trường phải có trong môi trường mà CLI chạy (ví dụ đặt trong `~/.bashrc` / `~/.zshrc`).

## Bảo mật

- Prompt tóm tắt yêu cầu không ghi mật khẩu, token, key — nhưng đây là tóm tắt của AI, hãy giữ repo dữ liệu ở chế độ **private**.
- Transcript được gửi cho CLI tóm tắt (tức là cho nhà cung cấp model của CLI đó).
- Thư mục `raw/` chứa gần như toàn bộ hội thoại. Bộ lọc che các dạng phổ biến (`password=…`, `sk-…`, `ghp_…`, `AKIA…`, private key…) nhưng không bắt được mọi thứ. Nếu cần, bật mã hoá: `age-keygen -o ~/.config/worklog/key.txt`, rồi `export WORKLOG_AGE_RECIPIENT=age1...` trên mọi máy; đọc lại bằng `age -d -i ~/.config/worklog/key.txt <file> | zcat`.
- `WORKLOG_AUTO_UPDATE=1` nghĩa là code mới nhất từ remote của `~/worklog-tool` được chạy tự động. Nếu clone repo của người khác, hãy fork về repo của bạn hoặc đặt `WORKLOG_AUTO_UPDATE=0`.
- Trên server dùng chung, nên dùng **deploy key** có quyền ghi chỉ cho repo dữ liệu.

## Gỡ lỗi

Lỗi của tiến trình nền ghi ở `~/.local/state/worklog/core.log`. Chạy thử tay:

```bash
~/worklog-tool/hooks/core.sh claude "$PWD" /đường/dẫn/transcript.jsonl "" <session_id>
```

## Gỡ cài đặt

Xoá các hook có chữ `worklog` trong `~/.claude/settings.json`, `~/.gemini/settings.json`, `~/.codex/hooks.json`; xoá `~/.copilot/hooks/worklog.json`, `~/.claude/skills/worklog`, và khối `<!-- worklog:start -->…<!-- worklog:end -->` trong `GEMINI.md` / `AGENTS.md`.
