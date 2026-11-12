# Security notes

This project exposes a full remote desktop to the Internet. The browser is not a hardened isolation boundary.

1. Always replace the default password with a unique long secret before enabling tunnels. Add Cloudflare Access on your named tunnel when possible.
2. Use a private GitHub repository. Never commit `.env`, tokens or the browser volume. Audit any browser extensions you install.
3. No public VNC (5900) or websockify (6080) ports. Nginx listens on 8080 and Docker maps 8080 to **localhost only**; Cloudflare is the HTTPS entrypoint.
4. Browser profile data can contain cookies and credentials, and Chromium's `--password-store=basic` stores credentials without a system keyring. Encrypt the VPS disk, restrict admin access, and keep backups private.
5. Chromium is launched with `--no-sandbox` for common Docker compatibility. Avoid untrusted sites or sensitive accounts. For high-security use, replace the browser isolation with a sandboxed host/VM and proper sandbox configuration.
6. `http://127.0.0.1:8080` is plain HTTP and intended only for local VPS administration. Never forward it to the public Internet without TLS.
7. Update the Chromium image and Cloudflare tunnel regularly; reboot the host for security updates.
8. The `/downloads/` endpoint lists downloaded files to anyone who authenticates to the browser. Protect credentials accordingly.
