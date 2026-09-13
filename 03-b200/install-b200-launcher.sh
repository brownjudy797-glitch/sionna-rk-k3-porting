#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${SUDO_USER:-ubuntu}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
SIONNA_ROOT="${1:-$TARGET_HOME/sionna-rk}"

[[ -d "$SIONNA_ROOT" ]] || { echo "ERROR: 找不到 Sionna-RK：$SIONNA_ROOT" >&2; exit 1; }
[[ -x "$SIONNA_ROOT/ext/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem" ]] || {
  echo "ERROR: 找不到已编译的 nr-softmodem；B200 启动器不包含 OAI RAN 二进制" >&2
  exit 1
}
[[ -x /opt/sionna-rk-k3/cn5g/scripts/start-cn5g.sh ]] || {
  echo "ERROR: 请先执行 sudo ./install.sh cn5g" >&2
  exit 1
}

install -m 0755 "$ROOT/scripts/run-k3-b200.sh" "$SIONNA_ROOT/scripts/run-k3-b200.sh"
install -d -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$SIONNA_ROOT/config/b200"
install -m 0644 "$ROOT/b200.env.example" "$SIONNA_ROOT/config/b200/.env.k3-example"
chown "$TARGET_USER:$(id -gn "$TARGET_USER")" \
  "$SIONNA_ROOT/scripts/run-k3-b200.sh" \
  "$SIONNA_ROOT/config/b200/.env.k3-example"

echo "B200 启动器已安装：$SIONNA_ROOT/scripts/run-k3-b200.sh"
echo "配置示例：$SIONNA_ROOT/config/b200/.env.k3-example"
echo "下一步请把配置项合并到 $SIONNA_ROOT/config/b200/.env"

