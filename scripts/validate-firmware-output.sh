#!/usr/bin/env bash
set -euo pipefail

build_dir=$(cd "${1:?Usage: validate-firmware-output.sh BUILD_DIR}" && pwd -P)
test -f "$build_dir/.config" || { echo "Missing final OpenWrt .config." >&2; exit 1; }

for package in iptables-mod-conntrack-extra kmod-ipt-conntrack-extra; do
    grep -Fxq "CONFIG_PACKAGE_${package}=y" "$build_dir/.config" || {
        echo "Tailscale connmark dependency is not selected as =y: $package" >&2; exit 1;
    }
done

target_dir="$build_dir/bin/targets"
# Image manifests live directly in targets/<target>/<subtarget>/. The nested
# packages/Packages.manifest is an opkg repository index, not installed packages.
mapfile -d '' manifests < <(find "$target_dir" -mindepth 3 -maxdepth 3 \
    -type f -name '*.manifest' ! -name 'Packages.manifest' -print0)
(("${#manifests[@]}" > 0)) || { echo "No firmware manifest was produced." >&2; exit 1; }
for manifest in "${manifests[@]}"; do
    for required in beszel-agent luci-app-openclash tailscale luci-app-tailscale-community zerotier luci-app-zerotier qemu-ga iptables-mod-conntrack-extra kmod-ipt-conntrack-extra; do
        grep -qE "^${required} - " "$manifest" || { echo "Missing package: $required ($manifest)" >&2; exit 1; }
    done
    if grep -qE '^(luci-app-(ssr-plus|nginx|frpc|frps|ddns|ddns-go)|nginx([_-][^ ]+)?|frpc|frps|ddns-go|ddns-scripts([_-][^ ]+)?) - ' "$manifest"; then
        echo "A removed proxy, nginx, FRP, or DDNS package is present: $manifest" >&2
        exit 1
    fi
done

mapfile -d '' kernel_configs < <(find "$build_dir/build_dir" -path '*/linux-x86_64/linux-*/.config' -type f -print0)
(("${#kernel_configs[@]}" > 0)) || { echo "No x86 kernel config was produced." >&2; exit 1; }
for kernel_config in "${kernel_configs[@]}"; do
    grep -Fxq "CONFIG_VIRTIO_BALLOON=y" "$kernel_config" || { echo "Built-in VirtIO balloon support is missing." >&2; exit 1; }
    grep -Eq '^CONFIG_NETFILTER_XT_CONNMARK=[my]$' "$kernel_config" || {
        echo "Kernel connmark support is missing: $kernel_config" >&2; exit 1;
    }
done

# Inspect the installed image root, not just package metadata or staging files.
mapfile -d '' roots < <(find "$build_dir/build_dir" -mindepth 2 -maxdepth 2 \
    -type d -name root-x86 -print0)
(( ${#roots[@]} == 1 )) || { echo "Expected exactly one installed x86 rootfs." >&2; exit 1; }
rootfs=${roots[0]}
for plugin in libxt_connmark.so libxt_CONNMARK.so; do
    test -s "$rootfs/usr/lib/iptables/$plugin" || {
        echo "Installed connmark userspace extension is missing or empty: $plugin" >&2; exit 1;
    }
done
if grep -Fxq 'CONFIG_NETFILTER_XT_CONNMARK=m' "${kernel_configs[@]}"; then
    mapfile -d '' modules < <(find "$rootfs/lib/modules" -type f -size +0c \
        \( -name xt_connmark.ko -o -name xt_connmark.ko.gz -o -name xt_connmark.ko.xz -o -name xt_connmark.ko.zst \) -print0)
    (( ${#modules[@]} > 0 )) || { echo "Installed xt_connmark kernel module is missing." >&2; exit 1; }
fi

echo "Firmware manifests, connmark payloads and built-in VirtIO Balloon support verified."
