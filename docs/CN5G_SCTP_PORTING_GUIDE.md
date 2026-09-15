# K3 SCTP 内核与 OAI CN5G RISC-V 移植说明

## 1. 移植目标

目标平台为 K3 Pico-ITX、RV64。核心网采用精简的非 NRF 结构：MariaDB、OAI AMF、OAI SMF、OAI UPF。gNB 经 N2/SCTP 接入 AMF，经 N3/GTP-U 接入 UPF；SMF 与 UPF 使用 N4/PFCP。

## 2. SCTP 内核

基线内核为 `6.18.3-7-spacemit-generic`。移植内核版本标记为 `6.18.3-k3-sctp+`，SCTP 以模块形式提供：

```text
/lib/modules/6.18.3-k3-sctp+/kernel/net/sctp/sctp.ko.zst
```

安装包同时保存内核映像、initramfs、配置、System.map、K3 DTB 和完整模块树。K3 的 U-Boot `boot.scr` 固定 `fk_kvers`，因此只复制内核文件并不足以启动；安装脚本会备份并切换对应的 `boot.scr`，然后执行 `update-grub`。原厂内核及其文件不会删除。

验收：

```bash
uname -r
grep -i sctp /proc/net/protocols
modinfo sctp
ss -lnp --sctp
```

## 3. CN5G 源码版本与架构修改

- Sionna-RK：`0abdce3ff7f5840d64b783632eb419ea6bf54ae5`；
- OAI CN5G federation：`6cd16eb65b3f1f92ccc330dfe6f0bacf99372682`；
- AMF、SMF、UPF：`v2.1.0`；
- 目标：RISC-V ELF64 LP64D，不包含 NRF。

主要适配点：

1. 将构建脚本的架构识别扩展到 `riscv64`；
2. `-msse4.2` 仅在 x86 启用，RISC-V 分支不传入 x86 SIMD 参数；
3. 为 GCC 补齐源码对 `<cstdint>`、`<limits>`、`<system_error>` 等头文件的显式依赖；
4. 使用隔离的 Boost 1.83，避免系统 Boost 1.90 与旧版 nghttp2-asio ABI 混用；
5. 使用 fmt 9、固定版本 Pistache 和与 UPF 匹配的 Folly；
6. 为 UPF eBPF 构建补充 RISC-V 多架构头路径，并去除 eBPF 源对用户态头文件的错误依赖；
7. 私有运行库通过 `LD_LIBRARY_PATH` 加载，不覆盖系统 Boost/UHD/GNU Radio。

## 4. 已完成的功能验证

- AMF N2/SCTP 监听和 gNB NG Setup；
- SMF–UPF N4/PFCP association；
- UE 注册、5G-AKA、Security Mode、Registration Accept；
- PDU Session 建立，UE 获得 `12.1.1.130`；
- UPF 上下行 PDR/FAR 和 N3 GTP-U；
- UE 到 UPF、UE 到公网的双向转发；
- gNB、UE 与核心网的一键启停回归。

## 5. 为什么不复制完整系统

完整磁盘镜像会同时复制分区 UUID、SSH 主机密钥、Tailscale 节点身份、网络配置和数据库运行状态。本安装包只迁移经过验证的内核、组件、依赖、配置模板和数据库初始化 SQL，更容易审计和回退。

## 6. 限制

- 仅保证相同 K3 型号与相同 Ubuntu 系统基线；
- 配置中的出口网卡和主机地址必须针对目标板重新生成；
- B210 实时空口仍受 K3 实时性和 UHD overflow 影响，这与 CN5G 功能移植是否成功是两个独立验收项；
- 若升级系统 glibc、OpenSSL、MariaDB 或核心网源码，需要重新执行 `ldd`、SCTP/N4/N2 和 PDU Session 回归。

## 7. 在线安装（推荐）

目标 K3 能访问 GitHub 时，优先使用本节。安装程序会从公开 Release 下载经过校验的 RISC-V 安装包，不需要复制整个离线目录。

### 7.1 下载安装仓库

```bash
cd "$HOME"
git clone https://github.com/brownjudy797-glitch/sionna-rk-k3-porting.git
cd sionna-rk-k3-porting
```

如果此前已经下载过，只需更新：

```bash
cd "$HOME/sionna-rk-k3-porting"
git pull --ff-only origin main
git rev-parse --short HEAD
```

内核载荷校验误报修复包含在提交 `caa1be3` 及后续版本中。若输出的提交早于该版本，应先完成更新再安装。

