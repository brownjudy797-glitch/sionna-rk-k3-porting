#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "ERROR: 请使用 sudo" >&2; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-}"
PAYLOAD="$ROOT/cn5g-payload.tar.zst"
TEMP_DIR=""
trap '[[ -n "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"' EXIT

HOST_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
WAN_IF="$(ip -4 route show default | awk 'NR==1{print $5}')"
UPF_N3_IP=192.168.71.134
GNB_N3_IP=192.168.71.140
UE_SUBNET=12.1.1.0/24
UE_GATEWAY=12.1.1.1
INSTALL_PREFIX=/opt/sionna-rk-k3/cn5g
CONFIG_DIR=/etc/sionna-rk-k3/cn5g
STATE_DIR=/var/lib/sionna-rk-k3/cn5g

if [[ -n "$ENV_FILE" ]]; then
  [[ -f "$ENV_FILE" ]] || { echo "ERROR: 找不到 $ENV_FILE" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

[[ -n "$HOST_IP" && -n "$WAN_IF" ]] || { echo "ERROR: 无法确定 HOST_IP/WAN_IF" >&2; exit 1; }
ip link show "$WAN_IF" >/dev/null || { echo "ERROR: 网卡不存在：$WAN_IF" >&2; exit 1; }
[[ -s "$PAYLOAD" ]] || { echo "ERROR: 缺少 cn5g-payload.tar.zst" >&2; exit 1; }

TEMP_DIR="$(mktemp -d)"
tar --zstd -xf "$PAYLOAD" -C "$TEMP_DIR"

if compgen -G "$ROOT/packages/*.deb" >/dev/null; then
  dpkg -i "$ROOT"/packages/*.deb || apt-get -f install -y --no-download
fi

for cmd in ip iptables mariadb; do
  command -v "$cmd" >/dev/null || { echo "ERROR: 缺少依赖命令 $cmd" >&2; exit 1; }
done

install -d "$INSTALL_PREFIX" "$CONFIG_DIR" "$STATE_DIR/logs" "$STATE_DIR/run"
cp -a "$TEMP_DIR/bin" "$TEMP_DIR/lib" "$ROOT/scripts" "$INSTALL_PREFIX/"
install -d "$INSTALL_PREFIX/database"
cp -a "$TEMP_DIR/database/." "$INSTALL_PREFIX/database/"
cp -a "$ROOT/database/." "$INSTALL_PREFIX/database/"
cp -a "$TEMP_DIR/config/." "$CONFIG_DIR/"

for config in "$CONFIG_DIR"/*; do
  [[ -f "$config" ]] || continue
  sed -i \
    -e "s/10\.17\.116\.247/$HOST_IP/g" \
    -e "s/wlP4p1s0/$WAN_IF/g" \
    -e "s/192\.168\.71\.134/$UPF_N3_IP/g" \
    -e "s/192\.168\.71\.140/$GNB_N3_IP/g" "$config"
done

cat >"$CONFIG_DIR/runtime.env" <<EOF
HOST_IP=$HOST_IP
WAN_IF=$WAN_IF
UPF_N3_IP=$UPF_N3_IP
GNB_N3_IP=$GNB_N3_IP
UE_SUBNET=$UE_SUBNET
UE_GATEWAY=$UE_GATEWAY
INSTALL_PREFIX=$INSTALL_PREFIX
CONFIG_DIR=$CONFIG_DIR
STATE_DIR=$STATE_DIR
EOF

systemctl enable --now mariadb
mariadb <"$INSTALL_PREFIX/database/init-oai-db.sql"
mariadb oai_db <"$INSTALL_PREFIX/database/oai_db1.sql"

echo "CN5G 已安装：$INSTALL_PREFIX"
echo "生效配置：$CONFIG_DIR（HOST_IP=$HOST_IP, WAN_IF=$WAN_IF）"
echo "下一步：sudo $INSTALL_PREFIX/scripts/start-cn5g.sh"
