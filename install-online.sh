#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="${K3_PORTING_REPOSITORY:-brownjudy797-glitch/sionna-rk-k3-porting}"
RELEASE_BASE="https://github.com/$REPOSITORY/releases/latest/download"
MODE="${1:-}"

die() { echo "ERROR: $*" >&2; exit 1; }
download() {
  local name="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  curl -fL --retry 3 --connect-timeout 20 "$RELEASE_BASE/$name" -o "$dest"
  curl -fL --retry 3 --connect-timeout 20 "$RELEASE_BASE/$name.sha256" -o "$dest.sha256"
  local expected actual
  expected="$(awk 'NR==1 {print $1}' "$dest.sha256")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "SHA-256 文件格式错误：$name.sha256"
  actual="$(sha256sum "$dest" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "SHA-256 校验失败：$name"
  echo "$name: OK"
}

[[ "$(uname -m)" == riscv64 ]] || die "仅支持 riscv64 K3"

case "$MODE" in
  check)
    echo "Architecture: $(uname -m)"
    echo "Kernel: $(uname -r)"
    if grep -qi sctp /proc/net/protocols 2>/dev/null || sudo modprobe sctp 2>/dev/null; then
      echo "SCTP: available（无需更换内核）"
    else
      echo "SCTP: unavailable（需要安装发布版 SCTP 内核）"
    fi
    ;;
  kernel)
    if grep -qi sctp /proc/net/protocols 2>/dev/null || sudo modprobe sctp 2>/dev/null; then
      echo "当前内核已经支持 SCTP，跳过内核下载和安装。"
      exit 0
    fi
    download k3-sctp-kernel-6.18.3.tar.zst "$ROOT/01-sctp-kernel/kernel-payload.tar.zst"
    sudo "$ROOT/install.sh" kernel
    echo "请执行 sudo reboot，重启后再安装 CN5G。"
    ;;
  cn5g)
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl zstd iproute2 iptables mariadb-server
    download cn5g-riscv64-v2.1.0.tar.zst "$ROOT/02-cn5g/cn5g-payload.tar.zst"
    sudo "$ROOT/install.sh" cn5g "${2:-}"
    ;;
  b200)
    sudo "$ROOT/install.sh" b200 "${2:-$HOME/sionna-rk}"
    ;;
  *)
    echo "Usage: $0 check"
    echo "       $0 kernel"
    echo "       $0 cn5g [config.env]"
    echo "       $0 b200 [sionna-rk-root]"
    exit 1
    ;;
esac