### 7.2 检查平台和 SCTP

```bash
./install-online.sh check
```

若结果显示 `SCTP is already available; no kernel change is needed.`，不要重复安装内核，直接进入下一步。

只有 SCTP 不可用时才执行：

```bash
./install-online.sh kernel
sudo reboot
```

安装程序会先校验 Release 的 SHA-256，再完整读取压缩包目录，并确认以下两部分同时存在：

```text
boot/vmlinuz-6.18.3-k3-sctp+
lib/modules/6.18.3-k3-sctp+/
```

若旧版脚本显示 `ERROR: 内核载荷不完整`，不要删除载荷或重启。先确认脚本是否已经更新：

```bash
grep -n PAYLOAD_LIST 01-sctp-kernel/install-sctp-kernel.sh
```

没有输出表示仍是旧脚本，执行：

```bash
git pull --ff-only origin main
```

需要人工复核已下载载荷时执行：

```bash
tar --zstd -tf 01-sctp-kernel/kernel-payload.tar.zst > /tmp/k3-kernel-files.txt
grep -Fx 'boot/vmlinuz-6.18.3-k3-sctp+' /tmp/k3-kernel-files.txt
grep -F 'lib/modules/6.18.3-k3-sctp+/' /tmp/k3-kernel-files.txt | head
```

两条检查都有输出才表示内核映像和模块树均存在。修正版脚本避免了旧版 `pipefail` 与 `grep -q` 组合造成的误报。

重启后重新进入仓库并检查：

```bash
cd "$HOME/sionna-rk-k3-porting"
./install-online.sh check
```

### 7.3 在线安装 CN5G

使用自动检测到的本机网络参数安装：

```bash
./install-online.sh cn5g
```

需要明确指定地址和出口网卡时，先生成本机配置：

```bash
cp 02-cn5g/config.env.example config.env
nano config.env
./install-online.sh cn5g ./config.env
```

公开安装包不包含实验室 UE 的 IMSI、K、OPc 等鉴权数据。真实 UE 的用户信息必须在本机单独配置，不要提交到公开仓库。

### 7.4 安装 B200/B210 启动脚本

确认 `$HOME/sionna-rk` 中的 OAI RAN 已经编译完成后执行：

```bash
cd "$HOME/sionna-rk-k3-porting"
./install-online.sh b200 "$HOME/sionna-rk"
```

脚本会安装到 `$HOME/sionna-rk/scripts/run-k3-b200.sh`。完整启动方法见第 9 节。

### 7.5 下载量说明

- K3 已支持 SCTP 时，只需下载约 128 MB 的 CN5G 包；
- 只有缺少 SCTP 时，才额外下载约 875 MB 的内核包；
- 在线安装仍会核对 Release 中发布的 SHA-256，校验失败会停止安装。

## 8. 在另一块 K3 上离线安装

以下命令全部在目标 K3 上执行。不要跳过校验和 SCTP 重启验收。

### 8.1 找到 USB 存储设备

