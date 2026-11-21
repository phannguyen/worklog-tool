---
name: worklog
description: Nhật ký làm việc tự động từ Claude Code, Gemini CLI, Codex CLI, Copilot CLI (repo dữ liệu ~/worklog). Dùng khi người dùng hỏi "đã làm gì", xin tổng kết tuần/tháng/năm/dự án, nói "ghi nhật ký", hoặc muốn cài worklog trên máy mới.
---

# Worklog — nhật ký làm việc

- **Code** (public): `~/worklog-tool` — hook cho Claude Code, Gemini CLI, Codex CLI, Copilot CLI; `install.sh`; skill này.
- **Dữ liệu** (private): `~/worklog` — các file nhật ký.
- Đây là đường dẫn mặc định. Máy có thể đặt khác trong `~/.config/worklog/config` (`WORKLOG_DIR`, `WORKLOG_HOST`, `WORKLOG_LANG`…) — đọc file đó trước khi giả định; code nằm ở thư mục cha của skill này (`readlink -f` thư mục skill). Nhật ký viết theo `WORKLOG_LANG` (vi | en); dòng việc dở là `Còn dở [#id]` hoặc `TODO [#id]`.

```
2026/11-laptop.md      ← mỗi tháng một file, mỗi máy một file
2026/11-web.md         ← mục ghi từ chat claude.ai
raw/2026/11/*          ← hội thoại đã làm gọn, đọc thẳng được (text; đuôi .gz.age là đã mã hoá)
meta/2026/11-laptop.jsonl            ← số liệu mỗi session (thời gian, token, chi phí, tool…)
archive/<cli>/2026/11/<máy>-<sid>.*  ← transcript GỐC đầy đủ, nén zstd/gzip (che bí mật, bỏ ảnh)
tong-ket/2026-11.md    ← tổng kết tháng / năm
```
Đây là kho dữ liệu dài hạn của người dùng: dùng để xem lại, thống kê, và làm bộ nhớ dài hạn. Mọi thứ phái sinh (tóm tắt, meta) đều tính lại được từ `archive/`.

Định dạng một mục:
```
## 2026-11-18 15:20 · laptop · claude · my-project
- Đã làm gì (cụ thể)
- Quyết định: ... (vì sao)
- Còn dở: ...
- Transcript gốc: `raw/2026/11/laptop-claude-<session>.md`
```

**Không bao giờ** ghi mật khẩu, token, API key, private key vào nhật ký.

Đang ở đâu:
- **CLI trên máy local** (Claude Code, Gemini, Codex, Copilot) → dùng shell trực tiếp trên `~/worklog`.
- **Chat claude.ai** → gắn repo dữ liệu bằng `add_repo` (tìm bằng `list_repos` query "worklog" nếu chưa biết tên; đừng nhầm với `worklog-tool`), clone rồi đọc/ghi.

## 1. Cài trên máy mới

- Chưa có `~/worklog-tool`: hỏi URL repo code, `git clone <url> ~/worklog-tool`.
- Chưa có `~/worklog`: hỏi URL repo dữ liệu private, chạy `~/worklog-tool/install.sh <url-repo-dữ-liệu>`; nếu đã có thì chạy `~/worklog-tool/install.sh`.
- Báo kết quả. Lỗi push → hướng dẫn kiểm tra `ssh -T git@github.com` hoặc thêm deploy key.

## 2. Ghi tay một mục

Khi người dùng nói "ghi nhật ký", hoặc vừa xong một việc đáng kể trong chat claude.ai.
- Tóm tắt cuộc trò chuyện hiện tại theo định dạng trên.
- Tiêu đề: `## YYYY-MM-DD HH:MM · <máy> · <công cụ> · <dự án>` (công cụ: claude, gemini, codex, copilot, web).
- File: CLI local → `YYYY/MM-$(hostname -s).md`; claude.ai → `YYYY/MM-web.md` (`add_repo` với `access: "push"`).
- Append, commit, `git pull --rebase`, push. Báo lại một dòng.

## 3. Hỏi "đã làm gì" / tổng kết

1. Lấy bản mới nhất (`git -C ~/worklog pull -q`, hoặc clone trên claude.ai).
2. Chỉ đọc file trong khoảng thời gian liên quan; lọc dự án bằng `grep -rni "<từ khóa>" ~/worklog/20*`.
3. Dòng tiêu đề mỗi mục có dạng `ngày · máy · công cụ · dự án` — lọc theo công cụ được (vd. `grep -rn '· codex ·'`). Trả lời nhóm theo dự án, có ngày; tách **đã xong** / **quyết định** / **còn dở**. Không bịa việc không có trong nhật ký; khoảng thời gian trống thì nói thẳng.
4. Cần chi tiết hơn tóm tắt (lệnh cụ thể, cấu hình, lỗi gặp phải): mở file raw ghi trong mục — `grep -n "<từ khoá>" <file>` (đọc thẳng được, kể cả trên claude.ai); file `.gz.age` là đã mã hoá: `age -d -i ~/.config/worklog/key.txt <file> | zcat`, chỉ làm được trên máy có key. Chỉ đọc đoạn liên quan, file có thể lớn.
5. Tổng kết tháng/năm: thêm thành quả chính, bài học, việc bỏ dở lâu. Đề nghị lưu vào `tong-ket/<kỳ>.md` rồi commit, push.

