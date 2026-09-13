#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-}"

case "$mode" in
  kernel)
    "$ROOT/preflight.sh"
    exec "$ROOT/01-sctp-kernel/install-sctp-kernel.sh"
    ;;
  cn5g)
    "$ROOT/preflight.sh"
    exec "$ROOT/02-cn5g/install-cn5g.sh" "${2:-}"
    ;;
  b200)
    "$ROOT/preflight.sh"
    exec bash "$ROOT/03-b200/install-b200-launcher.sh" "${2:-}"
    ;;
  *)
    echo "Usage: sudo $0 kernel"
    echo "       sudo $0 cn5g [config.env]"
    echo "       sudo $0 b200 [sionna-rk-root]"
    exit 1
    ;;
esac
