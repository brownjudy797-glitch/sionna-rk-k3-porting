#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -s "$ROOT/boot.scr.stock" ]] || { echo "ERROR: 安装包没有原厂 boot.scr" >&2; exit 1; }
cp -a /boot/boot.scr "/boot/boot.scr.before-rollback-$(date +%Y%m%d-%H%M%S)"
cp -a "$ROOT/boot.scr.stock" /boot/boot.scr
update-grub
echo "已恢复原厂内核引导脚本。请重启；没有删除 SCTP 内核文件。"
