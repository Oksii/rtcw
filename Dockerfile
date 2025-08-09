# Build stage
FROM debian:stable-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        unzip \
        jq \
        bbe \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /output

# Download files
ARG STATIC_URL_BASEGAME
ARG RTCWPRO_RELEASE_ID=""

COPY fetchRtcwPro.sh /output/

RUN set -e \
    && mkdir -p /output/main \
    && echo "Downloading base game..." \
    && curl --retry 3 --retry-delay 1 -fsL "${STATIC_URL_BASEGAME}" -o /output/rtcw.zip \
    && echo "Downloading RTCWPro..." \
    && datapath="/output/rtcwpro-data" bash /output/fetchRtcwPro.sh \
    && echo "Extracting files..." \
    && unzip -q -d /output/main /output/rtcw.zip \
    && unzip -q /output/main/mp_bin.pk3 -d /output/main \
    && rm -rf /output/main/*.dll /output/rtcw.zip \
    && mv /output/rtcwpro-data/rtcwpro /output/ \
    && mv /output/rtcwpro-data/wolfded.x86 /output/ \
    && rm -rf /output/rtcwpro-data

# Runtime stage
FROM debian:stable-slim
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        libc6-i386 \
        libc6:i386 \
        unzip \
        jq \
        git \
        bbe \
        qstat \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install additional tools
RUN curl --retry 3 -fsL "http://github.com/icedream/icecon/releases/download/v1.0.0/icecon_linux_amd64" -o /bin/icecon \
    && curl --retry 3 -fsL "http://archive.debian.org/debian/pool/main/g/gcc-2.95/libstdc++2.10-glibc2.2_2.95.4-27_i386.deb" -o /tmp/libstdc.deb \
    && chmod +x /bin/icecon \
    && echo "fa8e4293fa233399a2db248625355a77  /tmp/libstdc.deb" | md5sum -c \
    && dpkg -i /tmp/libstdc.deb \
    && rm /tmp/libstdc.deb

# Setup user
RUN useradd -ms /bin/bash game
USER game
WORKDIR /home/game

# Copy files from builder
COPY --chown=game:game --from=builder /output/ /home/game/
COPY --chown=game:game entrypoint.sh /home/game/start
COPY --chown=game:game autorestart.sh /home/game/autorestart

RUN chmod +x /home/game/start /home/game/autorestart

# Clone config repository
RUN git clone --depth 1 "https://github.com/Oksii/rtcw-config.git" settings/ \
    && rm -rf settings/.git

EXPOSE 27960/udp
ENTRYPOINT ["./start"]