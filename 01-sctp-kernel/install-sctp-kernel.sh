#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVER=6.18.3-k3-sctp+
BACKUP="/boot/k3-sctp-backup-$(date +%Y%m%d-%H%M%S)"

[[ "$(uname -m)" == riscv64 ]] || { echo "ERROR: 架构不是 riscv64" >&2; exit 1; }
[[ -s "$ROOT/kernel-payload.tar.zst" ]] || { echo "ERROR: 缺少 kernel-payload.tar.zst" >&2; exit 1; }
PAYLOAD_LIST="$(mktemp)"
trap 'rm -f "$PAYLOAD_LIST"' EXIT
tar --zstd -tf "$ROOT/kernel-payload.tar.zst" > "$PAYLOAD_LIST" \
  || { echo "ERROR: 无法读取内核载荷，文件可能损坏或不完整" >&2; exit 1; }
grep -Fxq "boot/vmlinuz-$KVER" "$PAYLOAD_LIST" \
  || { echo "ERROR: 内核载荷缺少 boot/vmlinuz-$KVER" >&2; exit 1; }
grep -Fq "lib/modules/$KVER/" "$PAYLOAD_LIST" \
  || { echo "ERROR: 内核载荷缺少 lib/modules/$KVER/" >&2; exit 1; }

mkdir -p "$BACKUP"
cp -a /boot/boot.scr /boot/grub/grub.cfg "$BACKUP/" 2>/dev/null || true

tar --zstd -xf "$ROOT/kernel-payload.tar.zst" -C /
depmod "$KVER"

if [[ -s "$ROOT/boot.scr.k3-sctp" ]]; then
  cp -a /boot/boot.scr "$BACKUP/boot.scr.before-install" 2>/dev/null || true
  cp -a "$ROOT/boot.scr.k3-sctp" /boot/boot.scr
fi
update-grub

echo "SCTP 内核已安装，原引导文件备份在：$BACKUP"
echo "现在执行 sudo reboot；重启后运行 uname -r 和 grep -i sctp /proc/net/protocols"
