# Deploying doty-panel on a CLEAN server

Repeatable: **~95%**. Everything except the items marked ⚠️ below
(server IP, domain, certs, cloud firewall) — those are per-server by nature.

## 0. Get the repo

**Option A — GitHub (once pushed):**
```bash
git clone git@github.com:tblesshack/doty-panel.git
cd doty-panel
```

**Option B — direct transfer (works today):**
```bash
# from the OLD server:
rsync -a /root/tcpudp/tblesshack-repo/ root@NEW_SERVER_IP:/root/doty-panel/
ssh root@NEW_SERVER_IP; cd /root/doty-panel
```

## 1. Base packages (Ubuntu 22.04/24.04)
```bash
apt update && apt install -y nginx sslh dropbear openvpn python3 rsyslog \
  iptables-persistent netfilter-persistent git curl tcpdump fail2ban udns-utils 2>/dev/null || true

# xray (official installer)
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# badvpn-udpgw (udp gateway) — build or copy from old server (/usr/bin/udpgw, /usr/bin/badvpn)
```

## 2. Bundled binaries (in this repo)
```bash
install -m755 bin/udp-custom   /root/udp/udp-custom
install -m755 bin/tuic-server  /usr/local/bin/tuic-server
install -m755 bin/zivpn-server /usr/local/bin/zivpn-server
```

## 3. Run the friendly installer
```bash
./install.sh            # safe: won't clobber existing configs
# or full config install on a truly clean box:
./install.sh --configs --yes
```
This lays down: panel + managers, ssh wrapper, SSH/WS services (edu/proxy/udpgw),
sysctls, DNS guard, log guards.

## 4. ⚠️ Per-server customization (REQUIRED)

| Item | Action |
|---|---|
| **IP addresses** | client configs in `client-configs/` reference <SERVER_IP> → regenerate for new IP |
| **Domain** | `opbless.duckdns.org` → your domain; update nginx server_name + xray fallback SNI |
| **TLS cert** | `openssl req -x509 -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -days 3650 -nodes -subj '/CN=YOUR.DOMAIN'` (chown to xray user) |
| **UUIDs/passwords** | REGENERATE — never reuse production secrets across servers (`xray uuid`) |
| **OCI Security List** | open: tcp 22,80,443,444,853,854,2080,2082,2086,6422,9643,1194 · udp 443,1194,2200,36712,5667 |
| **DNS** | OCI boxes: the installer auto-adds the :53→169.254.169.254 DNAT. Non-OCI: skip + set normal resolvers |

## 5. Verify
```bash
bash mysetup/verify-paths.sh        # 15 protocol paths
systemctl is-active xray nginx sslh udp-custom zivpn tuic edu proxy udpgw
```

## What is NOT portable
- OCI-internal DNS resolver IP (169.254.169.254) — OCI only
- ProtonVPN outbound (needs your own proton.conf + `dev tun9`)
- fail2ban ban list (rebuilds itself)
- The ~2600-rule accumulated iptables INPUT (fresh boxes get clean rules via netfilter-persistent)
