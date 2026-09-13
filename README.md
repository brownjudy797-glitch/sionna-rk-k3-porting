# Sionna-RK K3 离线移植包

在线安装仓库：`https://github.com/brownjudy797-glitch/sionna-rk-k3-porting`

在线安装时先执行：

```bash
git clone https://github.com/brownjudy797-glitch/sionna-rk-k3-porting.git
cd sionna-rk-k3-porting
./install-online.sh check
```

当前内核已经支持 SCTP 时直接安装 CN5G；否则先安装内核并重启：

```bash
./install-online.sh kernel
sudo reboot
```

安装 CN5G：

```bash
cd sionna-rk-k3-porting
./install-online.sh cn5g
```

公开发布包不包含测试 UE 的 IMSI、K 或 OPc。需要连接软件 UE 或真实 UE 时，必须在目标板本地配置用户数据。

---

适用范围：与源设备相同型号的进迭时空 K3 Pico-ITX、Ubuntu riscv64。

本安装包分为三个部分：

1. `01-sctp-kernel`：安装已经验证的 `6.18.3-k3-sctp+` 内核与模块；
2. `02-cn5g`：安装原生 RISC-V AMF、SMF、UPF、运行库、配置和数据库。
3. `03-b200`：把 K3 原生 B200/B210 gNB 启动器和配置示例安装到现有 Sionna-RK。

它不会复制源设备的 Tailscale 身份、SSH 主机密钥、`machine-id` 或完整数据库目录。

## 第一步：校验安装包

```bash
cd sionna-rk-k3-offline-kit
sha256sum -c checksums.sha256
./preflight.sh
```

只有架构显示 `riscv64`、设备型号检查通过且校验无错误时才继续。

## 第二步：安装 SCTP 内核

```bash
sudo ./install.sh kernel
sudo reboot
```

重启后检查：

```bash
uname -r
grep -i sctp /proc/net/protocols
modinfo sctp
```

预期内核为 `6.18.3-k3-sctp+`，并能看到 SCTP/SCTPv6。安装程序保留原内核，出现启动问题时可从 GRUB 的高级选项选择原内核，或运行 `01-sctp-kernel/rollback-kernel.sh`。

## 第三步：配置并安装 CN5G

安装程序自动读取默认出口网卡和 IPv4。也可以先复制并修改配置：

```bash
cp 02-cn5g/config.env.example config.env
nano config.env
sudo ./install.sh cn5g ./config.env
```

不提供配置文件时：

```bash
sudo ./install.sh cn5g
```

默认安装位置：

- 程序和私有库：`/opt/sionna-rk-k3/cn5g`；
- 生效配置：`/etc/sionna-rk-k3/cn5g`；
- 日志与 PID：`/var/lib/sionna-rk-k3/cn5g`。

## 第四步：启动和检查

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/start-cn5g.sh
sudo /opt/sionna-rk-k3/cn5g/scripts/status-cn5g.sh
```

停止：

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/stop-cn5g.sh
```

验收至少包括：MariaDB 正常、AMF/SMF/UPF 均运行、SCTP 38412 监听、N4 PFCP association 建立。

## 第五步：安装 B200/B210 启动器（可选）

目标板必须已经编译出 Sionna-RK 的 `nr-softmodem`。安装启动器：

```bash
sudo ./install.sh b200 "$HOME/sionna-rk"
```

按照 `config/b200/.env.k3-example` 修改 `config/b200/.env` 后执行：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh check
./scripts/run-k3-b200.sh start
```

## 源码移植记录

源码版本、补丁原因、依赖 ABI 和验证过程见 `docs/CN5G_SCTP_PORTING_GUIDE.md`。离线安装包用于同型号、同系统基线设备；不同 Ubuntu 版本必须重新核对动态库 ABI。
