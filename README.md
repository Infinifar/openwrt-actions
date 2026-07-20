# OpenWRT 编译 (含 Tailscale)

[![build-openwrt](https://github.com/alecthw/openwrt-actions/actions/workflows/build-openwrt.yml/badge.svg)](https://github.com/alecthw/openwrt-actions/actions/workflows/build-openwrt.yml)
[![build-n1](https://github.com/alecthw/openwrt-actions/actions/workflows/build-n1.yml/badge.svg)](https://github.com/alecthw/openwrt-actions/actions/workflows/build-n1.yml)

> Fork 自 [alecthw/openwrt-actions](https://github.com/alecthw/openwrt-actions)，仅保留 `lede-openclash-x86-amd64` 和 `lede-common-n1-arm64`，并集成 Tailscale。

每周五自动构建新版本。

专注制作旁路由精简固件，稳定运行！

旁路由固件默认 IP 地址：
默认 IP: `192.168.11.4/24`
默认 GW: `192.168.11.1`

密码: `没有密码`，其他如有涉及默认密码的都是 `password`

## Tailscale 集成

本分支已集成 Tailscale，包含：
- **Tailscale 二进制**：通过 [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) feed 编译
- **LUCI 界面**：[luci-app-tailscale-community](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community)（菜单位于 VPN 分类下）
- **UDP GRO 优化**：首次启动自动开启 `rx-gro-list`，消除 Tailscale UDP GRO 转发警告
- **状态持久化**：`TS_STATE_DIR=/etc/tailscale/state`，节点密钥和登录状态不会因重启丢失

## 详细说明见各个目标子目录

分为旁路由固件和硬件路由固件。

注意：旁路由固件默认未开启 DHCP！！！旁路由固件默认未开启 DHCP！！！旁路由固件默认未开启 DHCP！！！

可以参考：[在后台使用命令行修改 IP 地址和掩码](#命令行修改-ip-和掩码)

### 旁路由固件

重点是 AdGuardHome 、 mosdns 和 openclash （或 ssrp ）的搭配，详细介绍见子目录下的 README。更多信息可以参考[这篇文章](https://alecthw.github.io/p/2023/11/fuck-gfw/)。

#### 基于 LEDE 构建

- [LEDE 源码](https://github.com/coolsnowwolf/lede)

| 说明 | 下载 |
|---|---|
| [lede-openclash-x86-amd64](user/lede-openclash-x86-amd64/README.md) | [Release](https://github.com/alecthw/openwrt-actions/releases/tag/lede-openclash-x86-amd64) |
| [lede-common-n1-arm64](user/lede-common-n1-arm64/README.md) | [Release](https://github.com/alecthw/openwrt-actions/releases/tag/lede-common-n1-arm64) |

#### 特别说明

##### 1. DHCP 服务器

一般情况下建议禁用旁路由的 DHCP 服务器，在主路由配置 DHCP 服务器，把网关设置成旁路由，或者通过静态分配指定不同客户端指向不同网关。

**由于旁路由 openclash 专属固件默认未设置 53 端口劫持，所以 DHCP 服务器设置中的 DNS 服务器，务必设置成旁路由，不要设置公共 DNS。

##### 2. IPv6

主路由上**请勿通告 IPv6 DNS 服务器**（这里指 IPv6 地址的 DNS 服务器，如 2400:3200::1）。通过 IPv4 地址的 DNS 服务器解析域名，一样可以拿到 AAAA 记录，所以没必要开启 IPv6 地址的 DNS 服务器，开启反而会增加配置难度，影响 DNS 分流，并可能造成 DNS 泄露。

Openwrt、iKuai、RouterOS 都是支持不通告 IPv6 DNS 的。如果你的主路由不支持，IPv6 DNS 可以填个无效地址，如 `::1`

##### 3. 开启 openclash 后 DNS 异常问题

参考：[Clash 订阅引起 DNS 问题的说明](https://github.com/alecthw/openwrt-actions/blob/master/user/lede-common-x86-amd64/README.md#clash-%E8%AE%A2%E9%98%85%E5%BC%95%E8%B5%B7-dns-%E9%97%AE%E9%A2%98%E7%9A%84%E8%AF%B4%E6%98%8E)

## 命令行修改 IP 和掩码

注意，旁路由固件默认未开启 DHCP，旁路由固件默认未开启 DHCP，旁路由固件默认未开启 DHCP！

所以，如果不在控制台修改 IP，请修改电脑的 IP 访问，然后可以在网页修改。

```bash
# 作为旁路路由，IP 不建议设置 1，防止和主路由冲突！
# 命令行修改 IP 示例：
uci set network.lan.ipaddr='192.168.1.2'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.1.1'
uci commit network
```

## 编译和固件个性化流程说明

1. 导出 `Settings.ini` 内容为环境变量
2. 克隆 OpenWRT 源码
3. 安装 `user/common/patches`和`user/[target]/patches` 目录下的补丁
4. 添加 Tailscale feed（`src-git opentailscale https://github.com/GuNanOvO/openwrt-tailscale.git;feed`）
5. 更新 feeds，Update feeds
6. 复制 `user/common/files` 和 `user/[target]/files` 到 `[OpenWRT Code Dir]/files`，注意后者覆盖前者
7. 执行脚本 `user/common/custom.sh` 和 `user/[target]/custom.sh`
8. 安装 feeds，Install feeds
9. 执行 `app_config.sh` 脚本，对插件做自定义，包括下载部分插件需要的二进制执行文件，例如 `clash` 和 `AdGuardHome`
10. 开始编译

## 本地构建指南

使用 [act](https://nektosact.com/) 本地执行 workflow 进行构建。

### 准备环境 Ubuntu 2204

```bash
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y ack antlr3 aria2 asciidoc autoconf automake autopoint binutils bison build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext gcc-multilib g++-multilib git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libreadline-dev libssl-dev libtool lrzsz mkisofs msmtp nano ninja-build p7zip p7zip-full patch pkgconf python2.7 python3 python3-pip python3-pyelftools libpython3-dev qemu-utils rsync scons squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev clang llvm npm
```

### 安装 act

```bash
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin
```

或参考官方文档：[act install](https://nektosact.com/installation/index.html)

### 构建

```bash
git clone <your-fork-url>.git
cd openwrt-actions
act \
    -r
    -P ubuntu-22.04=-self-hosted \
    -a alecthw \
    -W '.github/workflows/build-openwrt.yml' \
    --matrix target:lede-openclash-x86-amd64 \
    workflow_dispatch
```

matrix `target` 是 user 目录下下除 common 以外的文件夹名。

## ext4 扩容（如 SD-Card 空间未使用）

需要 `fdisk resize2fs losetup`，`r2s, zero3, filogic` 固件已预置。

### 查看分区，记录数据分区起始扇区

```bash
fdisk -l
```

## 转换工具下载

- StarWind V2V Converter: [Download link](https://www.starwindsoftware.com/tmplink/starwindconverter.exe)

## 链接

- [chnlist](https://github.com/alecthw/chnlist)
- [coolsnowwolf lede](https://github.com/coolsnowwolf/lede)
- [immortalwrt](https://github.com/immortalwrt/immortalwrt)
