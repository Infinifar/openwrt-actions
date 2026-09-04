#!/bin/bash

# Execute after install feeds
# patch -> [update & install feeds] -> custom -> config

echo "Current dir: $(pwd), Script: $0"

if [ -z "${GITHUB_WORKSPACE}" ]; then
    echo "GITHUB_WORKSPACE not set"
    GITHUB_WORKSPACE=$(
        cd $(dirname $0)/../..
        pwd
    )
    export GITHUB_WORKSPACE
fi

source $GITHUB_WORKSPACE/lib.sh

target=$1
echo "Execute common custom.sh ${target}"

target_array=(${target//-/ })
build_source=${target_array[0]}
build_type=${target_array[1]}
build_target=${target_array[2]}
build_arch=${target_array[3]}
echo "source=${build_source}, type=${build_type}, target=${build_target}, arch=${build_arch}"

# Priority: package dir > feeds dir
do_common() {
    # Set banner
    echo " Built on $(date +%Y-%m-%d)" >>files/etc/banner
    echo "" >>files/etc/banner
    mv -f files/etc/banner package/base-files/files/etc/banner

    # add luci-theme-argon-jerrykuku
    rm -rf package/luci-theme-argon-jerrykuku
    dl_git https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon-jerrykuku

    # add/replace feeds/luci/applications/luci-app-mosdns
    rm -rf package/luci-app-mosdns
    dl_git_sub https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns luci-app-mosdns v5

    # replace feeds/helloworld/mosdns, feeds/packages/net/mosdns
    rm -rf package/mosdns
    dl_git_sub https://github.com/sbwml/luci-app-mosdns package/mosdns mosdns v5
    rm -rf package/mosdns/patches
    sed -i 's#IrineSistiana/mosdns/tar#alecthw/mosdns/tar#g' package/mosdns/Makefile
    sed -i 's/^PKG_HASH.*/PKG_HASH:=skip/g' package/mosdns/Makefile

    # add openclash | replace feeds/luci/applications/luci-app-openclash
    rm -rf package/luci-app-openclash
    dl_git_sub https://github.com/vernesong/OpenClash package/luci-app-openclash luci-app-openclash master
    sed -i "/dashboard_password/d" package/luci-app-openclash/root/etc/uci-defaults/luci-openclash

    # add luci-app-fancontrol
    rm -rf package/luci-app-fancontrol
    dl_git_sub https://github.com/rockjake/luci-app-fancontrol package/luci-app-fancontrol luci-app-fancontrol
    rm -rf package/fancontrol
    dl_git_sub https://github.com/rockjake/luci-app-fancontrol package/fancontrol fancontrol

    # add luci-app-nginx (LuCI interface for Nginx management)
    rm -rf package/luci-app-nginx
    dl_git https://github.com/arenekosreal/luci-app-nginx package/luci-app-nginx

    # add luci-app-tailscale-community
    rm -rf package/luci-app-tailscale-community
    dl_git_sub https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community package/luci-app-tailscale-community luci-app-tailscale-community master

    # move tailscale menu from Services to VPN
    find package/luci-app-tailscale-community -path '*/menu.d/*.json' | while read f; do
        sed -i 's|"admin/services/tailscale"|"admin/vpn/tailscale"|g' "$f"
    done

    # persist tailscale state across reboots
    export TS_STATE_DIR=/etc/tailscale/state
}

# excute
do_common

# excute custom for different source
source "$GITHUB_WORKSPACE/user/common/${build_source}.sh"
