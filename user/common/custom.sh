#!/bin/bash

set -e

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

    # Replace feeds/helloworld/mosdns and feeds/packages/net/mosdns. The core
    # is pinned as a public GitHub submodule and includes stats_api while
    # retaining alecthw's MMDB changes. Copying the checked-out source here
    # does not require a deploy token in OpenWrt download metadata.
    rm -rf package/mosdns
    dl_git_sub https://github.com/sbwml/luci-app-mosdns package/mosdns mosdns v5
    rm -rf package/mosdns/patches
    mosdns_source_dir="$GITHUB_WORKSPACE/sources/mosdns"
    [ -f "$mosdns_source_dir/go.mod" ] || {
        echo "Error: Missing public MosDNS submodule. Run: git submodule update --init --recursive"
        return 1
    }
    rm -rf package/mosdns/src
    mkdir -p package/mosdns/src
    cp -af "$mosdns_source_dir/." package/mosdns/src/
    rm -rf package/mosdns/src/.git
    cp -f "$GITHUB_WORKSPACE/user/common/packages/mosdns/Makefile" package/mosdns/Makefile

    # luci-app-mosdns requires geo2txt at image installation time.
    rm -rf package/geo2txt
    dl_git_sub https://github.com/sbwml/luci-app-mosdns package/geo2txt geo2txt v5

    # Remove the unused SSR Plus package, including its unconditional Kconfig
    # defaults which can select redundant proxy cores even with its UI disabled.
    if [ -d feeds/helloworld/luci-app-ssr-plus ]; then
        rm -rf feeds/helloworld/luci-app-ssr-plus
        ./scripts/feeds update -i helloworld
    fi

    # add openclash | replace feeds/luci/applications/luci-app-openclash
    rm -rf package/luci-app-openclash
    dl_git_sub https://github.com/vernesong/OpenClash package/luci-app-openclash luci-app-openclash master
    sed -i "/dashboard_password/d" package/luci-app-openclash/root/etc/uci-defaults/luci-openclash

    # add luci-app-fancontrol
    rm -rf package/luci-app-fancontrol
    dl_git_sub https://github.com/rockjake/luci-app-fancontrol package/luci-app-fancontrol luci-app-fancontrol
    rm -rf package/fancontrol
    dl_git_sub https://github.com/rockjake/luci-app-fancontrol package/fancontrol fancontrol

    # add luci-app-tailscale-community
    rm -rf package/luci-app-tailscale-community
    dl_git_sub https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community package/luci-app-tailscale-community luci-app-tailscale-community master

    # replace the LEDE tailscale package with GuNanOvO's latest source package
    rm -rf package/tailscale
    dl_git_sub https://github.com/GuNanOvO/openwrt-tailscale package/tailscale package/tailscale main
    # Reviewed UI compatibility fixes, always after the fresh upstream checkout.
    python3 -B "$GITHUB_WORKSPACE/scripts/test-tailscale-luci.py" --upstream "$PWD/package/luci-app-tailscale-community"
    python3 -B "$GITHUB_WORKSPACE/scripts/patch-tailscale-luci.py" "$PWD"

    # Upgrade the actual OpenWrt cross-build toolchain, not the container's Go.
    # Refuse an insufficient compiler before the expensive firmware build.
    python3 "$GITHUB_WORKSPACE/scripts/update-go-toolchain.py" prepare "$PWD"

    # Replace the LEDE package-feed copy with the latest official OpenWrt
    # ZeroTier package definition.  The LuCI application remains sourced from
    # the freshly updated LEDE LuCI feed so that it matches this build's LuCI.
    rm -rf package/zerotier
    dl_git_sub https://github.com/openwrt/packages package/zerotier net/zerotier master
    [ -d feeds/luci/applications/luci-app-zerotier ] || {
        echo "Error: Missing luci-app-zerotier in the refreshed LuCI feed"
        return 1
    }
    echo "Info: ZeroTier LuCI feed @ $(git -C feeds/luci rev-parse --short=12 HEAD)"

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
        orbien_version=$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' https://github.com/orbien-org/orbien/releases/latest | sed 's#.*/tag/##; s/^v//')
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

    # Add vernette's native OpenWrt package for Beszel Agent.  Its Makefile is
    # designed for CI-injected version/architecture/hash values, so resolve and
    # pin all three here before the normal OpenWrt package build begins.
    # Also remove files left by the old binary-overlay installation.  The
    # reusable local build tree is intentionally incremental, so deleting the
    # files from this repository alone would otherwise leave stale copies in
    # OpenWrt's top-level files/ overlay.
    rm -rf files/opt/beszel-agent
    rm -f files/etc/config/beszel-agent \
        files/etc/init.d/beszel-agent \
        files/etc/uci-defaults/zzzz-beszel-agent
    rm -rf package/beszel-agent
    beszel_package_tmp=$(mktemp -d)
    if ! git clone -q --depth=1 --single-branch -b master https://github.com/vernette/beszel-agent-openwrt "$beszel_package_tmp/repository"; then
        echo "Error: Unable to download the Beszel Agent OpenWrt package"
        rm -rf "$beszel_package_tmp"
        return 1
    fi
    mkdir -p package/beszel-agent
    cp -af "$beszel_package_tmp/repository/beszel-agent/." package/beszel-agent/
    rm -rf "$beszel_package_tmp"
    [ -f package/beszel-agent/Makefile ] || {
        echo "Error: Unable to install the Beszel Agent OpenWrt package"
        return 1
    }

    case "$build_arch" in
    amd64 | arm64)
        beszel_arch="$build_arch"
        ;;
    *)
        beszel_arch=""
        ;;
    esac
    if [ -n "$beszel_arch" ]; then
        beszel_version=$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' https://github.com/henrygd/beszel/releases/latest | sed 's#.*/tag/##; s/^v//')
        if [ -z "$beszel_version" ]; then
            echo "Error: Unable to determine the latest Beszel version"
            return 1
        fi

        beszel_archive="beszel-agent_linux_${beszel_arch}.tar.gz"
        beszel_tmp=$(mktemp -d)
        if ! curl -fsSL "https://github.com/henrygd/beszel/releases/download/v${beszel_version}/beszel_${beszel_version}_checksums.txt" -o "$beszel_tmp/checksums.txt"; then
            echo "Error: Unable to download Beszel checksums"
            rm -rf "$beszel_tmp"
            return 1
        fi
        beszel_checksum=$(awk -v name="$beszel_archive" '$2 == name { print $1 }' "$beszel_tmp/checksums.txt")
        if ! echo "$beszel_checksum" | grep -qE '^[a-fA-F0-9]{64}$'; then
            echo "Error: Unable to find a valid checksum for ${beszel_archive}"
            rm -rf "$beszel_tmp"
            return 1
        fi

        sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=${beszel_version}/" package/beszel-agent/Makefile
        sed -i "s|^PKG_SOURCE:=.*|PKG_SOURCE:=\$(PKG_NAME)_linux_${beszel_arch}.tar.gz|" package/beszel-agent/Makefile
        sed -i "s/^PKG_HASH:=.*/PKG_HASH:=${beszel_checksum}/" package/beszel-agent/Makefile
        echo "Info: Beszel Agent package ${beszel_version}, arch ${beszel_arch}, SHA256 ${beszel_checksum}"
        rm -rf "$beszel_tmp"
    else
        echo "Warning: Beszel Agent package is not supported for ${build_arch}"
        rm -rf package/beszel-agent
    fi
}

# excute
# Keep errexit active inside do_common and its source-fetch helpers.
do_common

# excute custom for different source
source "$GITHUB_WORKSPACE/user/common/${build_source}.sh"
