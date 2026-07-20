# Tailscale 集成说明

## 版本
- Tailscale 版本：由 [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) feed 提供（feed 分支）
- LUCI 界面：由 [Tokisaki-Galaxy/luci-app-tailscale-community](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community) 源码编译
- 菜单分类：VPN（通过 uci-defaults 脚本在首次启动时自动修正）

## 集成方式

### 1. Tailscale 二进制（GuNanOvO feed）
在 `feeds.conf.default` 中添加：
```
src-git opentailscale https://github.com/GuNanOvO/openwrt-tailscale.git;feed
```
由 feeds 系统自动拉取并编译 `tailscale` 包，满足 `luci-app-tailscale-community` 的 `+tailscale` 依赖。

### 2. LUCI 界面（dl_git_sub）
在 `user/common/custom.sh` 中通过 `dl_git_sub` 克隆源码：
```bash
dl_git_sub https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community package/luci-app-tailscale-community luci-app-tailscale-community main
```

### 3. 菜单移至 VPN
`custom.sh` 中修改 menu.d JSON：
```bash
sed -i 's|"admin/services/tailscale"|"admin/vpn/tailscale"|g' ...
```
另在 `user/common/files/etc/uci-defaults/zzzz-tailscale-vpn-menu` 中做备份修正。

### 4. 状态持久化
已在 `custom.sh` 中设置 `TS_STATE_DIR=/etc/tailscale/state`，
确保节点密钥和登录状态在重启后不丢失。

### 5. UDP GRO 性能优化
通过 `uci-defaults/zzzz-tailscale-gro` 在首次启动时执行：
```sh
ethtool -K br-lan rx-gro-list on
```
消除 Tailscale 的 UDP GRO 转发警告。

### 6. config.diff 配置
- `CONFIG_PACKAGE_luci-app-tailscale-community=y`
- `CONFIG_PACKAGE_tailscale=y`
- `CONFIG_PACKAGE_ethtool=y`（GRO 优化依赖）

## 工作原理
1. `feeds update -a` → 拉取 GuNanOvO tailscale feed
2. `custom.sh` → 克隆 luci-app-tailscale-community 源码并修正菜单
3. `feeds install -a` → 安装 tailscale + luci-app-tailscale-community
4. 编译 → tailscale 二进制并入固件
5. 首次启动 → uci-defaults 脚本自动优化 GRO + 修正菜单