插入存有安装包的 USB 设备，然后执行：

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,TRAN
findmnt -t exfat,vfat,ext4,ntfs3
```

本次制作安装包时，USB 挂载目录是：

```text
/run/media/ubuntu/9EF6-0F3A
```

目标 K3 的挂载目录可能不同，应以 `lsblk` 的实际输出为准。进入包含以下两个文件的目录：

```text
sionna-rk-k3-offline-kit-20260911.tar.zst
sionna-rk-k3-offline-kit-20260911.tar.zst.sha256
```

例如：

```bash
cd /run/media/ubuntu/9EF6-0F3A/sionna-rk-k3-offline-kit
ls -lh
```

### 8.2 校验并复制到目标 K3

先校验 USB 上的归档：

```bash
sha256sum -c sionna-rk-k3-offline-kit-20260911.tar.zst.sha256
```

必须显示：

```text
sionna-rk-k3-offline-kit-20260911.tar.zst: OK
```

复制到目标 K3。复制过程不会修改 USB 内的文件：

```bash
mkdir -p "$HOME/k3-offline-install"
cp sionna-rk-k3-offline-kit-20260911.tar.zst* "$HOME/k3-offline-install/"
sync
cd "$HOME/k3-offline-install"
sha256sum -c sionna-rk-k3-offline-kit-20260911.tar.zst.sha256
```

第二次校验也必须显示 `OK`。

### 8.3 解压并执行安装前检查

```bash
cd "$HOME/k3-offline-install"
tar --zstd -xf sionna-rk-k3-offline-kit-20260911.tar.zst
cd sionna-rk-k3-offline-kit
sha256sum -c checksums.sha256
./preflight.sh
```

验收要求：

- 架构为 `riscv64`；
- 板型为 K3/SpacemiT；
- 当前内核能够正常读取；
- 所有内部文件校验显示 `OK`；
- `Preflight: PASS`。

### 8.4 安装 SCTP 内核

```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
sudo ./install.sh kernel
sudo reboot
```

SSH 会在重启过程中断开。目标 K3 重新启动后登录并执行：

```bash
uname -r
grep -i sctp /proc/net/protocols
modinfo sctp
```

正常结果应满足：

- `uname -r` 为 `6.18.3-k3-sctp+`；
- `/proc/net/protocols` 同时包含 `SCTP` 和 `SCTPv6`；
- `modinfo sctp` 指向 `/lib/modules/6.18.3-k3-sctp+`。

只有这三项通过后才能安装 CN5G。

### 8.5 配置目标 K3 的网络参数

自动检测当前默认网卡和 IPv4 时，可以直接进入下一节。需要显式配置时执行：

```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
cp 02-cn5g/config.env.example config.env
ip -4 route show default
ip -4 address
nano config.env
```

至少确认：

```text
HOST_IP=目标K3的局域网IPv4
WAN_IF=目标K3的实际上网网卡
```

例如：

```text
HOST_IP=192.0.2.10
WAN_IF=wlP4p1s0
```

不要直接照抄示例，应使用目标 K3 的实际值。`UPF_N3_IP`、`GNB_N3_IP` 和 UE 地址段在同机实验且无地址冲突时可以保持默认。

### 8.6 离线安装 CN5G

使用自动检测网络参数：

```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
sudo ./install.sh cn5g
```

使用上一节的显式配置：

```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
sudo ./install.sh cn5g ./config.env
```

安装过程会完成：

1. 安装随包提供的 RISC-V `.deb` 依赖；
2. 安装 AMF、SMF、UPF 和私有运行库；
3. 根据目标 K3 的 IP 和网卡生成生效配置；
4. 启用 MariaDB；
5. 创建 `oai_db`、数据库账户和 UE 数据表。

### 8.7 启动核心网

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/start-cn5g.sh
```

检查状态：

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/status-cn5g.sh
```

进一步检查进程、端口和 SCTP：

```bash
ps -ef | grep -E '[a]mf|[s]mf|[u]pf'
sudo ss -lnptu
sudo ss -lnp --sctp
ip address show cn5g-upf
ip address show cn5g-gnb
```

查看日志：

```bash
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/upf.log
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/smf.log
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/amf.log
```

验收要求：

- `upf: running`；
- `smf: running`；
- `amf: running`；
- `N4: associated`；
- `N2/SCTP 38412: listening`。

### 8.8 停止核心网

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/stop-cn5g.sh
```

停止后确认：

```bash
sudo /opt/sionna-rk-k3/cn5g/scripts/status-cn5g.sh
pgrep -a amf || true
pgrep -a smf || true
pgrep -a upf || true
```

### 8.9 SCTP 内核回退

如果新内核能够进入系统，但需要恢复原厂引导：

```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
sudo ./01-sctp-kernel/rollback-kernel.sh
sudo reboot
```

回退脚本只恢复原厂 `boot.scr`，不会删除任何内核文件。也可以在 GRUB 的高级选项中手动选择：

```text
Ubuntu, with Linux 6.18.3-7-spacemit-generic
```

重启后检查：

```bash
uname -r
```

### 8.10 常见错误

若提示校验失败：

```text
FAILED
```

停止安装，重新复制归档；不要继续解压或安装。

若找不到 USB 路径，重新执行：

```bash
lsblk -f
findmnt
```

若 AMF 没有监听 SCTP：

```bash
uname -r
grep -i sctp /proc/net/protocols
sudo modprobe sctp
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/amf.log
```

若 N4 未建立：

```bash
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/smf.log
sudo tail -100 /var/lib/sionna-rk-k3/cn5g/logs/upf.log
ip address show cn5g-upf
```

## 9. 启动 gNB、CN5G 并连接 UE

本节要求目标 K3 已经按第 7 节在线安装或按第 8 节离线安装 CN5G，并且已经安装、编译 Sionna-RK 中的 OAI RAN。确认下面两个程序存在：

