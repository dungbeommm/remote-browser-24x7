# Remote Browser 24/7 — Chromium điều khiển bằng web

Một trình duyệt Chromium có giao diện đầy đủ, mở trong trình duyệt trên điện thoại/máy tính bằng **noVNC**; chạy trong Docker trên VPS hoặc máy tính luôn bật. Không cần cài Chrome trên thiết bị truy cập.

## Tính năng

- Điều khiển từ xa (chuột, bàn phím, nhiều tab) qua giao diện web noVNC.
- Có **mật khẩu bắt buộc** ở Nginx; cổng điều khiển nội bộ không được public trực tiếp.
- Profile Chromium, cookie, phiên đăng nhập, lịch sử, bookmark, extension và download được ghi vào Docker volume `browser-data` và được giữ lại qua các lần khởi động lại.
- **Quick Tunnel** Cloudflare để kiểm tra: tạo URL HTTPS ngẫu nhiên, miễn phí và không cần tài khoản Cloudflare.
- **Named Tunnel** Cloudflare: URL HTTPS cố định, cần có Cloudflare Tunnel và tên miền do bạn quản lý.
- Docker tự khởi động lại khi máy reboot hoặc container gặp lỗi (`restart: unless-stopped`). Có chế độ tự khởi động lại trình duyệt theo chu kỳ nếu thực sự cần.
- Có workflow GitHub Actions **chỉ dùng để build và smoke-test**, không dùng runner GitHub làm máy chủ 24/7.

> **Quan trọng:** Đây là ứng dụng điều khiển từ xa. Mọi website, mật khẩu, cookie và dữ liệu tải xuống đều tồn tại trên máy chủ bạn triển khai. Hãy bảo vệ máy chủ, volume và mật khẩu. Chromium trong Docker dùng `--no-sandbox`, nên không truy cập các trang không đáng tin cậy hoặc xử lý dữ liệu tối mật trên bản cài đặt này.

## Sơ đồ

```text
Điện thoại / Laptop
      | HTTPS
      v
Cloudflare Tunnel (quick hoặc named)
      |
      v
Nginx Basic Auth :8080
      |
      v
noVNC + websockify :6080 (loopback)
      |
      v
x11vnc :5900 (loopback) -> Xvfb + Openbox -> Chromium
                                              |
                                              v
                                          /data (volume)
                                             ├── profile/
                                             └── downloads/
```

## 1. Yêu cầu

- VPS Linux (ví dụ Ubuntu 22.04+, Debian 12+) hoặc máy Linux luôn bật, kiến trúc amd64, có Docker Engine và Docker Compose v2.
- Gợi ý tối thiểu 2 vCPU, RAM 2–4 GB (4 GB tốt hơn), dung lượng đĩa phù hợp với dữ liệu web/tệp tải về.
- Kết nối Internet ổn định. **GitHub Actions không thay thế máy chủ này.**

Cài Docker theo hướng dẫn của Docker cho bản Linux đang dùng. Kiểm tra `docker --version` và `docker compose version`.

## 2. Khởi chạy và lấy link tạm thời

```bash
git clone https://github.com/dungbeommm/remote-browser-24x7.git
cd remote-browser-24x7
cp .env.example .env
nano .env
```

Đổi `WEB_PASSWORD` thành mật khẩu riêng dài tối thiểu 12 ký tự. Mật khẩu có thể tạo bằng `openssl rand -hex 24`. Đừng đưa mật khẩu hoặc token vào repo.

```bash
docker compose --profile quick up -d --build
./scripts/show-link.sh
```

Nếu link chưa hiện, xem `docker compose logs -f tunnel-quick` rồi chạy lại `./scripts/show-link.sh`. Mở URL `https://...trycloudflare.com` trên điện thoại, nhập `WEB_USER` và `WEB_PASSWORD`. Bạn sẽ thấy desktop Chromium trong noVNC. Nếu không tự kết nối, nhấn **Connect**. Danh sách file đã tải có tại **`https://<link-của-bạn>/downloads/`**, cùng thông tin đăng nhập.

