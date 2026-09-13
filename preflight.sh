#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -m)" == riscv64 ]] || { echo "ERROR: 仅支持 riscv64" >&2; exit 1; }

model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
echo "Architecture: $(uname -m)"
echo "Board model: ${model:-unknown}"
echo "Current kernel: $(uname -r)"

if [[ -n "$model" ]] && [[ ! "$model" =~ [Kk]3|SpacemiT|spacemit ]]; then
  echo "ERROR: 设备型号不像已验证的 K3，停止安装" >&2
  exit 1
fi

command -v sha256sum >/dev/null || { echo "ERROR: 缺少 sha256sum" >&2; exit 1; }
command -v update-grub >/dev/null || echo "WARNING: 未找到 update-grub，请确认设备引导方式"
echo "Preflight: PASS"