```bash
cd "$HOME/sionna-rk"
test -x ext/openairinterface5g/cmake_targets/ran_build/build/nr-softmodem \
  && echo "gNB: OK" || echo "gNB: MISSING"
test -x ext/openairinterface5g/cmake_targets/ran_build/build/nr-uesoftmodem \
  && echo "nrUE: OK" || echo "nrUE: MISSING"
```

离线包中的 `02-cn5g` 只负责核心网，不包含 OAI RAN 编译产物。若显示 `MISSING`，应先完成 OAI RISC-V 移植和编译，不能直接执行下面的启动命令。

### 9.1 两种 UE 接入方式

本项目支持两种不同的验证方式：

1. RFsim 软件 UE：gNB、RFsim、nrUE 和核心网都运行在 K3，用于验证完整协议流程，不发射真实无线信号；
2. B210 + 真实 UE：K3 运行 gNB 和核心网，B210 提供真实射频，手机或测试终端作为 UE。

初次部署应先完成 RFsim 软件 UE 验证，再尝试 B210 和真实 UE。

### 9.2 RFsim：一键启动核心网、gNB 和软件 UE

先停止可能遗留的进程：

```bash
cd "$HOME/sionna-rk"
sudo ./scripts/stop-full-cn5g-k3.sh || true
sudo pkill -INT -x nr-uesoftmodem 2>/dev/null || true
sudo pkill -INT -x nr-softmodem 2>/dev/null || true
sleep 3
```

启动完整 RFsim 5G 系统：

```bash
cd "$HOME/sionna-rk"
sudo -v
./scripts/start-full-cn5g-k3.sh
```

该脚本按以下顺序执行：

```text
MariaDB
→ UPF
→ SMF
→ AMF
→ N4 PFCP association
→ gNB
→ N2 NG Setup
→ 创建 cn5g-ue network namespace
→ nrUE
→ 注册和 PDU Session
```

检查整体状态：

```bash
cd "$HOME/sionna-rk"
./scripts/status-full-cn5g-k3.sh
```

成功结果应至少包含：

```text
upf: running
smf: running
amf: running
N4: associated
gNB: running
nrUE: running
UE PDU: active
N2 NG Setup: confirmed
PDU Session Accept: confirmed
```

检查 UE 地址：

```bash
sudo ip netns exec cn5g-ue ip -br address show oaitun_ue1
```

默认应看到 UE 地址 `12.1.1.130`。

验证 UE 到 UPF：

```bash
sudo ip netns exec cn5g-ue ping -I oaitun_ue1 -c 5 12.1.1.1
```

验证 UE 到公网：

```bash
sudo ip netns exec cn5g-ue ping -I oaitun_ue1 -c 5 8.8.8.8
```

查看各组件日志：

```bash
cd "$HOME/sionna-rk"
tail -100 logs/cn5g-k3/upf.log
tail -100 logs/cn5g-k3/smf.log
tail -100 logs/cn5g-k3/amf.log
tail -100 logs/cn5g-k3/gnb.log
tail -100 logs/cn5g-k3/nrue.log
```

快速检查关键流程：

```bash
grep -E 'Received NGSetupResponse|associated AMF' logs/cn5g-k3/gnb.log
grep -E 'Initial sync successful|UE synchronized|Registration Accept|PDU Session Establishment Accept' logs/cn5g-k3/nrue.log
grep -E 'Authentication Response|Registration Complete' logs/cn5g-k3/amf.log
grep -E 'N4 ASSOCIATION SETUP RESPONSE|PDU_SESSION_ACTIVE' logs/cn5g-k3/smf.log
```

停止完整 RFsim 系统：

```bash
cd "$HOME/sionna-rk"
sudo ./scripts/stop-full-cn5g-k3.sh
```

停止后确认没有残留：

```bash
pgrep -a nr-softmodem || true
pgrep -a nr-uesoftmodem || true
pgrep -a amf || true
pgrep -a smf || true
pgrep -a upf || true
ip netns list
```

### 9.3 RFsim 启动失败时检查

如果提示 gNB 没有完成 NG Setup：

```bash
grep -E 'NGSetup|SCTP|AMF|ERROR|Assert' "$HOME/sionna-rk/logs/cn5g-k3/gnb.log" | tail -100
sudo ss -lnp --sctp
ip route get "$(hostname -I | awk '{print $1}')"
```

如果 nrUE 无法建立 PDU Session：

