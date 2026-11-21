# worklog-tool

[English](README.md) · **Tiếng Việt**

Nhật ký làm việc tự động cho các AI coding agent: **Claude Code, Gemini CLI, Codex CLI, GitHub Copilot CLI**. Mỗi khi một session kết thúc, AI tự tóm tắt đã làm gì, quyết định gì, còn dở gì — rồi ghi vào một repo git **private** của bạn. Dùng được trên nhiều máy, vài năm sau đọc lại vẫn hiểu.

## Cách hoạt động

- **Repo này (public):** chỉ có code.
- **Repo dữ liệu (private, của bạn):** các file nhật ký, mỗi tháng một file cho mỗi máy:

```
2026/11-laptop.md                          ← tóm tắt, đọc nhanh
2026/11-server-a.md
raw/2026/11/laptop-claude-<session>.md     ← hội thoại đã làm gọn, đọc thẳng được (đã che bí mật)
meta/2026/11-laptop.jsonl                  ← số liệu mỗi session: thời gian làm thật, token, chi phí, tool
archive/claude/2026/11/laptop-<sid>.jsonl.zst  ← transcript GỐC đầy đủ, nén (đã che bí mật, bỏ ảnh)
todo/laptop.jsonl                          ← việc còn dở (sự kiện mở / xong)
tong-ket/2026-11.md                        ← tổng kết tháng / năm (nhật ký tiếng Anh: summaries/)
```

`archive/` là nguồn gốc lâu dài: tóm tắt, số liệu, thống kê sau này đều tính lại được từ đây. Transcript gốc bỏ ảnh base64 rồi nén còn khoảng 5% (thực tế: 365MB → 18MB cho 86 session).

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
5. Lưu trữ dài hạn (`hooks/store.sh`): transcript gốc → `archive/` (che bí mật, bỏ ảnh, nén zstd hoặc gzip, mã hoá `age` nếu có cấu hình), và một dòng số liệu → `meta/` (`hooks/meta.jq`: thời gian làm thật, token theo model — Claude cộng theo `message.id` để không đếm trùng, chi phí do Claude Code tính, số lệnh tool, subagent).
6. Append, commit, push dưới khoá (nhiều session cùng kết thúc không giẫm nhau); rebase hỏng thì tự abort, push lỗi thì thử lại và để lần sau đẩy tiếp.
7. Khi mở session: pull repo dữ liệu, (mặc định) cập nhật code `worklog-tool`, và chạy `hooks/sweep.sh` (tối đa 1 lần/giờ) để lưu các transcript Claude Code / Codex còn sót — ví dụ khi cửa sổ bị đóng đột ngột nên hook kết thúc không chạy. `install.sh` chạy `sweep.sh --all` để lưu cả transcript cũ còn trên máy, và đặt `cleanupPeriodDays: 365` cho Claude Code (mặc định Claude Code xoá transcript sau 30 ngày) nếu bạn chưa tự đặt.

## Bộ nhớ dài hạn

- **Việc còn dở có id** (`todo/<máy>.jsonl`): mỗi việc dở trong bản tóm tắt thành một mục `#a1b2c3`. Lần tóm tắt sau của cùng dự án, AI nhận danh sách việc đang mở và tự đánh dấu việc đã xong. Xem/đóng/thêm tay: `hooks/todo.sh list [dự án|--all]`, `todo.sh done <id>`, `todo.sh add <dự án> "<nội dung>"`.
- **Nạp ngữ cảnh khi mở session** (hiện có cho Claude Code): hook `SessionStart` đưa vào đầu session các việc còn dở và 3 mục nhật ký gần nhất của dự án đang mở (`hooks/context.sh`, chỉ đọc file local, ~0,1 giây). Ngữ cảnh được đánh dấu là dữ liệu tham khảo, không phải chỉ dẫn. Tắt bằng `WORKLOG_CONTEXT=0`; chỉnh số lượng bằng `WORKLOG_CONTEXT_ENTRIES`, `WORKLOG_CONTEXT_TODOS`.

## Thống kê và dashboard

```bash
~/worklog-tool/hooks/stats.sh            # 30 ngày gần nhất: giờ làm theo dự án / CLI, token theo model, chi phí, việc còn dở
~/worklog-tool/hooks/stats.sh 2026-11 --project my-api
~/worklog-tool/hooks/stats.sh all --json # để tự xử lý tiếp
~/worklog-tool/hooks/dashboard.sh --open # trang HTML tự chứa, không cần mạng, ở ~/.cache/worklog/dashboard.html
```