**Nhược điểm:** URL quick tunnel thay đổi khi tunnel được tạo lại và không có cam kết uptime. Nó chỉ phù hợp thử nghiệm.

## 3. Link cố định, chạy lâu dài

Cần một Cloudflare account và tên miền quản lý trên Cloudflare:

1. Vào Cloudflare Zero Trust → Networks → Tunnels, tạo một **Cloudflare Tunnel** (loại `cloudflared`).
2. Thêm **Public hostname**, ví dụ `browser.example.com`, với service **HTTP**, địa chỉ dịch vụ **`http://browser:8080`**. (Chỉ địa chỉ nội bộ Docker; không dùng `localhost` trong Cloudflare Tunnel container.)
3. Lấy **Tunnel token** và đặt vào `.env` tại `CLOUDFLARE_TUNNEL_TOKEN=...`.
4. Dừng quick tunnel nếu đã thử và bật named tunnel:

```bash
docker compose --profile quick down
docker compose --profile stable up -d --build
docker compose --profile stable ps
```

Mở **`https://browser.example.com`** (thay bằng hostname bạn đã cấu hình). Địa chỉ này giữ nguyên khi browser container khởi động lại. Trong khoảng ngắn khi khởi động lại có thể tạm không kết nối được.

Nếu chưa có tên miền, hãy dùng chế độ quick; **không thể cam kết một URL cố định** trong chế độ đó. Có thể cấu hình thêm Cloudflare Access để xác thực email/SSO ở lớp ngoài.

## 4. Lưu dữ liệu và tự khởi động lại

| Dữ liệu | Nơi lưu |
| --- | --- |
| Cookie, lịch sử, đăng nhập, bookmark, extension | `/data/profile` → Docker named volume `browser-data` |
| File tải xuống | `/data/downloads` → Docker named volume `browser-data` |
| Link và mật khẩu đăng nhập | `.env` (chỉ trên máy chủ, tuyệt đối không commit) |

- `docker compose restart browser` **không xóa dữ liệu**. File đã tải có thể lấy trực tiếp qua đường dẫn **`/downloads/`**, được bảo vệ bằng cùng mật khẩu.
- `docker compose down` **không xóa volume**. **Không dùng `docker compose down -v`** (lệnh này xóa dữ liệu).
- Docker `restart: unless-stopped` tự hồi phục khi container lỗi hoặc máy chủ khởi động lại. Máy chủ phải luôn bật.
- `SESSION_ROTATE_HOURS=0` (mặc định) nghĩa là không cố ý gián đoạn phiên, phù hợp cho VPS 24/7.
- Muốn buộc trình duyệt khởi động lại mỗi 5 giờ 30 phút, đổi thành `SESSION_ROTATE_HOURS=5.5`, sau đó chạy `docker compose up -d`. Cách này **chỉ restart container Docker trên VPS**, không kích hoạt hay nối chuỗi GitHub Actions. Mỗi lần restart có gián đoạn ngắn, các phiên web có thể yêu cầu đăng nhập lại.
- Nếu muốn dữ liệu bền vững ngay cả khi VPS bị xóa/mất ổ đĩa, hãy tạo backup định kỳ và sao chép bản backup sang một hệ thống lưu trữ khác.

Sao lưu thủ công (tạm dừng trình duyệt để SQLite/profile được đóng sạch):

```bash
./scripts/backup.sh
```

Lệnh tạo file `.tar.gz` trong `backups/`. File này chứa dữ liệu nhạy cảm, phải lưu riêng tư. Nếu cần khôi phục, xem trợ giúp `./scripts/restore.sh`.

## 5. Điều khiển và bảo trì

