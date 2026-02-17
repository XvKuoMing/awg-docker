# ── Stage 1: Build amneziawg-go (userspace daemon) ──────────────────────────
FROM ubuntu:24.04 AS build-go

RUN apt-get update && apt-get install -y \
        git make golang ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/amnezia-vpn/amneziawg-go /src/amneziawg-go
WORKDIR /src/amneziawg-go
RUN make


# ── Stage 2: Build amneziawg-tools (awg / awg-quick) ───────────────────────
FROM ubuntu:24.04 AS build-tools

RUN apt-get update && apt-get install -y \
        git make gcc libc6-dev pkg-config ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/amnezia-vpn/amneziawg-tools /src/amneziawg-tools
WORKDIR /src/amneziawg-tools/src
RUN make && DESTDIR=/out make install


# ── Stage 3: Runtime image ──────────────────────────────────────────────────
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
        iproute2 iptables resolvconf procps curl \
    && rm -rf /var/lib/apt/lists/*

# Copy built binaries
COPY --from=build-go    /src/amneziawg-go/amneziawg-go  /usr/local/bin/amneziawg-go
COPY --from=build-tools /out/usr/                        /usr/

RUN chmod +x /usr/local/bin/amneziawg-go

# Entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Config will be mounted here
VOLUME /etc/amnezia/amneziawg

ENTRYPOINT ["/entrypoint.sh"]
