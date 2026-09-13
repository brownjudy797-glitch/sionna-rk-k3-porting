#!/usr/bin/env bash
set -u

PREFIX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR=/var/lib/sionna-rk-k3/cn5g
failed=0

for name in upf smf amf; do
  pidfile="$STATE_DIR/run/$name.pid"
  if [[ -s "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "$name: running (PID $(cat "$pidfile"))"
  else
    echo "$name: NOT RUNNING"
    failed=1
  fi
done

grep -q 'N4 ASSOCIATION SETUP RESPONSE' "$STATE_DIR/logs/smf.log" 2>/dev/null \
  && echo 'N4: associated' || { echo 'N4: not observed'; failed=1; }
ss -lnp --sctp 2>/dev/null | grep -q ':38412' \
  && echo 'N2/SCTP 38412: listening' || { echo 'N2/SCTP 38412: not listening'; failed=1; }

exit "$failed"
