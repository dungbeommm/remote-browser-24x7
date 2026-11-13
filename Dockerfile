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
    openbox \
    procps \
    x11-utils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1000 browser \
    && mkdir -p /data /app \
    && chown -R browser:browser /data /home/browser

ARG KASMVNC_VERSION=1.5.0
ARG KASMVNC_SHA256=770fd3df51510beecc89666879d82faf411276e68c6e11df612f736b891b5f71
RUN curl -fsSL -o /tmp/kasmvnc.deb "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_bookworm_${KASMVNC_VERSION}_amd64.deb" \
    && echo "${KASMVNC_SHA256}  /tmp/kasmvnc.deb" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/kasmvnc.deb \
    && rm -f /tmp/kasmvnc.deb && rm -rf /var/lib/apt/lists/* \
    && test -x /usr/bin/Xkasmvnc && test -d /usr/share/kasmvnc/www

COPY app/nginx.conf /etc/nginx/nginx.conf
COPY app/start.sh /app/start.sh
COPY app/healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/start.sh /app/healthcheck.sh

EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD /app/healthcheck.sh

ENTRYPOINT ["/app/start.sh"]
