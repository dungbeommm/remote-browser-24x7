FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    HOME=/home/browser \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2-utils \
    ca-certificates \
    chromium \
    curl \
    dbus-x11 \
    fonts-dejavu-core \
    fonts-liberation \
    fonts-noto-cjk \
    nginx \
    novnc \
    openbox \
    procps \
    websockify \
    x11-utils \
    x11vnc \
    xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1000 browser \
    && mkdir -p /data /app \
    && chown -R browser:browser /data /home/browser

COPY app/nginx.conf /etc/nginx/nginx.conf
COPY app/start.sh /app/start.sh
COPY app/healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/start.sh /app/healthcheck.sh

EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD /app/healthcheck.sh

ENTRYPOINT ["/app/start.sh"]
