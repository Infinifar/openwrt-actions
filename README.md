# OpenWrt / LEDE 公开配置模板

这是经过脱敏的构建模板，不是任何生产路由器的恢复包。它保留可复用的构建、DNS、策略组及校验代码；私有部署仓库与设备不受本仓库更新影响。

## 保留的功能

- OpenClash / Mihomo、独立更新的 Zashboard，以及 AI、US-AI、Google、Docker 策略和规则。
- AdGuard Home 规则磁盘持久化、每天更新，MosDNS 同源 hosts 同步与缓存优化。
- 基于 alecthw 修改版的 MosDNS，补充 stats_api；源码固定引用公开的 [Infinifar/mosdns](https://github.com/Infinifar/mosdns)。
- Tailscale nftables 默认选项、connmark 依赖、LuCI 应用与防火墙重载兼容补丁。
- ZeroTier、Beszel Agent 安装支持，Argon 主题依赖及安装完整性校验。
- x86 的 QEMU Guest Agent；ShadowSocksR Plus 保持禁用。

## 本公开版刻意不包含

代理订阅和节点、账号密码及密码哈希、VPN 登录状态和私钥、ZeroTier 网络身份、Beszel 授权、私人域名/IP/MAC、生产防火墙和网络拓扑、个人壁纸、原始备份与私有 GitLab 提交历史。

- 订阅文件只有 `proxies: []`，三个配置保留禁用的 Subscribe4AI HTTP 订阅示例。
- Tailscale 不通告子网/出口，不启用中继，也没有登录状态；ZeroTier/Beszel 不自动加入或连接任何网络。
- OpenClash、AdGuard、VPN、监控服务默认不自动启用。AdGuard 管理地址及配置中的 Mihomo 外控仅监听回环地址。
- 开机模板不覆盖上游的 LAN 地址、网关、MAC、DHCP 和 SSH 登录设置。
- Argon 使用无个人内容、无元数据的纯色占位图，仍校验主题真实安装与依赖。

不要把本模板视为“刷入即可复原”的个人固件。首次部署必须自行设置密码、导入节点、配置网络和服务，然后再启用对应服务。不要将填写后的文件推回公开仓库。

## 获取与校验

```sh
git clone --recurse-submodules https://github.com/Infinifar/openwrt-actions.git
cd openwrt-actions
python3 -B scripts/validate-public-config.py
bash scripts/validate-personal-config.sh
```

需要 Python 3 + PyYAML、Ruby 和 Node.js。兼容入口 validate-personal-config.sh 在公开版校验的是“无账号、无设备身份、无生产重写”的安全模板，同时保留功能回归；不是要求导入个人配置。

GitHub Actions 中的 x86 / N1 构建均只接受手动触发；普通 push 不自动编译。公开版依赖不需要任何私有源码部署令牌。构建和发布使用 GitHub 提供的 GITHUB_TOKEN，不要求填写个人访问令牌。此次公开同步没有编译固件。

本地编译入口为 localbuild.sh，请先查看其用法并提供足够磁盘空间。公开模板未作为完整固件重新编译或刷机验收，不能将离线校验当作硬件兼容证明。

## 自行部署时

1. 设置路由器管理密码，确认 LAN/DHCP/防火墙符合自己的拓扑。
2. 配置 AdGuard 的本地账号、监听地址和需要的精确重写；默认重写列表为空。DNS 链路涉及 OpenClash 7874 / MosDNS 5335，先配置完整链路再启用 AdGuard。
3. 在本地导入订阅，并设置 Mihomo 外控密钥和允许访问范围；US-AI 需要名称匹配的节点，空组按原规则拒绝回退。
4. 按需登录 Tailscale、加入 ZeroTier，填写 Beszel hub/key/token；不要复用别人的设备状态文件。
5. 同源 DNS 示例默认使用 example.com 域名范围，部署时将同步脚本里的示例范围替换成自己的域名；不要另做相互循环的 DNS 转发。

代码和外部组件的来源见 [CREDITS.md](CREDITS.md)，脱敏范围及检查边界见 [PUBLICATION.md](PUBLICATION.md)。原构建项目的 MIT 许可证保留，各子项目遵循自己的许可证；MosDNS 为 GPL-3.0。