```bash
# Trạng thái
docker compose --profile stable ps

# Xem log
docker compose --profile stable logs -f --tail=100 browser

# Khởi động lại browser (giữ profile)
docker compose restart browser

# Dừng / mở lại
docker compose --profile stable stop
docker compose --profile stable up -d

# Truy cập từ ngay trên VPS qua 127.0.0.1 (không mở public port 8080)
curl http://127.0.0.1:8080/healthz
```

Gợi ý cho điện thoại: mở `https://hostname/vnc.html?autoconnect=1&resize=scale`; thanh công cụ noVNC có bàn phím ảo, nút gửi Ctrl/Alt/Del, thu/phóng.

## 6. GitHub Actions được sử dụng như thế nào?

Repo có:

- `.github/workflows/ci.yml`: build Docker image và smoke-test cơ chế xác thực (không có mật khẩu phải nhận HTTP 401).
- `.github/workflows/preview.yml`: **chế độ thử nghiệm ngắn** (10 hoặc 20 phút), khởi chạy browser + Cloudflare Quick Tunnel trên runner GitHub, tạo URL HTTPS trong **Actions → run → Summary**. Để sử dụng: vào repo → Settings → Secrets and variables → Actions, tạo secret `PREVIEW_WEB_PASSWORD` (12+ ký tự); rồi Actions → **Temporary browser preview** → Run workflow. Tên đăng nhập mặc định là `preview`.

Chế độ preview chỉ để kiểm thử, **không lưu profile giữa các run**, không dùng để duy trì máy chủ thường trực và không được dùng để nối chuỗi phiên chạy.

**Không có workflow tự tạo job mới sau 5–6 giờ**. Theo tài liệu GitHub, một job trên GitHub-hosted runner tối đa 6 giờ, và GitHub không cho dùng runner vào hoạt động không liên quan đến production/test/deploy của project. Tạo workflow nối tiếp để duy trì remote browser 24/7 không đáp ứng mục đích sử dụng này và không đảm bảo uptime. Docker trên máy chủ là giải pháp đúng.

Tài liệu:
- https://docs.github.com/en/actions/reference/limits
- https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features
- https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
- https://developers.cloudflare.com/tunnel/concepts/

### Thiết lập Telegram nhanh trên Windows (khuyến nghị)

Đã có script PowerShell **`scripts/setup-telegram.ps1`**. Script hỏi token và mật khẩu bằng nhập liệu ẩn, tìm Chat ID từ tin nhắn Telegram, dùng `gh secret set` để lưu ba GitHub Actions Secrets và chạy thử preview 10 phút. Token không được commit lên GitHub.

1. Thu hồi token cũ đã từng chia sẻ qua **@BotFather** (`/revoke`) và tạo token mới. **Đừng dán token vào chat hoặc issue.**
2. Nhắn `/start` đến bot Telegram bạn muốn nhận link.
3. Trên Windows PowerShell, cài GitHub CLI nếu chưa có: `winget install --id GitHub.cli -e` rồi mở cửa sổ PowerShell mới.
4. Chạy:

   ```powershell
   git clone https://github.com/dungbeommm/remote-browser-24x7.git
   cd remote-browser-24x7
   gh auth login --web
   .\scripts\setup-telegram.ps1
   ```

5. Nhập token **mới** và mật khẩu trình duyệt khi script hỏi. Nếu bot có nhiều chat hoặc không có update thì script sẽ hỏi Chat ID. Sau khi thiết lập, nó sẽ kích hoạt một phiên preview. Bạn nhận link Telegram khi tunnel khởi tạo thành công. Có thể chạy script bằng `-DoNotRun` nếu chỉ muốn lưu secrets.

Đây là script thiết lập trên máy của bạn: GitHub connector dùng trong ChatGPT có thể sửa mã nguồn nhưng **không thể ghi trực tiếp Actions Secrets**, và chương trình cần tài khoản GitHub đã đăng nhập của bạn để gọi lệnh này. Script sử dụng GitHub CLI để mã hóa Secrets trước khi gửi lên GitHub. Không đưa token trực tiếp lên command line hoặc file cấu hình.

