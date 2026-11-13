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
    pulseaudio \
    procps \
    x11-utils \
    xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1000 browser \
    && mkdir -p /data /app \
    && chown -R browser:browser /data /home/browser

ARG SELKIES_VERSION=2.1.0
ARG SELKIES_SHA256=d2a9fd238507b58c93a65e371a756669b8ba91ee237f81c457d5329b0ce756f9
RUN curl -fsSL -o /tmp/selkies.deb "https://github.com/selkies-project/selkies/releases/download/${SELKIES_VERSION}/selkies-${SELKIES_VERSION}-debianbookworm-amd64.deb" \
    && echo "${SELKIES_SHA256}  /tmp/selkies.deb" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/selkies.deb \
    && rm -f /tmp/selkies.deb && rm -rf /var/lib/apt/lists/*

COPY app/nginx.conf /etc/nginx/nginx.conf
COPY app/start.sh /app/start.sh
COPY app/healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/start.sh /app/healthcheck.sh

EXPOSE 8080
VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD /app/healthcheck.sh

ENTRYPOINT ["/app/start.sh"]
