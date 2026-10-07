# HTTP Custom — SSH over SSL setup (client side)

Server path: HTTP Custom → TLS :443 → sslh → xray fallback → sshd:22
(Looks like HTTPS to the ISP. Works on Vodacom — TCP 443 is never blocked.)

## Settings

| Field | Value |
|---|---|
| Connection mode | **SSH + SSL/TLS** |
| Server / Host | `<SERVER_IP>` (or opbless.duckdns.org) |
| Port | `443` |
| SSL/TLS | **ON** |
| SNI / Bug host | anything — use your ISP's free/zero-rated host if you have one (e.g. `www.rain.co.za`, `www.vodacom.co.za`); any SNI works because the server self-signs |
| SSH Username | system user, e.g. `tblesshack` (create more with the `udp`/`doty` menu) |
| SSH Password | that user's password |
| **UDPGW** | **`127.0.0.1:7300`** ← NOT the server IP! (it's reached through the SSH tunnel) |

## Steps (HTTP Custom)
1. Home → check **SSH** box → enter host `<SERVER_IP>`, port `443`
2. Check **SSL/TLS** box → SNI field: your bug host (or leave `opbless.duckdns.org`-free — any works)
3. Username/Password → the SSH account
4. Extras → UDPGW = `127.0.0.1:7300`
5. CONNECT → log should read `Connected / SSH authentication succeeded`

## If it fails
| Error | Cause → fix |
|---|---|
| closed during identification exchange | you're hitting something that isn't the TLS→SSH path → confirm port 443, SSL ON |
| auth failed | wrong user/pass (test with any SSH client on port 22 first) |
| udpgw error | UDPGW field ≠ 127.0.0.1:7300 (or try :7800) |
| connects, no internet | device DNS — set HTTP Custom DNS to 1.1.1.1 or enable its VPN DNS |
| instant disconnect | ISP SNI filter → change SNI to a host your ISP zero-rates |
