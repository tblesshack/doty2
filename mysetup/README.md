# My DOTY Setup (personalized defaults + ops manual)
Server: <SERVER2_IP> · domain: redbuntu.duckdns.org · Linode
(Cert + nginx SNI also cover opbless.duckdns.org for migrated clients.)

## 1. Port map (current truth)

| Port | Proto | Service | Notes |
|---|---|---|---|
| 22 | tcp | sshd | direct SSH |
| 53 | udp | — | free (MasterDnsVPN removed) |
| 80 | tcp | nginx NTLS | all WS paths + SSH-WS at `/` (see §8); panel NTLS links use this |
| 88 | tcp | nginx NTLS | alias of 80 |
| 443 | tcp | **sslh → xray** | universal TLS port (see §2) + plain SSH probe |
| 443 | udp | TUIC | QUIC (replaced hysteria2) |
| 444 | tcp | nginx TLS | alias of 443 paths (grpc/ws/hu/xhttp) |
| 2080 | tcp | ws-com (proxy.service) | SSH-WS → dropbear:6422 |
| 2082/2083 | tcp | nginx | vmess WS direct (NTLS/TLS) |
| 2086/2087 | tcp | nginx | vless WS direct (NTLS/TLS) |
| 2200 | udp | OpenVPN | 10.7.0.0/24, PAM auth |
| 1194 | tcp+udp | OpenVPN | 10.6/10.8.0.0/24, PAM auth |
| 6422 | tcp | dropbear | lightweight SSH |
| 7300 | tcp | badvpn-udpgw | UDP gateway (localhost) |
| 7800 | tcp | udpgw | UDP gateway (localhost, systemd unit) |
| 8443 | tcp | xray-direct | localhost TLS entry (sslh target); 1001–3004 protocol inbounds (localhost) |
| 36712 | udp | udp-custom | ePro UDP VPN, system-user auth |
| 5667 | udp | zivpn | passwords in /etc/zivpn/config.json |
| 9643 | tcp | sslh | legacy mux port |

**Link rule for clients: TLS → 443, NTLS → 80** — panel links work unmodified.
444/88 remain as aliases.

## 2. Port 443 routing (xray fallbacks)

```
443/tcp → sslh ──SSH probe──→ sshd:22
              └─TLS probe──→ xray:8443 (vless+tls)
                              ├─ valid VLESS      → direct proxy
                              ├─ ALPN h2          → trojan-grpc :1003
                              ├─ path /trojan     → trojan-ws   :1001
                              ├─ path /htrojan    → trojan-hu   :1002
                              ├─ path /vmess      → vmess-ws    :2001
                              ├─ path /hvmess     → vmess-hu    :2002
                              ├─ path /vless      → vless-ws    :3001
                              ├─ path /hvless     → vless-hu    :3002
                              └─ anything else    → sshd:22 (SSH-SSL)
```
Panel-generated links (443/80) work unmodified. 444 = nginx alias.

## 3. Accounts
- VLESS uuid: <VLESS_UUID> (tbless22)
- VMESS uuid: <VMESS_UUID> (thabiso80)
- Trojan password: <PASSWORD>
- TUIC uuid/password: <VLESS_UUID> / <PASSWORD> (replaced hysteria) · ZiVPN: <PASSWORD>
- SSH/VPN system users: thabiso, tblesshack, tshepo, ameka (+ panel-created, e.g. thd5)
- Self-signed cert CN=opbless.duckdns.org (/etc/xray/xray.crt) → clients need allowInsecure/skip-verify

## 4. DNS architecture (OCI-only quirk — NOT active on this box)
- This server (Linode) reaches public resolvers directly — no DNAT, no immutable
  resolv.conf; `dig @8.8.8.8` works and systemd-resolved (127.0.0.53) is healthy.
- On OCI boxes the edge blocks outbound :53 to public resolvers (1.1.1.1 etc.):
  fix is `iptables -t nat OUTPUT :53 → 169.254.169.254` (OCI resolver), persisted
  via netfilter-persistent; /etc/resolv.conf = 169.254.169.254 (immutable).
  The installer applies this ONLY when public DNS is dead (skipped here).
- xray dns = "localhost" (consumes OS resolver) on both.
- **Symptom if broken: tunnels connect but clients have no internet**