### Gửi URL trình duyệt preview qua Telegram tự động

Workflow `.github/workflows/preview.yml` sẽ **gửi link HTTPS đến Telegram** ngay khi link Cloudflare Tunnel xuất hiện, trước khi bắt đầu đếm 10/20 phút chạy thử. Tin nhắn chứa đường link, username `preview`, thời gian phiên và URL workflow; **không gửi mật khẩu**.

1. Vào **@BotFather** trong Telegram, dùng `/revoke` để vô hiệu token cũ nếu đã từng chia sẻ token công khai, sau đó lấy token mới.
2. Mở chat với bot của bạn, nhấn **Start** hoặc gửi `/start`. Bot không thể nhắn tin riêng trước khi người dùng bắt đầu cuộc trò chuyện.
3. Lấy `chat.id` từ Telegram API bằng máy riêng (không công khai token):

   ```bash
   read -r -s -p "New Telegram bot token: " BOT_TOKEN; echo
   curl --silent --show-error --fail "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
   unset BOT_TOKEN
   ```

   Trong JSON trả về, tìm `result[].message.chat.id` ứng với cuộc trò chuyện bạn vừa nhắn. Nếu `result` rỗng, hãy gửi `/start` hoặc một tin nhắn mới rồi chạy lại. Với nhóm Telegram, cần thêm bot vào nhóm và lấy đúng `chat.id` của nhóm (thường là số âm).

4. Mở [Repository Settings → Actions secrets](https://github.com/dungbeommm/remote-browser-24x7/settings/secrets/actions), thêm **ba repository secrets**:

   | Secret | Giá trị |
   | --- | --- |
   | `PREVIEW_WEB_PASSWORD` | Mật khẩu mạnh (tối thiểu 12 ký tự) để mở trình duyệt |
   | `TELEGRAM_BOT_TOKEN` | Token **mới** do BotFather cấp |
   | `TELEGRAM_CHAT_ID` | Giá trị `chat.id` chính xác từ Telegram |

5. Vào **Actions → Temporary browser preview (manual, NOT 24/7) → Run workflow**. Khi tunnel tạo link, workflow sẽ dùng Telegram Bot API `sendMessage` để gửi vào đúng cuộc trò chuyện. Nếu thiếu secret hoặc bot chưa được phép nhắn tin, workflow báo lỗi và không gửi thông báo. Thời gian preview vẫn chỉ là 10 hoặc 20 phút; link không tồn tại sau khi runner dừng.

**Không** thêm token, Chat ID, mật khẩu hoặc file `.env` vào commit GitHub. Hạn chế quyền truy cập vào repo và Actions secrets.

## 7. Triển khai từ repository

Bạn có thể clone mã nguồn vào VPS theo lệnh ở mục 2. Repo chứa mã nguồn và quy trình kiểm thử; tự nó không phải một máy chủ đang chạy.

Dùng repo riêng tư khi lưu thêm cấu hình nhạy cảm; tuyệt đối không commit `.env`, token, thông tin đăng nhập hoặc thư mục dữ liệu trình duyệt.

## 8. Giới hạn cần biết

- Browser được điều khiển thông qua ảnh/chuột/keyboard của noVNC; âm thanh trang web và micro/webcam không được chuyển tiếp đầy đủ như RDP/streaming chuyên dụng.
- Các website có DRM, kiểm tra thiết bị, xác thực hai bước hoặc anti-bot có thể không hoạt động bình thường.
- Không cam kết 100% uptime: VPS, Cloudflare, mạng và ổ đĩa vẫn có thể lỗi. Cần giám sát, backup và tăng độ sẵn sàng nếu sử dụng quan trọng.
- Không chia sẻ URL + mật khẩu cho người lạ. Không public cổng VNC 5900 hoặc websockify 6080 ra Internet.
- Không chạy `docker compose down -v` nếu còn cần dữ liệu.
