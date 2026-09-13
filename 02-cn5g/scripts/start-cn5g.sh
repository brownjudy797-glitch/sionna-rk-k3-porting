#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR=/etc/sionna-rk-k3/cn5g
STATE_DIR=/var/lib/sionna-rk-k3/cn5g
source "$CONFIG_DIR/runtime.env"
LIB="$PREFIX/lib/private:$PREFIX/lib/boost:$PREFIX/lib/local:$PREFIX/lib/system"

mkdir -p "$STATE_DIR/logs" "$STATE_DIR/run"
systemctl is-active --quiet mariadb || systemctl start mariadb

for name in upf smf amf; do
  if [[ -s "$STATE_DIR/run/$name.pid" ]] && kill -0 "$(cat "$STATE_DIR/run/$name.pid")" 2>/dev/null; then
    echo "ERROR: $name 已运行" >&2
    exit 1
  fi
done

ip link delete tun0 2>/dev/null || true
for spec in "cn5g-upf $UPF_N3_IP/32" "cn5g-gnb $GNB_N3_IP/32"; do
  read -r dev addr <<<"$spec"
  ip link show "$dev" >/dev/null 2>&1 || ip link add "$dev" type dummy
  ip address replace "$addr" dev "$dev"
  ip link set "$dev" up
done

nohup env LD_LIBRARY_PATH="$LIB" "$PREFIX/bin/upf" -c "$CONFIG_DIR/upf.yaml" >"$STATE_DIR/logs/upf.log" 2>&1 </dev/null &
echo $! >"$STATE_DIR/run/upf.pid"
sleep 2
nohup env LD_LIBRARY_PATH="$LIB" "$PREFIX/bin/smf" -c "$CONFIG_DIR/smf.yaml" -o >"$STATE_DIR/logs/smf.log" 2>&1 </dev/null &
echo $! >"$STATE_DIR/run/smf.pid"
sleep 2
nohup env LD_LIBRARY_PATH="$LIB" "$PREFIX/bin/amf" -c "$CONFIG_DIR/amf.yaml" -o >"$STATE_DIR/logs/amf.log" 2>&1 </dev/null &
echo $! >"$STATE_DIR/run/amf.pid"
sleep 3

"$PREFIX/scripts/status-cn5g.sh"
