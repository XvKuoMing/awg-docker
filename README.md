# AmneziaWG Docker Container

Run [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go) VPN client inside a Docker container on Ubuntu.

**Image:** `kamasalyamov/awg-ubuntu-24-04:0.1.0`

---

## 1. Host Prerequisites

### Install the AmneziaWG kernel module

The kernel module runs on the **host** (not inside the container). Without it the container falls back to the slower userspace implementation.

```bash
# Install prerequisites
sudo apt install -y software-properties-common python3-launchpadlib gnupg2 linux-headers-$(uname -r)

# Add the Amnezia PPA
sudo add-apt-repository ppa:amnezia/ppa

# Install the kernel module
sudo apt-get install -y amneziawg
```

> After a kernel upgrade you must reboot and re-check that the module loads: `sudo modprobe amneziawg`.

### Ensure /dev/net/tun exists

```bash
ls -l /dev/net/tun
```

If missing:

```bash
sudo mkdir -p /dev/net
sudo mknod /dev/net/tun c 10 200
sudo chmod 666 /dev/net/tun
```

### Install Docker & Docker Compose

```bash
# https://docs.docker.com/engine/install/ubuntu/
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
```

---

## 2. Get Credentials from AmneziaVPN App

1. Open AmneziaVPN client app on your phone/desktop.
2. Go to **Share VPN Access**.
3. Set **Connection format** → **AmneziaWG native format**.
4. Press **Share** and copy the config.

The exported config contains everything you need:
- `PrivateKey`, `Address`, `DNS`
- AmneziaWG obfuscation parameters (`Jc`, `Jmin`, `Jmax`, `S1`, `S2`, `H1`–`H4`)
- `[Peer]` section with `PublicKey`, `PresharedKey`, `Endpoint`

> **What's missing from the export:** `Table`, `MTU`, `PostUp`, `PreDown` — you must add these manually (see below).

---

## 3. Discover Host Network Variables

Before editing the config, collect these values from your host:

### Default gateway IP and interface name

```bash
ip route | grep default
# Example output: default via 203.0.113.1 dev ens18 proto static
#   GATEWAY  = 203.0.113.1
#   DEV      = ens18
```

### Your host's IP (the IP assigned to the interface)

```bash
ip addr show ens18
# Look for "inet x.x.x.x" — that is your HOST_IP
# Example: 198.51.100.10
#   HOST_IP = 198.51.100.10
```

### VPN server endpoint IP (from the exported config)

Look at the `Endpoint` line in the exported config:

```
Endpoint = 192.0.2.50:47808
#   VPN_ENDPOINT = 192.0.2.50
```

### Summary of variables

| Variable         | How to find                        | Example          |
|------------------|------------------------------------|------------------|
| `HOST_IP`        | `ip addr show <DEV>`               | `198.51.100.10`  |
| `GATEWAY`        | `ip route \| grep default`         | `203.0.113.1`    |
| `DEV`            | `ip route \| grep default`         | `ens18`          |
| `VPN_ENDPOINT`   | `Endpoint` line in exported config | `192.0.2.50`     |
| `VPN_ADDRESS`    | `Address` line in exported config  | `10.8.1.2/32`    |

---

## 4. Configure wg0.conf

Paste the exported config into `config/wg0.conf`, then add the missing fields.

```bash
nano config/wg0.conf
```

### Full config template

Replace all `<...>` placeholders with your values:

