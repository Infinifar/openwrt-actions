# 来源与致谢

本仓库是配置、补丁与构建流程的集成，不宣称下列上游作品为原创。原作者的 LICENSE、版权头和公开署名应保留；组件许可证不能用本仓库的 MIT 许可证替代。

| 项目 / 作者 | 使用范围与来源 |
|---|---|
| alecthw/openwrt-actions | 原构建项目、工作流与配置框架：https://github.com/alecthw/openwrt-actions |
| coolsnowwolf/lede、coolsnowwolf/luci、OpenWrt | 固件、LuCI 与软件包 feeds：https://github.com/coolsnowwolf/lede ，https://github.com/coolsnowwolf/luci ，https://github.com/openwrt/packages |
| IrineSistiana/mosdns 及贡献者 | MosDNS 原始项目，GPL-3.0：https://github.com/IrineSistiana/mosdns |
| alecthw/mosdns | 本次 MosDNS 基线及 MMDB 修改：https://github.com/alecthw/mosdns |
| sbwml/luci-app-mosdns | LuCI、stats_api 插件与查询上下文等补丁：https://github.com/sbwml/luci-app-mosdns/tree/v5/mosdns/patches |
| vernesong/OpenClash、MetaCubeX/mihomo | OpenClash 与代理内核：https://github.com/vernesong/OpenClash ，https://github.com/MetaCubeX/mihomo |
| Zephyruso/zashboard | 控制面板：https://github.com/Zephyruso/zashboard |
| vernette、henrygd/beszel | Beszel OpenWrt 包与 agent：https://github.com/vernette/beszel-agent-openwrt ，https://github.com/henrygd/beszel |
| GuNanOvO、Tokisaki-Galaxy、Tailscale | Tailscale 包、LuCI 社区插件与原项目：https://github.com/GuNanOvO/openwrt-tailscale ，https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community ，https://github.com/tailscale/tailscale |
| ZeroTier、OpenWrt 包维护者 | ZeroTier 核心和集成：https://github.com/zerotier/ZeroTierOne ，https://github.com/openwrt/packages |
| jerrykuku/luci-theme-argon | Argon 主题及资源：https://github.com/jerrykuku/luci-theme-argon |
| blackmatrix7、Loyalsoldier、alecthw、MetaCubeX | 分流规则、地理数据和 DNS 列表：https://github.com/blackmatrix7/ios_rule_script ，https://github.com/Loyalsoldier/v2ray-rules-dat ，https://github.com/alecthw/chnlist ，https://github.com/alecthw/mmdb_china_ip_list ，https://github.com/MetaCubeX/meta-rules-dat |
| dashboard-icons、selfh.st | 策略组图标来源：https://github.com/homarr-labs/dashboard-icons ，https://selfh.st/icons/ |
| rockjake、orbien-org | 风扇控制与 Orbien：https://github.com/rockjake/luci-app-fancontrol ，https://github.com/orbien-org/orbien |

本公开版的集成工作包括依赖校验、LuCI 兼容补丁、统计功能移植、策略规则与公开模板安全门禁。完整 MosDNS 来源链、基线和移植范围另见 [MosDNS 署名说明](https://github.com/Infinifar/mosdns/blob/main/CREDITS.md)。

上表按直接使用的项目列出，不替代各依赖的完整贡献者列表、Go 模块清单及其独立许可证。
