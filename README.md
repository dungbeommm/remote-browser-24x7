# Remote Browser 24/7 — Chromium điều khiển bằng web

Một trình duyệt Chromium có giao diện đầy đủ, mở trong trình duyệt trên điện thoại/máy tính bằng **Selkies**; chạy trong Docker trên VPS hoặc máy tính luôn bật. Không cần cài Chrome trên thiết bị truy cập.

## Tính năng

- Điều khiển từ xa (chuột, bàn phím, nhiều tab) qua giao diện web Selkies.
- Có **mật khẩu bắt buộc** ở Nginx; cổng điều khiển nội bộ không được public trực tiếp.
- Profile Chromium, cookie, phiên đăng nhập, lịch sử, bookmark, extension và download được ghi vào Docker volume `browser-data` và được giữ lại qua các lần khởi động lại.
- **Quick Tunnel** Cloudflare để kiểm tra: tạo URL HTTPS ngẫu nhiên, miễn phí và không cần tài khoản Cloudflare.
- **Named Tunnel** Cloudflare: URL HTTPS cố định, cần có Cloudflare Tunnel và tên miền do bạn quản lý.
- Docker tự khởi động lại khi máy reboot hoặc container gặp lỗi (`restart: unless-stopped`). Có chế độ tự khởi động lại trình duyệt theo chu kỳ nếu thực sự cần.
- Có workflow CI và phiên nối tiếp trên GitHub Actions; phiên nối tiếp lưu profile bằng artifact mã hóa.

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
Selkies WebSocket :6080 (loopback)
      |
      v
Xvfb + Openbox -> Chromium
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

Nếu link chưa hiện, xem `docker compose logs -f tunnel-quick` rồi chạy lại `./scripts/show-link.sh`. Mở URL `https://...trycloudflare.com` trên điện thoại, nhập `WEB_USER` và `WEB_PASSWORD`. Bạn sẽ thấy desktop Chromium trong Selkies. Danh sách file đã tải có tại **`https://<link-của-bạn>/downloads/`**, cùng thông tin đăng nhập.

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

Gợi ý cho điện thoại: mở `https://hostname/`; thanh công cụ Selkies có bàn phím ảo, thu phóng và tùy chỉnh chất lượng truyền hình.

## 6. GitHub Actions được sử dụng như thế nào?

Repo có:

- `.github/workflows/ci.yml`: build Docker image và smoke-test cơ chế xác thực (không có mật khẩu phải nhận HTTP 401).
- `.github/workflows/browser-24x7.yml`: chạy trình duyệt và Cloudflare Quick Tunnel, lưu dữ liệu giữa các run qua artifact mã hóa.
- `.github/workflows/browser-watchdog.yml`: khởi chạy lại chuỗi nếu không có run nào hoạt động.

Workflow `browser-24x7.yml` lưu profile và file tải sau 300 phút (mặc định), tải lên GitHub artifact đã mã hóa, rồi mới gọi run tiếp theo. Run mới giải mã và khôi phục dữ liệu trước khi bật Chromium. Tạo secret `SESSION_BACKUP_KEY` dài ít nhất 32 ký tự trong **Settings → Secrets and variables → Actions**; giữ nguyên secret này giữa các run. Nếu mất hoặc đổi key, các artifact cũ không giải mã được. `PREVIEW_WEB_PASSWORD` vẫn là mật khẩu truy cập web.

Việc chuyển run có gián đoạn; tab được Chromium khôi phục từ profile nhưng nội dung đang chạy trong RAM, form chưa lưu và tiến trình web không tiếp tục nguyên trạng. Cloudflare Quick Tunnel cấp link mới ở mỗi run. Artifact có thời hạn lưu 7 ngày và phụ thuộc giới hạn dung lượng/artifact của GitHub. Runner GitHub có giới hạn thời gian và không bảo đảm uptime; xem [giới hạn Actions](https://docs.github.com/en/actions/reference/limits) và [điều khoản sử dụng](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features).

Tài liệu:
- https://docs.github.com/en/actions/reference/limits
- https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features
- https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
- https://developers.cloudflare.com/tunnel/concepts/

### Thiết lập Telegram trên Windows

Script `scripts/setup-telegram.ps1` hỏi token Telegram, Chat ID, mật khẩu web và key mã hóa bản lưu; nó ghi bốn Actions secrets qua GitHub CLI rồi khởi chạy `browser-24x7.yml`. Chạy `gh auth login --web`, sau đó `./scripts/setup-telegram.ps1` trong PowerShell. Thêm `-DoNotRun` nếu chỉ muốn lưu secrets. Link phiên mới được gửi qua Telegram khi tunnel sẵn sàng; mật khẩu không có trong tin nhắn.

Giữ kín `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `PREVIEW_WEB_PASSWORD` và `SESSION_BACKUP_KEY`; không commit chúng vào repo.

## 7. Triển khai từ repository

Bạn có thể clone mã nguồn vào VPS theo lệnh ở mục 2. Repo chứa mã nguồn và quy trình kiểm thử; tự nó không phải một máy chủ đang chạy.

Dùng repo riêng tư khi lưu thêm cấu hình nhạy cảm; tuyệt đối không commit `.env`, token, thông tin đăng nhập hoặc thư mục dữ liệu trình duyệt.

## 8. Giới hạn cần biết

- Cấu hình này dùng Selkies WebSocket/WebCodecs qua một cổng HTTP, tương thích với Cloudflare Tunnel hiện tại. WebRTC cần thêm TURN hoặc đường UDP trực tiếp; phải cấu hình chúng trước khi đổi `--mode` trong `app/start.sh`. Âm thanh, micro và webcam phụ thuộc khả năng của trình duyệt truy cập và cấu hình Selkies.
- Các website có DRM, kiểm tra thiết bị, xác thực hai bước hoặc anti-bot có thể không hoạt động bình thường.
- Không cam kết 100% uptime: VPS, Cloudflare, mạng và ổ đĩa vẫn có thể lỗi. Cần giám sát, backup và tăng độ sẵn sàng nếu sử dụng quan trọng.
- Không chia sẻ URL + mật khẩu cho người lạ. Không public cổng Selkies 6080 ra Internet; chỉ truy cập qua Nginx có xác thực.
- Không chạy `docker compose down -v` nếu còn cần dữ liệu.