```ini
[Interface]
PrivateKey = <PRIVATE_KEY>
Address = <VPN_ADDRESS>
DNS = 1.1.1.1, 1.0.0.1
Table = off
# MTU = 1280                    # Uncomment if needed (see MTU section below)

# AmneziaWG obfuscation parameters (paste from exported config)
Jc = <value>
Jmin = <value>
Jmax = <value>
S1 = <value>
S2 = <value>
H1 = <value>
H2 = <value>
H3 = <value>
H4 = <value>

# ── PostUp ──────────────────────────────────────────────────────────────────
# 1. Protect SSH: keep traffic from HOST_IP on the main routing table
# 2. Route VPN server endpoint through the local gateway (bypass tunnel)
# 3. Set VPN as default route with low metric (takes priority)
PostUp = ip rule add from <HOST_IP> lookup main prio 100; ip route add <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip route add default dev wg0 metric 50

# ── PreDown ─────────────────────────────────────────────────────────────────
# Reverse everything in opposite order
PreDown = ip route del default dev wg0 metric 50; ip route del <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip rule del from <HOST_IP> lookup main prio 100

[Peer]
PublicKey = <PEER_PUBLIC_KEY>
PresharedKey = <PRESHARED_KEY>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <VPN_ENDPOINT>:<PORT>
PersistentKeepalive = 25
```

### What each PostUp/PreDown command does

| # | PostUp command | Purpose |
|---|----------------|---------|
| 1 | `ip rule add from <HOST_IP> lookup main prio 100` | **SSH protection.** All traffic originating from your host's public IP uses the main (non-VPN) routing table. This keeps your SSH session alive. |
| 2 | `ip route add <VPN_ENDPOINT> via <GATEWAY> dev <DEV>` | Route VPN encrypted packets to the server via your real gateway, not through the tunnel itself (would be a loop). |
| 3 | `ip route add default dev wg0 metric 50` | Everything else goes through the VPN tunnel. Metric 50 is lower (= higher priority) than the default route. |

PreDown reverses these in opposite order.

---

## 5. Avoiding SSH Disconnection

The key line is:

```
ip rule add from <HOST_IP> lookup main prio 100
```

This creates a **policy routing rule**: any packet with source IP = your host's IP is routed using the `main` table (your real gateway), **not** the VPN. Since SSH reply packets have source = HOST_IP, they always go through the direct path.

**This works for both local and external SSH** — it doesn't matter where the client connects from. The rule matches on the _source_ of outgoing (reply) packets, which is always your host's IP.

**How to verify it works after VPN is up:**

```bash
# Check the rule exists
ip rule show
# Should show: 100: from <HOST_IP> lookup main

# Verify SSH traffic doesn't go through VPN
ip route get <HOST_IP>
```

### What is HOST_IP exactly?

`HOST_IP` is the IP address **assigned to your network interface** (the one SSH binds to).

| Host type | What to use as HOST_IP | How to find |
|-----------|------------------------|-------------|
| **Bare metal / direct public IP** | The public IP on the interface | `ip addr show <DEV>` |
| **Cloud VM behind NAT** (AWS, GCP, etc.) | The **private** IP on the interface | `ip addr show <DEV>` (e.g. `10.0.0.5`) |
| **VPS with public IP on interface** | The public IP on the interface | `ip addr show <DEV>` |

> The rule uses the kernel's source IP, which is always the IP on the interface — even if the world sees a different (NAT'd) public IP via `curl ifconfig.me`.

### Multiple IPs or interfaces

If your host has **multiple IPs** that receive SSH (e.g. IPv4 + IPv6, or multiple interfaces), add a rule for each:

```ini
PostUp = ip rule add from <HOST_IP_1> lookup main prio 100; ip rule add from <HOST_IP_2> lookup main prio 100; ip route add <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip route add default dev wg0 metric 50
PreDown = ip route del default dev wg0 metric 50; ip route del <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip rule del from <HOST_IP_2> lookup main prio 100; ip rule del from <HOST_IP_1> lookup main prio 100
```

### SSH on a non-standard port

No extra config needed — the `ip rule from` matches by source IP regardless of port. SSH on port 22, 2222, or any other port is all protected the same way.

---

## 6. When to Use MTU

**MTU** (Maximum Transmission Unit) controls the largest packet size on the VPN interface.

### When to set `MTU = 1280`

- You experience **random timeouts**, pages half-loading, or SSH freezing on large output.
- The host is behind **PPPoE** (DSL), **double NAT**, or running inside a **VM/VPS** that already has a reduced MTU.
- You see ICMP "packet too large" messages or `ping -s 1400 -M do <VPN_IP>` fails.