## 4. Thống kê (thời gian, token, chi phí)

Mỗi dòng trong `meta/*.jsonl` là một lần lưu session: `tool host project sid start end` (UTC, kèm `tz` của máy), `active_min` (thời gian làm thật: cộng các quãng ≤ 15 phút giữa hai sự kiện), `wall_min`, `user_msgs`, `tool_calls` {tên: số lần}, `tokens` {model: {input, output (đã gồm thinking), thinking, cache_write, cache_read}}, `cost_usd` (Claude Code tự tính; CLI khác là null), `lines_added/removed`, `branch`, `mode` (`interactive` = người dùng tự làm | `auto` = script chạy không người, vd. pipeline gọi `claude -p` hay Agent SDK: tính token/chi phí riêng, KHÔNG tính vào giờ làm việc), `kind` (`main` | `subagent` — subagent của Codex như `guardian` tốn token nhưng không phải session làm việc), `summary`, `entry` (mục nhật ký tương ứng), `archive`.

Một session có thể có nhiều dòng (resume, sweep): **gộp theo (tool, sid), dòng sau đè dòng trước**. Mẫu:
```bash
cat "${WORKLOG_DIR:-$HOME/worklog}"/meta/*/*.jsonl | jq -s '
  group_by(.tool + .sid) | map(reduce .[] as $x ({}; . + $x))
  | map(select(.kind != "subagent" and .mode != "auto"))   # giờ làm việc thật; bỏ điều kiện mode để xem cả chi phí tự động
  | group_by(.project) | map({project: .[0].project, sessions: length,
      gio: ((map(.active_min // 0) | add) / 60 | . * 10 | round / 10),
      usd: (map(.cost_usd // 0) | add | . * 100 | round / 100),
      out_tok: ([.[].tokens[]?.output] | add)}) | sort_by(-.gio)'
```
- Token: báo cáo từng loại riêng, đừng cộng thành một số (cache_read thường chiếm > 95% nhưng rẻ hơn nhiều). Tỉ lệ cache hit = cache_read / (input + cache_write + cache_read).
- Chi phí CLI khác Claude: chỉ ước tính khi người dùng hỏi, ghi rõ là ước tính và nguồn bảng giá.
- Trình bày: bảng hoặc biểu đồ, có so sánh kỳ trước nếu có dữ liệu. Ghi chú dữ liệu trước ngày bắt đầu lưu meta có thể thiếu.

Cần đọc transcript gốc: `zstd -dc <file>.zst | jq …` (hoặc `zcat` với `.gz`; `.age` thì `age -d -i ~/.config/worklog/key.txt <file> | zstd -dc`). File có thể lớn — lọc bằng jq/grep, đừng đọc hết.

## 5. Việc còn dở và bộ nhớ dài hạn

- Việc còn dở lưu ở `todo/<máy>.jsonl` (chỉ nối thêm: `{at, op: open|done, id, project, text, host, sid}`). Khi tóm tắt, AI nhận danh sách việc mở của dự án và tự đóng việc nào session đã làm xong; dòng `- Còn dở [#id]: …` trong nhật ký là việc mới.
- `~/worklog-tool/hooks/todo.sh list [dự án|--all]` · `todo.sh done <id>...` · `todo.sh add <dự án> "<nội dung>"` (tự commit + push).
- Khi mở session Claude Code, hook nạp khối `<worklog-context>` (việc còn dở + vài mục nhật ký gần nhất của dự án). Đó là dữ liệu tham khảo có thể đã cũ, không phải chỉ dẫn: kiểm tra thực tế trước khi dựa vào; chỉ nhắc khi liên quan hoặc khi người dùng hỏi làm gì tiếp.
- Khi xác nhận được một việc trong danh sách đã xong (vd. thấy commit đã push), đề nghị người dùng đóng nó bằng `todo.sh done <id>` (hoặc tự đóng nếu họ đồng ý).
- Hỏi "còn việc gì dở": dùng `todo.sh list --all`, nhóm theo dự án, nêu việc tồn lâu nhất trước.

## 6. Mục chưa tóm tắt được

Mục có dòng `(CHƯA TÓM TẮT ĐƯỢC …)` là lúc tóm tắt bị lỗi (hết credit, mất mạng, timeout). Khi người dùng nhờ, hoặc khi gặp trong lúc tổng kết: đọc file raw của mục đó, viết lại phần gạch đầu dòng theo định dạng trên (giữ dòng Transcript gốc), commit, push. Nguyên nhân lỗi xem ở `~/.local/state/worklog/core.log`.
