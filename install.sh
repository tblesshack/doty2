#!/bin/bash
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  DOTY-PANEL — friendly safe installer
#  Installs the DOTY panel + SSH/WS services WITHOUT
#  clobbering an existing xray/nginx/sslh setup.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -uo pipefail
cd "$(dirname "$0")"

#--- colors & helpers ---
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'
bar()  { echo -e "${B}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"; }
ok()   { echo -e "${G}  ✔ $1${N}"; }
warn() { echo -e "${Y}  ⚠ $1${N}"; }
err()  { echo -e "${R}  ✘ $1${N}"; }
ask()  { echo -ne "${Y}  ➜ $1 [y/N]: ${N}"; read -r a; [[ $a =~ ^[yYsS]$ ]]; }
have() { command -v "$1" &>/dev/null; }

AUTO=0; WITH_CONFIGS=0
for f in "$@"; do case $f in --yes|-y) AUTO=1;; --configs) WITH_CONFIGS=1;; --help|-h)
  echo "usage: $0 [--yes] [--configs]"; exit 0;; esac; done

clear; bar
echo -e "${B}        DOTY-PANEL · friendly installer${N}"
bar

#--- preflight ---
[[ $EUID -ne 0 ]] && { err "run as root"; exit 1; }
. /etc/os-release 2>/dev/null || true
[[ ${ID:-} =~ ^(ubuntu|debian)$ ]] || warn "untested OS (${ID:-unknown}) — continuing anyway"
[[ $(uname -m) == x86_64 ]] || { err "x86_64 only"; exit 1; }
ok "preflight: ${PRETTY_NAME:-linux} $(uname -m)"

EXISTING=0
systemctl is-active --quiet xray 2>/dev/null && EXISTING=1
if [[ $EXISTING == 1 ]]; then
  warn "existing xray setup detected — configs will NOT be overwritten"
  warn "(use --configs to force-install mysetup/* configs)"
fi
[[ $AUTO == 0 ]] && { ask "continue?" || { echo "aborted."; exit 0; }; }

BK=/root/backups/doty-panel-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK"

#--- 1. panel binaries & managers ---
bar; echo -e "${B}[1/6] panel binaries + account managers${N}"
install -m 755 doty-bin/doty-panel /usr/local/sbin/menu
ok "panel -> /usr/local/sbin/menu"
for m in ssh vless vmess trojan dns domain socks status update log netguard iptools port; do
  install -m 755 "doty-bin/$m.sh" "/usr/local/bin/$m" && ok "manager: $m"
done
mv /usr/local/bin/ssh /usr/local/bin/doty-ssh   # don't shadow OpenSSH
install -m 755 doty-bin/zivpn.sh /usr/local/bin/zivpn-mgr
[[ -f /usr/bin/expiry ]] || install -m 755 doty-bin/expiry.sh /usr/bin/expiry
# launcher
printf '#!/bin/bash\nexec /usr/local/sbin/menu "$@"\n' > /usr/local/bin/doty
chmod +x /usr/local/bin/doty
ok "launcher: doty"