### When to leave it out (default)

- Everything works fine — WireGuard auto-negotiates MTU in most cases.
- Default is typically `1420` (1500 minus WireGuard overhead).

### How to test

```bash
# Find the largest working MTU (decrease until it passes)
ping -c 3 -s 1372 -M do 1.1.1.1    # 1372 + 28 header = 1400
ping -c 3 -s 1252 -M do 1.1.1.1    # 1252 + 28 header = 1280
```

If `1372` fails but `1252` works, set `MTU = 1280`.

---

## 7. Split Tunneling (VPN Only for Specific Sites)

If you want **only certain traffic** through the VPN (not everything):

### Option A: Route specific IPs through VPN

Change `AllowedIPs` in `[Peer]` and simplify PostUp/PreDown:

```ini
[Interface]
# ...
# Remove Table = off (let awg-quick manage the routing table)
# Remove PostUp / PreDown

[Peer]
# ...
# Instead of 0.0.0.0/0, list only the IPs/subnets you want through VPN:
AllowedIPs = 104.16.0.0/12, 172.67.0.0/16, 93.184.216.34/32
```

### Option B: Route specific domains through VPN

WireGuard works at the IP level, so you need to resolve domains to IPs first:

```bash
# Find IPs for a domain
dig +short example.com
dig +short netflix.com

# Find the whole subnet a service uses
whois $(dig +short netflix.com | head -1) | grep -i cidr
```

Then add those CIDRs to `AllowedIPs`.

### Option C: Full tunnel + exclude specific IPs

Keep `AllowedIPs = 0.0.0.0/0` but bypass VPN for certain destinations:

```ini
PostUp = ip rule add from <HOST_IP> lookup main prio 100; ip route add <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip route add default dev wg0 metric 50; ip route add 10.0.0.0/8 via <GATEWAY> dev <DEV>
PreDown = ip route del 10.0.0.0/8 via <GATEWAY> dev <DEV>; ip route del default dev wg0 metric 50; ip route del <VPN_ENDPOINT> via <GATEWAY> dev <DEV>; ip rule del from <HOST_IP> lookup main prio 100
```

This sends `10.0.0.0/8` directly, everything else through VPN.

---

## 8. Start the VPN

```bash
cd /path/to/awg
docker compose up -d
```

Check logs:

```bash
docker logs amneziawg
```

Verify the tunnel is up:

```bash
# Show interface status
docker exec amneziawg awg show wg0

# Check your public IP (should be the VPN exit IP)
curl -s ifconfig.me

# Check routes
ip route show

# Check policy rules (SSH protection)
ip rule show
```

---

## 9. Stop the VPN

```bash
docker compose down
```

The container handles `SIGTERM` gracefully — it runs `awg-quick down wg0` before exiting, which triggers PreDown and restores routing cleanly.

---

## 10. Auto-start on Boot

Docker's `restart: unless-stopped` policy in `compose.yml` means the container restarts automatically after a host reboot (as long as the Docker daemon is enabled):

```bash
sudo systemctl enable docker
```

If you previously ran `docker compose down`, the container will **not** restart on boot. To re-enable:

```bash
docker compose up -d
```

---

## 11. Build from Source (optional)

If you want to build the image yourself instead of pulling from Docker Hub:

```bash
# In compose.yml, replace "image:" with "build:":
#   build: .
#   # image: kamasalyamov/awg-ubuntu-24-04:0.1.0

docker compose up -d --build
```

---

## File Structure

```
awg/
├── Dockerfile          # Multi-stage build (Ubuntu 24.04)
├── compose.yml         # Docker Compose config
├── entrypoint.sh       # Startup/shutdown script
├── config/
│   └── wg0.conf        # ← Your VPN configuration
└── README.md
```

---

## Quick Reference

```bash
# Start
docker compose up -d

# Logs
docker logs -f amneziawg

# Status
docker exec amneziawg awg show wg0

# My public IP
docker exec amneziawg curl -s ifconfig.me

# Routes
ip route show
ip rule show

# Stop
docker compose down
```