## 5. Firewall/iptables notes
- INPUT has catch-all REJECT (OCI default) — new ACCEPTs must be inserted BEFORE it
- Persist changes: `netfilter-persistent save`
- fail2ban: sshd jail only (inet f2b-table)
- INPUT chain accumulates duplicates from panel scripts — cleanup pending

## 6. OS tuning
- /etc/sysctl.d/99-udp-tuning.conf: rmem/wmem_max 128M, backlog 32768 (udp-custom needs it; config asks 80M)
- rsyslog: /etc/rsyslog.d/10-udp-custom-drop.conf (udp-custom INFO flood dammed)
- journald vacuumed to 100M

## 7. Panel (doty)
- Launch: `doty` or `menu` → /usr/local/sbin/menu
- Managers in /usr/local/bin: doty-ssh, vless, vmess, trojan, dns, domain, socks, status, update, log, netguard, iptools, port, zivpn-mgr, expiry
- [01] SSH menu: bare `ssh` wrapper → doty-ssh manager; args → /usr/bin/ssh.openssh
- trojan/vless/vmess managers are wrapped (manager.bin + doty-linkfix): appends allowInsecure=1 to TLS links
- zivpn server binary = /usr/local/bin/zivpn-server (name freed for the manager)
- SSHPlus removed (backup: /root/backups/sshplus)

## 8. SSH/WebSocket services
- edu.service: ws.py :700 → dropbear:6422 (nginx `location /` on 80/444 proxies here)
- proxy.service: ws-com :2080 → dropbear:6422
- STOCK REPO BUGS FIXED: ws pointed at rpcbind:111, ws-com at dead :109
- udpgw.service: proper systemd unit (was fragile screen)

## 9. Common operations
```bash
# add VPN/SSH user (PAM-based: openvpn, ssh, udp-custom)
useradd -M -s /bin/false -e $(date +%F -d '+30 days') NAME && passwd NAME

# verify all vless/vmess paths (15 tests)
bash mysetup/verify-paths.sh

# live client traffic
tail -f /var/log/xray/access.log
journalctl -u tuic -f              # tuic (QUIC 443/udp)
journalctl -u udp-custom -f          # udp-custom connects
journalctl -u badvpn -f              # udpgw :7300

# restart stack
systemctl restart xray nginx sslh
```

## 10. Troubleshooting quick hits
| Symptom | Cause → fix |
|---|---|
| connects, no internet | DNS: §4 DNAT missing → re-add, check `dig @1.1.1.1` |
| "udpgw error" in app | app UDPGW field must be 127.0.0.1:7300 (or :7800), NOT server IP |
| TUIC fails on Vodacom | ISP throttles QUIC/443 → ask to move TUIC to 8444 (config ready) |
| SSH-SSL "closed during identification" | stunnel4 is gone by design — SSH-SSL now via xray fallback (§2) |
| panel link fails | pre-d237f6a links had wrong ports — regenerate |
| Rain CGNAT micro-drops | set app keepalive 10–20s |

## 11. Backups
- /root/backups/* (pre-install copies)
- /etc/xray/config.json.bak* (pre-change copies)
- This repo = full reference

## 12. Removed services (history)
anydesk, teamviewer, stunnel4/5 (replaced by sslh+xray fallback), hysteria2 (replaced by TUIC), udp2raw, squid, ohp, ws-com→restored, gost, mita, masterdnsvpn, psiphond, agn-websocket, noobzvpns, edu→restored, mieru
- Live xray config is /etc/xray/config.json; /usr/local/etc/xray/config.json is a symlink to it
  (xray-install drop-in overrides the path — the symlink keeps panel edits live).
- Panel UI text (DOTTYCAT banners) is baked into the compiled manager binaries
  (strings are obfuscated — no source available), so it cannot be reworded by the
  installer. All repo docs, installer output and client remarks stay neutral.

## Files → where they go
| File | Deploy to |
|---|---|
| xray-config.json | /etc/xray/config.json |
| nginx-doty.conf | /etc/nginx/conf.d/doty.conf |
| udp-custom-config.json | /root/udp/config.json |
| zivpn-config.json | /etc/zivpn/config.json |
| hysteria-config.yaml | /etc/hysteria/config.yaml |
| sslh-defaults | /etc/default/sslh |
| udpgw.service, ssh-ws/proxy.service, ssh-ws/edu.service | /etc/systemd/system/ |
| doty-linkfix, manager-wrapper-template.sh | /usr/local/bin/ |
| verify-paths.sh | anywhere (test tool) |