```bash
grep -E 'Initial sync|UE synchronized|Registration|Authentication|PDU Session|ERROR|Assert' \
  "$HOME/sionna-rk/logs/cn5g-k3/nrue.log" | tail -150
tail -100 "$HOME/sionna-rk/logs/cn5g-k3/amf.log"
tail -100 "$HOME/sionna-rk/logs/cn5g-k3/smf.log"
```

再次运行前必须先清理：

```bash
cd "$HOME/sionna-rk"
sudo ./scripts/stop-full-cn5g-k3.sh || true
```

### 9.4 B210：启动核心网和真实射频 gNB

真实射频测试应在屏蔽箱或符合当地无线电管理要求的实验环境中进行，并使用合适的衰减器。不要在未经许可的频段直接辐射发射。

该启动器不属于 Sionna-RK 官方仓库，属于 **【K3 移植新增】**。可以直接在目标 K3 上生成，不需要从作者电脑复制脚本。

#### 9.4.1 准备 B200/B210 运行脚本

运行脚本属于 **【K3 移植新增】**，不属于 Sionna-RK 官方仓库。请选择一种方式：

1. 按文末“附录 A”在 K3 终端直接生成脚本；
2. 已经解压本离线包时，按照下一小节由安装程序复制同一份脚本。

正文不再放置完整脚本，后续修改或核对脚本时统一查看附录 A。

#### 9.4.2 使用离线包安装脚本

如果正在使用本离线包，也可以由安装程序复制同一份脚本：


```bash
cd "$HOME/k3-offline-install/sionna-rk-k3-offline-kit"
sudo ./install.sh b200 "$HOME/sionna-rk"
```

安装后应存在：

```text
$HOME/sionna-rk/scripts/run-k3-b200.sh
$HOME/sionna-rk/config/b200/.env.k3-example
```

检查脚本：

```bash
test -x "$HOME/sionna-rk/scripts/run-k3-b200.sh" \
  && echo "B200 launcher: OK" || echo "B200 launcher: MISSING"
bash -n "$HOME/sionna-rk/scripts/run-k3-b200.sh"
```

如果 `config/b200/.env` 尚不存在，以项目原有配置或 `.env.k3-example` 为参考创建。
至少要填写 `USRP_SERIAL`、`AMF_IP`、`GNB_IP`、`K3_GNB_BUILD` 和
`K3_GNB_ALLOWED_CPUS`。示例里的序列号、IP 和用户名路径不能直接照抄。

确认 B210 已连接到 USB 3：

```bash
lsusb | grep '2500:0020'
uhd_find_devices
uhd_usrp_probe
```

记录 `uhd_find_devices` 输出的序列号，然后检查：

```bash
cd "$HOME/sionna-rk"
grep -E '^(USRP_SERIAL|AMF_IP|GNB_IP|K3_GNB_BUILD|K3_GNB_ALLOWED_CPUS)=' config/b200/.env
```

至少确认：

- `USRP_SERIAL` 与当前 B210 一致；
- `AMF_IP` 是本机 AMF 实际监听地址；
- `GNB_IP` 已分配给当前 K3；
- `K3_GNB_BUILD` 指向有效的 RISC-V OAI 构建目录。

检查配置但不启动：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh check
```

检查通过后启动核心网和 B210 gNB：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh start
```

只有已经另外应用 K3 `start_system.sh` 集成补丁的开发环境，才可以使用统一入口：

```bash
cd "$HOME/sionna-rk"
./scripts/start_system.sh b200
```

离线包默认保证可用的是 `run-k3-b200.sh`。两种入口选择一个执行，不要重复启动。

检查状态：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh status
```

持续查看 gNB 日志：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh log
```

重点确认：

```text
Received NGSetupResponse
associated AMF 1
```

这只说明 gNB 已通过 N2 接入核心网，不代表真实 UE 已经注册。

### 9.5 真实 UE/手机的 USIM 条件

普通运营商 SIM 不能直接注册到本实验核心网。真实 UE 必须满足：

- 支持 SA 5G NR 和 n78；
- 使用可编程测试 USIM；
- USIM 中的 IMSI、K、OPc/OP 与 AMF 查询的 `oai_db.users` 记录一致；
- PLMN 与 gNB/AMF 配置一致，本项目当前使用 `MCC=208`、`MNC=95`；
- APN/DNN 与核心网配置一致，当前为 `oai`。

查看 OAI 软件 UE 使用的测试身份：

