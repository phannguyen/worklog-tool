---
name: worklog
description: Nhật ký làm việc tự động từ Claude Code, Gemini CLI, Codex CLI, Copilot CLI (repo dữ liệu ~/worklog). Dùng khi người dùng hỏi "đã làm gì", xin tổng kết tuần/tháng/năm/dự án, nói "ghi nhật ký", hoặc muốn cài worklog trên máy mới.
---

# Worklog — nhật ký làm việc

- **Code** (public): `~/worklog-tool` — hook cho Claude Code, Gemini CLI, Codex CLI, Copilot CLI; `install.sh`; skill này.
- **Dữ liệu** (private): `~/worklog` — các file nhật ký.

```
2026/11-laptop.md      ← mỗi tháng một file, mỗi máy một file
2026/11-web.md         ← mục ghi từ chat claude.ai
raw/2026/11/*          ← toàn bộ hội thoại của từng session (text; đuôi .gz.age là đã mã hoá)
tong-ket/2026-11.md    ← tổng kết tháng / năm
```

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

## 4. Mục chưa tóm tắt được

Mục có dòng `(CHƯA TÓM TẮT ĐƯỢC …)` là lúc tóm tắt bị lỗi (hết credit, mất mạng, timeout). Khi người dùng nhờ, hoặc khi gặp trong lúc tổng kết: đọc file raw của mục đó, viết lại phần gạch đầu dòng theo định dạng trên (giữ dòng Transcript gốc), commit, push. Nguyên nhân lỗi xem ở `~/.local/state/worklog/core.log`.
