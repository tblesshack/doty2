# CLIENT SIDE — what's required per protocol

Server: <SERVER_IP> · domain: opbless.duckdns.org
Rule #1: self-signed TLS everywhere → **allowInsecure / skip-cert-verify = ON** (except REALITY)

## App matrix

| Protocol | Android | iOS | Router (DotyWRT) | PC |
|---|---|---|---|---|
| VLESS (443 TCP-TLS) | v2rayNG, NekoBox | Shadowrocket, Streisand, FoXray | PassWall/HomeProxy | NekoRay, v2rayN, InvisibleMan |
| VLESS/VMess WS (80/2086/2082) | v2rayNG, NekoBox | same | PassWall | v2rayN, NekoRay |
| VLESS REALITY (853/854) | NekoBox, Husi, v2rayNG ≥1.8 | Shadowrocket ≥2.2.27, Streisand | PassWall2 (sing-box ≥1.8) | NekoRay, v2rayN ≥6.23 |
| Trojan gRPC (443/444) | v2rayNG, NekoBox | Shadowrocket, Streisand | PassWall | v2rayN, NekoRay |
| TUIC (UDP 443/8444) | **NekoBox + TUIC plugin** ⚠️ | Streisand | sing-box profiles | NekoRay |
| udp-custom (36712) | **HTTP Custom / ePro UDP Custom** | — | — | — |
| ZiVPN (UDP 5667) | **ZiVPN app** | — | — | — |
| OpenVPN (1194/2200) | OpenVPN Connect | OpenVPN Connect | openvpn-client | OpenVPN |
| SSH-SSL (443) | **HTTP Custom / ePro** | — | — | any SSH+stunnel client |
| SSH-WS (80/444/2080) | HTTP Custom (WS payload) | — | — | — |

## Per-protocol client settings

### VLESS direct (PRIMARY)
- addr <SERVER_IP> :443 · uuid e92fed95-…-55a00b · tcp · tls · sni opbless.duckdns.org · **insecure ON** · flow none

### REALITY (no insecure flag needed!)
- 853 → sni www.vodacom.co.za · 854 → sni m.tiktok.com
- flow **xtls-rprx-vision** · fp chrome · pbk/sid from reality.txt
- ⚠️ old cores fail — update app first

### TUIC
- uuid e92fed95-… · password <PASSWORD> · alpn h3 · bbr · insecure ON
- ⚠️ NekoBox needs the TUIC plugin APK (GitHub: MatsuriDayo/plugins)

### udp-custom
- HTTP Custom → mode: UDP Custom · host <SERVER_IP> · port 36712 · user/pass (from `udp` menu)
- Rain/CGNAT: keepalive 10–20 s

### SSH-SSL (HTTP Custom)
- host <SERVER_IP>:443 · SSL ON · SNI = anything EXCEPT opbless.duckdns.org (that SNI = xray VLESS!)
- SSH user/pass · UDPGW field: `127.0.0.1:7300` (NOT the server IP!)

### OpenVPN
- import .ovpn → login = system user (PAM). Create: `useradd -M -s /bin/false NAME && passwd NAME`

## ISP notes (tested live)
- **Vodacom ZA**: blocks/throttles QUIC on UDP 443 (hysteria/tuic die there) → use TCP: VLESS-443, WS-80/2082/2086, REALITY-853/854, trojan-gRPC, SSH-SSL. udp-custom (36712) works.
- **Rain ZA**: CGNAT hops IPs every few min → app keepalive 10–20 s; UDP fine (udp-custom, tuic OK).
- **Econet LS**: udp-custom confirmed working.

## Quick start per user type
- Phone, Vodacom: v2rayNG → import vless-443 link → done
- Phone, Rain: HTTP Custom udp-custom OR NekoBox tuic
- iPhone: Shadowrocket → any vless/trojan/reality link
- Whole home: DotyWRT → VLESS-443 node → all devices behind it