```bash
cd "$HOME/sionna-rk"
grep -E '^[[:space:]]*(imsi|key|opc|dnn)' \
  ext/oai-cn5g-fed/docker-compose/ran-conf/nr-ue.conf
```

查看数据库中已经配置的 IMSI（需要数据库管理员权限）：

```bash
sudo mariadb oai_db -e 'SELECT imsi,mcc,mnc FROM users;'
```

不要把测试 USIM 的 K、OPc 或数据库口令上传到公共平台。写入实体 USIM 时，应在受控环境中完成。

### 9.6 观察真实 UE 注册过程

另开一个终端观察 AMF：

```bash
tail -F "$HOME/sionna-rk/logs/cn5g-k3/amf.log" \
  | grep --line-buffered -E 'Registration|Authentication|Security Mode|PDU Session|imsi|supi'
```

观察 SMF：

```bash
tail -F "$HOME/sionna-rk/logs/cn5g-k3/smf.log" \
  | grep --line-buffered -E 'Create SM Context|N4|PFCP|PDU_SESSION_ACTIVE'
```

观察 UPF：

```bash
tail -F "$HOME/sionna-rk/logs/cn5g-k3/upf.log" \
  | grep --line-buffered -E 'SESSION ESTABLISHMENT|PDR|FAR|GTP'
```

真实 UE 接入成功应依次出现：

```text
RRC 接入
→ Registration Request
→ Authentication Response
→ Security Mode Complete
→ Registration Complete
→ PDU Session Establishment
→ PFCP Session Establishment
→ PDU_SESSION_ACTIVE
```

### 9.7 停止 B210 gNB 和核心网

如果使用 `run-k3-b200.sh` 启动：

```bash
cd "$HOME/sionna-rk"
./scripts/run-k3-b200.sh stop
```

如果已经另外应用统一入口补丁并使用该入口启动：

```bash
cd "$HOME/sionna-rk"
./scripts/stop_system.sh b200
```

最后检查：

```bash
systemctl is-active k3-b200-gnb.service || true
pgrep -a nr-softmodem || true
pgrep -a amf || true
pgrep -a smf || true
pgrep -a upf || true
```

### 9.8 当前 B210 限制

当前 K3 已验证：B210 能被 UHD 识别、gNB 能初始化、核心网能启动、N2 NG Setup 能完成。但射频流仍可能出现 UHD `ERROR_CODE_OVERFLOW`。因此现阶段可以声明“B210 gNB 与 CN5G 框架已打通”，在 overflow 和实时性问题解决、真实 UE 完成注册及 PDU Session 前，不能声明真实空口端到端已经验收成功。

## 附录 A：生成 B200/B210 运行脚本

本附录是正文中最先出现的新增脚本。把下面代码块完整复制到目标 K3 终端执行；它会生成 `$HOME/sionna-rk/scripts/run-k3-b200.sh`。