Dashboard có: giờ làm theo dự án qua thời gian, heatmap thứ × giờ, chi phí theo thời gian (tự làm / chạy tự động), token theo model kèm cache hit, việc còn dở theo tuổi, các session gần nhất; lọc theo kỳ / dự án / CLI; giao diện sáng và tối. Trang được sinh tại máy từ `meta/` và `todo/`, không đẩy lên đâu cả. Chỉ Claude Code ghi chi phí; CLI khác hiện `–`.

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

Đặt trong file `~/.config/worklog/config` của từng máy (dạng `KEY=value`, `install.sh` tạo sẵn), hoặc bằng biến môi trường cùng tên (được ưu tiên). Nên dùng file config: CLI mở từ IDE hoặc menu thường không đọc `~/.bashrc`.

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `WORKLOG_DIR` | `~/worklog` | Nơi clone repo dữ liệu |
| `WORKLOG_LANG` | theo locale (`vi_*` → `vi`, còn lại `en`); hỏi khi cài | Ngôn ngữ viết nhật ký: `vi` hoặc `en` |
| `WORKLOG_HOST` | `hostname -s` | Tên máy trong tên file và tiêu đề — đặt khi nhiều máy trùng hostname (`ubuntu`, `localhost`…) |
| `WORKLOG_CONTEXT` | `1` | `0` = không nạp ngữ cảnh worklog khi mở session |
| `WORKLOG_CONTEXT_ENTRIES` / `WORKLOG_CONTEXT_TODOS` | `3` / `15` | Số mục nhật ký / việc còn dở được nạp |
| `WORKLOG_AUTO_SUMMARY` | `0` | `1` = vẫn tóm tắt session chạy tự động (`claude -p`, Agent SDK, `codex exec`) vào nhật ký |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `COPILOT_HOME` | `~/.claude`, `~/.codex`, `~/.copilot` | Thư mục cấu hình của từng CLI, nếu bạn đặt khác mặc định |
| `WORKLOG_SUMMARIZER` | tự chọn | `claude`, `gemini` hoặc `codex` — cố định CLI dùng để tóm tắt |
| `WORKLOG_CLAUDE_MODEL` | `haiku` | Model khi tóm tắt bằng Claude |
| `WORKLOG_RAW` | `1` | `0` = không lưu transcript (`raw/`, `archive/`), chỉ tóm tắt + số liệu `meta/` |
| `WORKLOG_RAW_MAX` | `20000000` | Bỏ qua file raw/archive (sau nén) lớn hơn số byte này |
| `WORKLOG_AGE_RECIPIENT` | — | (Tuỳ chọn) public key `age1...` để mã hoá file raw thành `.gz.age` — khi đó claude.ai không đọc được raw |
| `WORKLOG_AGE_RECIPIENTS_FILE` | — | Hoặc file chứa nhiều public key `age` |
| `WORKLOG_GIT_EMAIL` | hỏi khi cài | Email commit cho repo nhật ký (đặt riêng, không ảnh hưởng git global) |
| `WORKLOG_AUTO_UPDATE` | `1` | `0` = không tự `git pull` code `worklog-tool` khi mở session |

**Tên dự án** mặc định là tên thư mục gốc của repo git (các worktree tính chung với repo chính), ngoài git thì là tên thư mục. Hai repo trùng tên thư mục, hoặc muốn đặt tên khác: `git config worklog.project <tên>` trong repo đó.

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
~/worklog-tool/hooks/sweep.sh --all          # lưu trữ mọi transcript chưa lưu trên máy
~/worklog-tool/hooks/context.sh "$PWD"       # xem ngữ cảnh mà session mới ở đây sẽ nhận
jq -nRc --arg tool claude -f ~/worklog-tool/hooks/meta.jq < transcript.jsonl   # xem số liệu một session
```

## Gỡ cài đặt

Xoá các hook có chữ `worklog` trong `~/.claude/settings.json`, `~/.gemini/settings.json`, `~/.codex/hooks.json`; xoá `~/.copilot/hooks/worklog.json`, `~/.claude/skills/worklog`, `~/.config/worklog/`, và khối `<!-- worklog:start -->…<!-- worklog:end -->` trong `GEMINI.md` / `AGENTS.md`.
