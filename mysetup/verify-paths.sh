#!/bin/bash
# Full protocol test: local xray client per path, curl through it
# NOTE: xray >= 26 removed the "allowInsecure" client option. TLS tests rely on
# the OS trust store instead — trust the (self-signed) server cert first:
#   cp /etc/xray/xray.crt /usr/local/share/ca-certificates/xray-selfsigned.crt \
#   && update-ca-certificates
VL=<VLESS_UUID>
VM=<VMESS_UUID>
# expected exit IP: direct lookup (server may exit via IPv4 or IPv6)
EXPECT=$(timeout 8 curl -s https://ifconfig.me 2>/dev/null)
[ -z "$EXPECT" ] && EXPECT="<SERVER_IP>"
mkdir -p /tmp/opencode
i=0
run_test() {  # name proto net port path security
  local name=$1 proto=$2 net=$3 port=$4 path=$5 sec=$6
  i=$((i+1)); local sport=$((19500+i)) cfg=/tmp/opencode/vt-$i.json
  local id=$VL; [ "$proto" = vmess ] && id=$VM
  local user
  [ "$proto" = vless ] && user="{\"id\":\"$id\",\"encryption\":\"none\"}" \
                       || user="{\"id\":\"$id\",\"alterId\":0,\"security\":\"auto\"}"
  local ss=""
  case $net in
    ws)          ss="\"network\":\"ws\",\"wsSettings\":{\"path\":\"$path\"}";;
    httpupgrade) ss="\"network\":\"httpupgrade\",\"httpupgradeSettings\":{\"path\":\"$path\",\"host\":\"127.0.0.1\"}";;
    grpc)        ss="\"network\":\"grpc\",\"grpcSettings\":{\"serviceName\":\"$path\"}";;
    xhttp)       ss="\"network\":\"xhttp\",\"xhttpSettings\":{\"path\":\"$path\",\"host\":\"127.0.0.1\"}";;
    tcp)         ss="\"network\":\"tcp\"";;
  esac
  [ "$sec" = tls ] && ss="$ss,\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"opbless.duckdns.org\"}" \
                   || ss="$ss,\"security\":\"none\""
  cat > $cfg <<EOF
{"log":{"loglevel":"none"},
 "inbounds":[{"listen":"127.0.0.1","port":$sport,"protocol":"socks","settings":{"udp":true}}],
 "outbounds":[{"protocol":"$proto","settings":{"vnext":[{"address":"127.0.0.1","port":$port,"users":[$user]}]},"streamSettings":{$ss}}]}
EOF
  /usr/local/bin/xray run -c $cfg &>/dev/null & local pid=$!
  sleep 1.5
  local out=$(timeout 8 curl -s --socks5-hostname 127.0.0.1:$sport https://ifconfig.me 2>/dev/null)
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if [ "$out" = "$EXPECT" ]; then echo "PASS  $name"; else echo "FAIL  $name (got:'$out' want:'$EXPECT')"; fi
  rm -f $cfg
}
run_test vless-ws-444-tls        vless ws  444  /vless tls
run_test vless-ws-88             vless ws  88   /vless none
run_test vless-ws-2086           vless ws  2086 /vless none
run_test vless-ws-2087-tls       vless ws  2087 /vless tls
run_test vless-httpupgrade-444   vless httpupgrade 444 /hvless tls
run_test vless-grpc-444          vless grpc 444 vless-grpc tls
run_test vless-xhttp-444         vless xhttp 444 /xvless tls
run_test vless-direct-443        vless tcp 443 - tls
run_test vmess-ws-444-tls        vmess ws  444  /vmess tls
run_test vmess-ws-88             vmess ws  88   /vmess none
run_test vmess-ws-2082           vmess ws  2082 /vmess none
run_test vmess-ws-2083-tls       vmess ws  2083 /vmess tls
run_test vmess-httpupgrade-444   vmess httpupgrade 444 /hvmess tls
run_test vmess-grpc-444          vmess grpc 444 vmess-grpc tls
run_test vmess-xhttp-444         vmess xhttp 444 /xvmess tls