#--- 2. ssh wrapper (bare ssh -> manager, args -> OpenSSH) ---
bar; echo -e "${B}[2/6] ssh wrapper (panel [01] fix)${N}"
[[ -f /usr/bin/ssh.openssh ]] || cp -a /usr/bin/ssh /usr/bin/ssh.openssh
cp /usr/bin/ssh "$BK/ssh.orig"
cat > /usr/bin/ssh <<'W'
#!/bin/bash
if [[ $# -eq 0 ]]; then exec /usr/local/bin/doty-ssh; else exec /usr/bin/ssh.openssh "$@"; fi
W
chmod +x /usr/bin/ssh
ok "wrapper installed (original at /usr/bin/ssh.openssh)"

#--- 3. SSH/WS services (edu :700, proxy :2080 -> dropbear:6422) ---
bar; echo -e "${B}[3/6] SSH-WebSocket services${N}"
DBPORT=$(grep -m1 '^DROPBEAR_PORT' /etc/default/dropbear 2>/dev/null | cut -d= -f2)
DBPORT=${DBPORT:-6422}
install -m 755 mysetup/ssh-ws/ws /usr/bin/ws
sed -i "s/DEFAULT_HOST = '127.0.0.1:[0-9]*'/DEFAULT_HOST = '127.0.0.1:$DBPORT'/" /usr/bin/ws
install -m 755 mysetup/ssh-ws/ws-com /usr/bin/ws-com 2>/dev/null || true
printf 'verbose: 0\nlisten:\n- target_host: 127.0.0.1\n  target_port: %s\n  listen_port: 2080\n' "$DBPORT" > /usr/bin/config.yaml
install -m 644 mysetup/ssh-ws/edu.service mysetup/ssh-ws/proxy.service mysetup/udpgw.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now edu proxy udpgw &>/dev/null
ok "edu :700 + proxy :2080 + udpgw :7800 -> dropbear :$DBPORT"

#--- 4. network hardening (non-destructive) ---
bar; echo -e "${B}[4/6] sysctls + log guards${N}"
[[ -f /etc/sysctl.d/99-udp-tuning.conf ]] || {
  printf 'net.core.rmem_max = 134217728\nnet.core.wmem_max = 134217728\nnet.core.netdev_max_backlog = 32768\n' > /etc/sysctl.d/99-udp-tuning.conf
  sysctl --system &>/dev/null; ok "udp buffers tuned"; }
[[ -f /etc/rsyslog.d/10-udp-custom-drop.conf ]] || {
  printf 'if $programname == "udp-custom" then stop\n' > /etc/rsyslog.d/10-udp-custom-drop.conf
  systemctl restart rsyslog 2>/dev/null; ok "udp-custom log flood blocked"; }
# OCI DNS guard: only if public DNS is dead AND iptables exists (nft boxes skip).
# On non-OCI hosts (Linode etc.) public DNS normally works — nothing to do.
if have dig && ! timeout 3 dig +short @8.8.8.8 example.com &>/dev/null; then
  if have iptables; then
    iptables -t nat -C OUTPUT -p udp --dport 53 ! -d 169.254.169.254 -j DNAT --to 169.254.169.254:53 2>/dev/null || {
      iptables -t nat -A OUTPUT -p udp --dport 53 ! -d 169.254.169.254 -j DNAT --to 169.254.169.254:53
      iptables -t nat -A OUTPUT -p tcp --dport 53 ! -d 169.254.169.254 -j DNAT --to 169.254.169.254:53
      have netfilter-persistent && netfilter-persistent save &>/dev/null
      ok "OCI DNS redirect installed"; }
  else warn "public DNS dead but no iptables — set resolvers manually"; fi
else ok "public DNS reachable — no DNS guard needed"; fi

#--- 5. configs (opt-in) ---
bar; echo -e "${B}[5/6] server configs${N}"
if [[ $WITH_CONFIGS == 1 || $EXISTING == 0 ]]; then
  for c in xray-config.json:/etc/xray/config.json nginx-doty.conf:/etc/nginx/conf.d/doty.conf \
           tuic-config.json:/etc/tuic/config.json zivpn-config.json:/etc/zivpn/config.json \
           sslh-defaults:/etc/default/sslh udp-custom-config.json:/root/udp/config.json; do
    src=${c%%:*}; dst=${c##*:}
    [[ -f $dst ]] && cp "$dst" "$BK/$(basename $dst).bak"
    mkdir -p "$(dirname "$dst")"; cp "mysetup/$src" "$dst"; ok "installed $dst"
  done
  # xray-install drop-in reads /usr/local/etc/xray/config.json — keep it
  # symlinked at the panel-managed /etc/xray/config.json so edits stay live.
  if [[ ! -L /usr/local/etc/xray/config.json ]]; then
    [[ -f /usr/local/etc/xray/config.json ]] && cp /usr/local/etc/xray/config.json "$BK/xray-live.bak"
    ln -sf /etc/xray/config.json /usr/local/etc/xray/config.json && ok "xray live config symlinked"
  else ok "xray live config symlink present"; fi
  systemctl restart xray nginx sslh 2>/dev/null
else
  warn "skipped (existing setup kept — rerun with --configs to install mysetup/*)"
fi

#--- 6. panel fixups (always safe, idempotent) ---
bar; echo -e "${B}[6/6] panel fixups${N}"
[[ -f /etc/version ]] || { echo "1.4.3-doty" > /etc/version; ok "version file"; }
[[ -f /etc/xray/port_info ]] || {
  printf 'VLESS CUSTOM TLS: 443 (universal TLS port)\nVLESS CUSTOM NTLS: 80 (nginx NTLS)\nVMESS CUSTOM TLS: 443 (universal TLS port)\nVMESS CUSTOM NTLS: 80 (nginx NTLS)\n' > /etc/xray/port_info
  ok "port_info (custom-path display)"; }
install -m 755 mysetup/doty-linkfix /usr/local/bin/doty-linkfix
for p in vless vmess trojan; do
  if grep -q doty-linkfix "/usr/local/bin/$p" 2>/dev/null; then
    ok "linkfix wrapper present: $p"
  else
    # step [1/6] may have overwritten a wrapper with the raw binary — re-wrap
    if [[ ! -f /usr/local/bin/$p.bin ]]; then
      mv "/usr/local/bin/$p" "/usr/local/bin/$p.bin"
    fi
    sed "s/REAL=.*/REAL=$p/" mysetup/manager-wrapper-template.sh > "/usr/local/bin/$p"
    chmod +x "/usr/local/bin/$p" && ok "linkfix wrapper: $p"
  fi
done

#--- summary ---
bar; echo -e "${G}        DONE — panel ready${N}"; bar
echo -e "  launch panel:  ${Y}doty${N} (or ${Y}menu${N})"
echo -e "  managers:      ssh(mgr) vless vmess trojan dns domain socks status"
echo -e "  SSH/WS:        edu :700 · proxy :2080 · udpgw :7800"
echo -e "  backups:       $BK"
bar
