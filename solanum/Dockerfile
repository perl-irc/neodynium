# ABOUTME: Solanum IRCd container with OpenSSL optimization for AMD EPYC processors
# ABOUTME: Multi-stage build with Tailscale integration for secure mesh networking

# Build stage - Optimized for AMD EPYC processors
FROM alpine:latest as builder

# Install build dependencies
RUN apk update && apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    openssl-dev \
    flex \
    bison \
    git \
    && rm -rf /var/cache/apk/*

# Build Solanum with OpenSSL optimizations for fly.io AMD EPYC
WORKDIR /tmp
RUN git clone https://github.com/solanum-ircd/solanum.git
WORKDIR /tmp/solanum
RUN ./autogen.sh
ENV CFLAGS="-march=znver2 -O3"
RUN ./configure --prefix=/opt/solanum \
    --enable-epoll \
    --enable-openssl \
    --enable-aes \
    --with-nicklen=31 \
    --with-topiclen=390 \
    --enable-assert=no
RUN make -j$(nproc) && make install

# Production stage
FROM alpine:latest

# Install runtime dependencies (following official Tailscale guide)
RUN apk update && apk add --no-cache \
    openssl \
    ca-certificates \
    iptables \
    ip6tables \
    pwgen \
    gettext \
    bash \
    su-exec \
    netcat-openbsd \
    && rm -rf /var/cache/apk/*

# Copy Solanum from builder
COPY --from=builder /opt/solanum /opt/solanum

# Copy Tailscale binaries from official image (per Tailscale kb/1132)
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscale /usr/local/bin/tailscale

# Create directories
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
RUN mkdir -p /opt/solanum/var/log /opt/solanum/var/run /opt/solanum/etc

# Create ircd user and set permissions
RUN adduser -D -s /bin/false ircd
RUN chown -R ircd:ircd /opt/solanum/var

# Copy configuration templates and startup script
COPY ircd.conf.template /opt/solanum/etc/ircd.conf.template
COPY entrypoint.sh /app/start.sh
RUN chmod +x /app/start.sh

# Container starts as root for Tailscale, drops to ircd user for Solanum
WORKDIR /opt/solanum

# Security: Solanum service runs as ircd user via su-exec
USER ircd

EXPOSE 6667 6697 7000 8080

CMD ["/app/start.sh"]