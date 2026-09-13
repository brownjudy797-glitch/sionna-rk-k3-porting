#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
STATE_DIR=/var/lib/sionna-rk-k3/cn5g

for name in amf smf upf; do
  pidfile="$STATE_DIR/run/$name.pid"
  if [[ -s "$pidfile" ]]; then
    pid="$(cat "$pidfile")"
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$pidfile"
  fi
done

ip link delete tun0 2>/dev/null || true
ip link delete cn5g-upf 2>/dev/null || true
ip link delete cn5g-gnb 2>/dev/null || true
echo "CN5G 已停止"
