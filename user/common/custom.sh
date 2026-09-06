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

    # luci-app-mosdns requires geo2txt at image installation time.
    rm -rf package/geo2txt
    dl_git_sub https://github.com/sbwml/luci-app-mosdns package/geo2txt geo2txt v5

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

    # replace the LEDE tailscale package with GuNanOvO's latest source package
    rm -rf package/tailscale
    dl_git_sub https://github.com/GuNanOvO/openwrt-tailscale package/tailscale package/tailscale main

    # move tailscale menu from Services to VPN
    find package/luci-app-tailscale-community -path '*/menu.d/*.json' | while read f; do
        sed -i 's|"admin/services/tailscale"|"admin/vpn/tailscale"|g' "$f"
    done

    # persist tailscale state across reboots
    export TS_STATE_DIR=/etc/tailscale/state

    # bundle the latest statically linked Orbien client for the target CPU
    case "$build_arch" in
    amd64)
        orbien_arch="amd64"
        ;;
    arm64)
        orbien_arch="arm64"
        ;;
    *)
        orbien_arch=""
        ;;
    esac
    if [ -n "$orbien_arch" ]; then
        orbien_version=$(curl -fsSL https://api.github.com/repos/orbien-org/orbien/releases/latest | awk -F '"' '/"tag_name"/ { print $4; exit }' | sed 's/^v//')
        if [ -z "$orbien_version" ]; then
            echo "Error: Unable to determine the latest Orbien version"
            return 1
        fi
        orbien_archive="orbien_${orbien_version}_linux_${orbien_arch}_musl.tar.gz"
        orbien_tmp=$(mktemp -d)
        curl -fsSL "https://github.com/orbien-org/orbien/releases/download/v${orbien_version}/${orbien_archive}" -o "$orbien_tmp/orbien.tar.gz"
        tar -xzf "$orbien_tmp/orbien.tar.gz" -C "$orbien_tmp"
        install -Dm755 "$orbien_tmp/orbien" files/usr/bin/orbien
        rm -rf "$orbien_tmp"
    fi
}

# excute
do_common

# excute custom for different source
source "$GITHUB_WORKSPACE/user/common/${build_source}.sh"
