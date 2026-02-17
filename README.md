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

## 2. Configure wg0.conf

Copy the template and fill in **your** values:

```bash
cp config/wg0.conf config/wg0.conf.bak   # optional backup
nano config/wg0.conf
```

### Template

```ini
[Interface]
PrivateKey = <YOUR_PRIVATE_KEY>
Address = <YOUR_VPN_IP/CIDR>           # e.g. 10.8.1.2/32
DNS = 1.1.1.1
Table = off

# AmneziaWG obfuscation parameters (copy from your server/provider)
Jc  = <value>
Jmin = <value>
Jmax = <value>
S1  = <value>
S2  = <value>
H1  = <value>
H2  = <value>
H3  = <value>
H4  = <value>

# Routing: replace the placeholders
#   YOUR_VPN_ENDPOINT_IP  — server public IP (e.g. 203.0.113.1)
#   YOUR_ETH0_GATEWAY_IP  — default gateway on the host (run: ip route | grep default)
PostUp  = ip route add YOUR_VPN_ENDPOINT_IP via YOUR_ETH0_GATEWAY_IP dev eth0; ip route del default via YOUR_ETH0_GATEWAY_IP dev eth0; ip route add 0.0.0.0/0 dev wg0; ip -6 route add ::/0 dev wg0
PreDown = ip route del 0.0.0.0/0 dev wg0; ip -6 route del ::/0 dev wg0; ip route add default via YOUR_ETH0_GATEWAY_IP dev eth0; ip route del YOUR_VPN_ENDPOINT_IP via YOUR_ETH0_GATEWAY_IP dev eth0

[Peer]
PublicKey = <YOUR_PEER_PUBLIC_KEY>
PresharedKey = <YOUR_PRESHARED_KEY>
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <YOUR_VPN_ENDPOINT_IP>:<PORT>
PersistentKeepalive = 25
```

### How to find your gateway

```bash
ip route | grep default
# example output: default via 10.0.0.1 dev eth0
# YOUR_ETH0_GATEWAY_IP = 10.0.0.1
```

---

## 3. Start the VPN

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
docker exec amneziawg curl -s ifconfig.me

# Check routes
docker exec amneziawg ip route show
```

---

## 4. Stop the VPN

```bash
docker compose down
```

The container handles `SIGTERM` gracefully — it runs `awg-quick down wg0` before exiting, so routes are restored cleanly.

---

## 5. Auto-start on Boot

Docker's `restart: unless-stopped` policy in `compose.yml` means the container will automatically restart after a host reboot (as long as the Docker daemon is enabled):

```bash
sudo systemctl enable docker
```

If you previously ran `docker compose down`, the container will **not** restart on boot (that's what "unless-stopped" means). To re-enable:

```bash
docker compose up -d
```

---

## 6. Build from Source (optional)

If you want to build the image yourself instead of pulling from Docker Hub:

```bash
# Uncomment the build line and comment out image in compose.yml:
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
