# 小米 CR660x 固件：Netkeeper 闪讯 + UA3F

本仓库用于通过 GitHub Actions 在线编译 ImmortalWrt 固件，目标设备为小米 Mi Router CR6606 / CR6608 / CR6609。

## 功能清单

- Netkeeper 四件套：`netkeeper`、`luci-proto-netkeeper`、`netkeeper-interception`、`luci-app-netkeeper-interception`
- UA3F 及其 LuCI 管理页面
- `kmod-nft-queue`、`kmod-nft-tproxy`、`kmod-sched-bpf`、`libubox-lua`
- 为 NFQUEUE/BPF 与 UA3F 所需的相关内核模块和 iptables 组件

上游源码：
- [Netkeeper interception](https://github.com/YYuan996/netkeeper-interception)
- [UA3F](https://github.com/SunBK201/UA3F)

## 在线编译

1. 进入仓库的 **Actions** 标签页。
2. 选择 **Build ImmortalWrt CR660x + Netkeeper + UA3F**。
3. 点击 **Run workflow**。也可通过向 `main` 分支推送提交自动启动。
4. 成功后，在对应工作流运行页面的 **Artifacts** 下载 `cr660x-firmware`；失败时下载 `cr660x-build-log` 查看日志。

默认使用 ImmortalWrt `openwrt-24.10` 分支，以匹配 `opkg` 包管理环境。GitHub 标准运行器磁盘空间有限；如出现 `No space left on device`，需要改用有更大磁盘的自托管运行器，或扩容运行器。

## 重要说明

- 当前工作流构建的是 OpenWrt/ImmortalWrt 固件，不是小米原厂固件。
- 请先确认实机型号为 CR6606、CR6608 或 CR6609，并确认当前系统的刷机/救援方法。
- 不要混用不同内核版本的 `kmod-*` 包；此仓库尽可能将指定依赖编进同一个固件。
- 工作流成功不代表已验证 Netkeeper 在每家运营商线路上都能正常拨号。编译成功后请先核对产物名称和校验信息，再决定是否刷机。
- 本仓库使用的上游项目按各自许可证发布，请遵守其许可条款。
