# ABOUTME: Atheme IRC services container with PostgreSQL support and Tailscale integration
# ABOUTME: Based on overdrivenetworks/atheme-docker approach with Tailscale additions

ARG ATHEME_VERSION=7.2.12
ARG ATHEME_UID=10000

# Tailscale stage - get Tailscale binaries
FROM tailscale/tailscale:latest as tailscale

# Build stage
FROM alpine:latest AS builder
ARG ATHEME_VERSION
ARG MAKE_NUM_JOBS

RUN test -n "$ATHEME_VERSION" || (echo "Please set a version to build in build arg ATHEME_VERSION" && false)

# Install build dependencies including PostgreSQL support
RUN apk add --no-cache \
    build-base \
    pkgconf \
    openssl-dev \
    postgresql-dev \
    pcre-dev \
    autoconf \
    automake \
    libtool \
    git

# Checkout from Git using tagged release (avoids GIT-Access.txt issue)
RUN git clone https://github.com/atheme/atheme -b v${ATHEME_VERSION} --depth=1 /atheme-src --recursive
RUN cd /atheme-src/libmowgli-2 && git pull origin master

# Generate autotools files if needed and configure with PostgreSQL support
RUN cd /atheme-src && \
    autoreconf -fiv && \
    ./configure \
        --prefix=/atheme \
        --with-postgresql \
        --with-pcre \
        --enable-ssl && \
    make -j${MAKE_NUM_JOBS:-$(nproc)} && \
    make install

# Production stage
FROM alpine:latest
ARG ATHEME_UID

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    postgresql-client \
    msmtp \
    ca-certificates \
    curl \
    gettext \
    && rm -rf /var/cache/apk/*

# Copy Atheme from builder
COPY --from=builder /atheme/ /atheme

# Copy Tailscale binaries
COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/tailscale

# Create directories
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale /app

# Add atheme user
RUN adduser -D -h /atheme -u $ATHEME_UID atheme
RUN chown -R atheme /atheme

# Copy configuration templates and startup script
COPY atheme/atheme.conf.template /atheme/etc/atheme.conf.template
COPY atheme/entrypoint.sh /app/start.sh
RUN chmod +x /app/start.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose ports
EXPOSE 8080

# Volume for configuration
VOLUME /atheme/etc

# Container starts as root for Tailscale, drops to atheme user for services
WORKDIR /atheme
CMD ["/app/start.sh"]