# DOTY + XRAY — FULL PORT MAP (current server truth)

## TCP

| Port | Owner | Serves |
|---|---|---|
| 22 | sshd | direct SSH |
| 80 | nginx | **NTLS WS**: /vless /vmess /trojan /htrojan /hvmess /hvless /xtrojan /xvmess /xvless · `/` → ws.py:700 (SSH-WS) |
| 88 | nginx | alias of 80 |
| 443 | **sslh** | SSH probe → sshd:22 · TLS → xray:8443 (see matrix below) |
| 444 | nginx | **TLS alias** of the 443 WS/gRPC paths (stock doty port) |
| 853 | xray | VLESS+REALITY (sni www.vodacom.co.za) |
| 854 | xray | VLESS+REALITY (sni m.tiktok.com) |
| 1194 | openvpn | TCP server (10.6.0.0/24) |
| 2080 | ws-com | SSH-WS → dropbear:6422 |
| 2081 | nginx | (panel/redirect) |
| 2082 | nginx | VMess WS direct NTLS |
| 2083 | nginx | VMess WS direct TLS |
| 2086 | nginx | VLESS WS direct NTLS |
| 2087 | nginx | VLESS WS direct TLS |
| 6422 | dropbear | lightweight SSH |
| 9643 | sslh | legacy mux (ssh/tls) |

## UDP

| Port | Owner | Serves |
|---|---|---|
| 443 | tuic | TUIC v5 (QUIC, bbr, alpn h3) |
| 1194 | openvpn | UDP server (10.8.0.0/24) |
| 2200 | openvpn | UDP server (10.7.0.0/24) |
| 36712 | udp-custom | ePro UDP VPN (system users) |
| 5667 | zivpn | ZiVPN |

## Localhost-only
700 ws.py (SSH-WS→6422) · 7300 badvpn-udpgw · 7800 udpgw · 8443 xray vless-direct (TLS, sslh target) · 62789 xray api · 1001-1004 trojan · 2001-2004 vmess · 3001-3004 vless · 19723 containerd

## 443 fallback matrix (xray vless-direct :8443)
```
valid VLESS (uuid e92fed95…)  → direct proxy
ALPN h2                       → trojan-grpc :1003 → ProtonVPN USA (tun9)
path /trojan                  → trojan-ws :1001
path /htrojan                 → trojan-httpupgrade :1002
path /vmess                   → vmess-ws :2001
path /hvmess                  → vmess-httpupgrade :2002
path /vless                   → vless-ws :3001
path /hvless                  → vless-httpupgrade :3002
anything else                 → sshd:22 (SSH-SSL)
```

## Client-link port rules
- TLS links → **443** (443 and 444 both work)
- NTLS/WS links → **80** (88 also works)
- Panel-generated links work unmodified (doty stock = 443/80)

## Architecture diagram (xray / SSL / stunnel)

```
                       ┌─────────────────── INTERNET ───────────────────┐
                       │                                                │
 TCP/443 ─┬─ SSH plain ────────▶ sslh ──SSH probe──▶ sshd :22 ─────────┤
 (all     ├─ SSH-SSL (TLS) ────▶  │                                  │
  TLS)    ├─ VLESS-TCP (TLS) ───▶  └─TLS probe──▶ xray :8443 ─┐        │
          ├─ Trojan gRPC (h2) ───────────────┐                │        │
          ├─ Trojan/VMESS/VLESS WS (paths) ──┤  fallbacks:    │        │
          └─ ( scanners / probes ) ──────────┤  h2→1003       │        │
                                             │  /trojan→1001  │        │
 TCP/80,88 ─── WS all paths ────▶ nginx ─────┤  /vmess→2001   │        │
 TCP/444 ─── TLS WS+gRPC ───────▶ nginx ─────┤  /vless→3001   │        │
                                             │  default→sshd  │        │
 TCP/853/854 ─ REALITY ─────────▶ xray inbounds                ▼        │
                                        ┌─ routing ─┬─ direct ───▶ ZA  │
                                        │           ├─ proton ──▶ tun9 │
                                        │           │           (USA)  │
                                        │           └─ dns-out ─▶ DoH  │
 UDP/443 ── TUIC (QUIC) ────────────────────────────────────────▶      │
 UDP/36712 ─ udp-custom ───────── system users (PAM) ───────────▶      │
 UDP/5667 ── zivpn ────────────────────────────────────────────▶       │
 UDP/1194,2200 ─ openvpn (PAM) ────────────────────────────────▶       │
 TCP/2080 ── ws-com ──▶ dropbear :6422 ─┐                        │      │
 TCP/80,444 / ── ws.py :700 ──▶ dropbear ├─ SSH-WS               │      │
 udpgw :7300/:7800 (localhost) ◀── SSH direct-tcpip forwards ────┘      │
                       │                                                │
                       └────────────────────────────────────────────────┘
```