```bash
cd "$HOME/sionna-rk"
mkdir -p scripts

cat > scripts/run-k3-b200.sh <<'K3_B200_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SIONNA_RK_ROOT:-$HOME/sionna-rk}"
ENV_FILE="$ROOT/config/b200/.env"
DEFAULT_BUILD="$ROOT/ext/openairinterface5g/cmake_targets/ran_build/build"
BUILD="$DEFAULT_BUILD"
GNB_BIN="$BUILD/nr-softmodem"
GNB_TEMPLATE="$ROOT/config/common/gnb.sa.band78.24prbs.conf"
RUNTIME_DIR="$ROOT/.runtime/k3-b200"
RUNTIME_CONF="$RUNTIME_DIR/gnb.conf"
UNIT="k3-b200-gnb.service"
OPT_LOG="$ROOT/.runtime/k3-b200/optimization.log"
CORE_PREFIX="${K3_CN5G_PREFIX:-/opt/sionna-rk-k3/cn5g}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
active() { sudo systemctl is-active --quiet "$UNIT"; }

ensure_core() {
    if ! pgrep -x upf >/dev/null || ! pgrep -x smf >/dev/null || ! pgrep -x amf >/dev/null; then
        sudo "$CORE_PREFIX/scripts/start-cn5g.sh"
    fi
}

record() {
    mkdir -p "$(dirname "$OPT_LOG")"
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$OPT_LOG"
}

apply_host_tuning() {
    # Keep the B210 xHCI interrupt away from the eight A100 PHY cores. Retain
    # the kernel's RT safety budget so management/network tasks cannot starve.
    sudo sysctl -q -w kernel.sched_rt_runtime_us=950000
    local irq
    irq=$(awk '/xhci-hcd:usb5$/ {gsub(":", "", $1); print $1; exit}' /proc/interrupts)
    if [ -n "$irq" ] && [ -e "/proc/irq/$irq/smp_affinity" ]; then
        echo 80 | sudo tee "/proc/irq/$irq/smp_affinity" >/dev/null
        record "host-tuning rt_runtime_us=950000 b210_xhci_irq=$irq irq_affinity=cpu7"
    else
        record "host-tuning rt_runtime_us=950000 b210_xhci_irq=not-found"
    fi
}

load_env() {
    [ -r "$ENV_FILE" ] || die "Missing $ENV_FILE"
    set -a
    set +u
    # This is the project-owned shell-style environment file used by Compose.
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set -u
    set +a
}

valid_ipv4() {
    local ip=$1 part
    [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a parts <<< "$ip"
    for part in "${parts[@]}"; do
        (( part >= 0 && part <= 255 )) || return 1
    done
}

select_gnb_ip() {
    if [ -n "${GNB_IP:-}" ]; then
        printf '%s\n' "$GNB_IP"
        return
    fi
    ip -4 route get "$AMF_IP" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
}

preflight() {
    load_env
    # K3_GNB_BUILD is defined by the project .env, so resolve it only after
    # load_env. This keeps the original build as the automatic fallback.
    BUILD="${K3_GNB_BUILD:-$DEFAULT_BUILD}"
    GNB_BIN="$BUILD/nr-softmodem"
    [ "$(uname -m)" = "riscv64" ] || die "This launcher is for the RV64 K3; detected $(uname -m)."
    [ -x "$GNB_BIN" ] || die "Missing $GNB_BIN; build the native OAI gNB first."
    [ -x "$CORE_PREFIX/scripts/start-cn5g.sh" ] || die "Missing native CN5G launcher: $CORE_PREFIX/scripts/start-cn5g.sh"
    [ -r "$GNB_TEMPLATE" ] || die "Missing gNB template: $GNB_TEMPLATE"
    command -v uhd_find_devices >/dev/null || die "uhd_find_devices is missing; install/build UHD for riscv64."
    command -v uhd_usrp_probe >/dev/null || die "uhd_usrp_probe is missing; install/build UHD for riscv64."
    [ -n "${USRP_SERIAL:-}" ] || die "Set USRP_SERIAL in $ENV_FILE"
    [ -n "${AMF_IP:-}" ] || die "Set AMF_IP in $ENV_FILE to the external 5G Core AMF address."
    valid_ipv4 "$AMF_IP" || die "AMF_IP is not a valid IPv4 address: $AMF_IP"
    RESOLVED_GNB_IP=$(select_gnb_ip)
    [ -n "$RESOLVED_GNB_IP" ] || die "Could not select a K3 source address for AMF $AMF_IP; set GNB_IP explicitly."
    valid_ipv4 "$RESOLVED_GNB_IP" || die "GNB_IP is not a valid IPv4 address: $RESOLVED_GNB_IP"
    ip -4 addr show | grep -qw "$RESOLVED_GNB_IP" || die "GNB_IP $RESOLVED_GNB_IP is not assigned to this K3."
    uhd_find_devices 2>&1 | grep -Fq "$USRP_SERIAL" || die "USRP $USRP_SERIAL was not found by UHD."
}

write_runtime_config() {
    mkdir -p "$RUNTIME_DIR"
    cp "$GNB_TEMPLATE" "$RUNTIME_CONF"
    sed -Ei \
        -e 's#tracking_area_code[[:space:]]*=[[:space:]]*[^;]+;#tracking_area_code  = 0xa000;#' \
        -e 's#plmn_list[[:space:]]*=[[:space:]]*\(\{[[:space:]]*mcc[[:space:]]*=[[:space:]]*[0-9]+;[[:space:]]*mnc[[:space:]]*=[[:space:]]*[0-9]+;[[:space:]]*mnc_length[[:space:]]*=[[:space:]]*[0-9]+;#plmn_list = ({ mcc = 208; mnc = 95; mnc_length = 2;#' \
        -e "s#(amf_ip_address[[:space:]]*=[[:space:]]*\\(\\{[[:space:]]*ipv4[[:space:]]*=[[:space:]]*)\"[^\"]+\"#\\1\"$AMF_IP\"#" \
        -e "s#(GNB_IPV4_ADDRESS_FOR_NG_AMF[[:space:]]*=[[:space:]]*)\"[^\"]+\"#\\1\"$RESOLVED_GNB_IP\"#" \
        -e "s#(GNB_IPV4_ADDRESS_FOR_NGU[[:space:]]*=[[:space:]]*)\"[^\"]+\"#\\1\"$RESOLVED_GNB_IP\"#" \
        "$RUNTIME_CONF"
    grep -Fq "ipv4 = \"$AMF_IP\"" "$RUNTIME_CONF" || die "Failed to write AMF_IP to runtime config."
    [ "$(grep -Fc "\"$RESOLVED_GNB_IP\"" "$RUNTIME_CONF")" -ge 2 ] || die "Failed to write GNB_IP to runtime config."
}

start_gnb() {
    preflight
    ensure_core
    local allowed_cpus="${K3_GNB_ALLOWED_CPUS:-8-15}"
    active && die "$UNIT is already active."
    pgrep -x nr-softmodem >/dev/null && die "An unmanaged nr-softmodem process is already running."
    write_runtime_config
    apply_host_tuning
    record "start kernel=$(uname -r) build=$BUILD usrp=$USRP_SERIAL amf=$AMF_IP gnb_ip=$RESOLVED_GNB_IP thread_pool=${K3_GNB_THREAD_POOL:-default} l1_rx=-1 l1_tx=-1 ru_pool=-1x5 ru_thread=-1 allowed_cpus=$allowed_cpus"

    args=(
        "$GNB_BIN" -O "$RUNTIME_CONF"
        --RUs.[0].sdr_addrs "serial=$USRP_SERIAL"
        --continuous-tx
        --telnetsrv
        --reorder-thread-disable 1
        --log_config.global_log_options level,nocolor,time
    )
    if [ -n "${K3_GNB_THREAD_POOL:-}" ]; then
        args+=(--thread-pool "$K3_GNB_THREAD_POOL")
    fi
    if [ -n "${GNB_EXTRA_OPTIONS:-}" ]; then
        read -r -a extra <<< "$GNB_EXTRA_OPTIONS"
        args+=("${extra[@]}")
    fi

    sudo systemctl reset-failed "$UNIT" 2>/dev/null || true
    sudo systemd-run \
        --unit="$UNIT" \
        --service-type=exec \
        --property=Restart=no \
        --property=KillMode=mixed \
        --property=TimeoutStopSec=10 \
        --property="AllowedCPUs=$allowed_cpus" \
        --property=LimitMEMLOCK=infinity \
        --property=Nice=-20 \
        --property=TasksMax=infinity \
        --working-directory="$BUILD" \
        "${args[@]}"
    sleep 3
    active || {
        sudo journalctl -u "$UNIT" -n 120 --no-pager
        die "Native B200 gNB failed to start."
    }
    echo "Native K3 B200 gNB started."
    echo "AMF: $AMF_IP; K3 N2/N3 address: $RESOLVED_GNB_IP; USRP: $USRP_SERIAL"
    echo "Logs: $0 log"
}

case "${1:-}" in
    check)
        preflight
        ensure_core
        write_runtime_config
        echo "Preflight passed. Runtime config: $RUNTIME_CONF"
        ;;
    start) start_gnb ;;
    status)
        sudo "$CORE_PREFIX/scripts/status-cn5g.sh"
        sudo systemctl --no-pager --full status "$UNIT" || true
        sudo journalctl -u "$UNIT" --no-pager | grep -E 'Received NGSetupResponse|associated AMF|No UHD Devices|RuntimeError|ERROR' | tail -20 || true
        ;;
    log) exec sudo journalctl -fu "$UNIT" -n 100 ;;
    stop)
        sudo systemctl stop "$UNIT" 2>/dev/null || true
        sudo "$CORE_PREFIX/scripts/stop-cn5g.sh"
        echo "Native K3 B200 gNB and CN5G stopped."
        ;;
    *)
        echo "Usage: $0 check|start|status|log|stop"
        exit 2
        ;;
esac
K3_B200_SCRIPT

chmod +x scripts/run-k3-b200.sh
bash -n scripts/run-k3-b200.sh \
  && echo "B200 运行脚本创建成功，语法检查通过"
```

必须保留带单引号的 `<<'K3_B200_SCRIPT'`。这样生成脚本时不会提前展开其中的变量。

生成结果应位于：

```text
$HOME/sionna-rk/scripts/run-k3-b200.sh
```
