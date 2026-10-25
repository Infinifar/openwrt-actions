#!/usr/bin/env bash
set -euo pipefail
scripts_dir=$(cd "$(dirname "$0")" && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
build="$fixture/build"
target="$build/bin/targets/x86/64"
kernel="$build/build_dir/target-x86_64_musl/linux-x86_64/linux-test"
rootfs="$build/build_dir/target-x86_64_musl/root-x86"
mkdir -p "$target/packages" "$kernel" "$rootfs/usr/lib/iptables" "$rootfs/lib/modules/test"
printf '%s\n' 'CONFIG_TARGET_ROOTFS_PARTSIZE=2048' 'CONFIG_PACKAGE_iptables-mod-conntrack-extra=y' 'CONFIG_PACKAGE_kmod-ipt-conntrack-extra=y' > "$build/.config"
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' 'CONFIG_NETFILTER_XT_CONNMARK=m' > "$kernel/.config"
# Nonempty payload fixtures, not executable libraries or a loadable module.
for plugin in libxt_connmark.so libxt_CONNMARK.so; do
    printf 'fixture plugin\n' > "$rootfs/usr/lib/iptables/$plugin"
done
module="$rootfs/lib/modules/test/xt_connmark.ko"
printf 'fixture kernel module\n' > "$module"
manifest="$target/openwrt-x86-64-generic.manifest"
required=(beszel-agent luci-app-openclash tailscale luci-app-tailscale-community zerotier luci-app-zerotier qemu-ga iptables-mod-conntrack-extra kmod-ipt-conntrack-extra)
for package in "${required[@]}"; do printf '%s - 1.0\n' "$package"; done > "$manifest"
printf 'Package: unrelated\nVersion: 1.0\n\n' > "$target/packages/Packages.manifest"
printf 'not an image checksum\n' > "$target/packages/sha256sums"
printf 'fixture firmware, not a bootable image\n' > "$target/openwrt-test.img.gz"
(cd "$target" && sha256sum --binary openwrt-test.img.gz > sha256sums)

expect_fail() {
    local label=$1
    shift
    if "$@" > "$fixture/failure.log" 2>&1; then
        echo "FAIL (unexpected success): $label" >&2; exit 1
    fi
    printf 'PASS: %s\n' "$label"
}

bash "$scripts_dir/validate-firmware-output.sh" "$build"
printf 'PASS: image manifest accepted with nested package index\n'
sed '/^beszel-agent - /d' "$manifest" > "$fixture/manifest-missing"
cp "$manifest" "$fixture/complete.manifest"
cp "$fixture/manifest-missing" "$manifest"
expect_fail 'missing required package rejected' bash "$scripts_dir/validate-firmware-output.sh" "$build"
cp "$fixture/complete.manifest" "$manifest"
cp "$build/.config" "$fixture/complete.config"
for package in iptables-mod-conntrack-extra kmod-ipt-conntrack-extra; do
    sed "/^${package} - /d" "$fixture/complete.manifest" > "$manifest"
    expect_fail "missing $package from image manifest rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    cp "$fixture/complete.manifest" "$manifest"
    sed "/^CONFIG_PACKAGE_${package}=/d" "$fixture/complete.config" > "$build/.config"
    expect_fail "unselected $package rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    sed "s/^CONFIG_PACKAGE_${package}=y$/CONFIG_PACKAGE_${package}=m/" "$fixture/complete.config" > "$build/.config"
    expect_fail "module-only $package rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    cp "$fixture/complete.config" "$build/.config"
done
for package in luci-app-ssr-plus nginx nginx-ssl frpc frps ddns-scripts ddns-scripts-cloudflare; do
    printf '%s - 1.0\n' "$package" >> "$manifest"
    expect_fail "$package rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    cp "$fixture/complete.manifest" "$manifest"
done
mv "$manifest" "$fixture/hidden.manifest"
expect_fail 'package index alone is not a firmware manifest' bash "$scripts_dir/validate-firmware-output.sh" "$build"
mv "$fixture/hidden.manifest" "$manifest"
printf '# CONFIG_VIRTIO_BALLOON is not set\n' > "$kernel/.config"
expect_fail 'missing balloon support rejected' bash "$scripts_dir/validate-firmware-output.sh" "$build"
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' 'CONFIG_NETFILTER_XT_CONNMARK=m' > "$kernel/.config"
for plugin in libxt_connmark.so libxt_CONNMARK.so; do
    mv "$rootfs/usr/lib/iptables/$plugin" "$fixture/$plugin"
    expect_fail "missing $plugin in rootfs rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    : > "$rootfs/usr/lib/iptables/$plugin"
    expect_fail "empty $plugin in rootfs rejected" bash "$scripts_dir/validate-firmware-output.sh" "$build"
    mv "$fixture/$plugin" "$rootfs/usr/lib/iptables/$plugin"
done
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' '# CONFIG_NETFILTER_XT_CONNMARK is not set' > "$kernel/.config"
expect_fail 'missing kernel connmark support rejected' bash "$scripts_dir/validate-firmware-output.sh" "$build"
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' 'CONFIG_NETFILTER_XT_CONNMARK=m' > "$kernel/.config"
mv "$module" "$fixture/xt_connmark.ko"
expect_fail 'missing modular connmark payload rejected' bash "$scripts_dir/validate-firmware-output.sh" "$build"
: > "$module"
expect_fail 'empty modular connmark payload rejected' bash "$scripts_dir/validate-firmware-output.sh" "$build"
rm -- "$module"
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' 'CONFIG_NETFILTER_XT_CONNMARK=y' > "$kernel/.config"
bash "$scripts_dir/validate-firmware-output.sh" "$build" >/dev/null
printf 'PASS: built-in kernel connmark accepted without a separate module\n'
mv "$fixture/xt_connmark.ko" "$module"
printf '%s\n' 'CONFIG_VIRTIO_BALLOON=y' 'CONFIG_NETFILTER_XT_CONNMARK=m' > "$kernel/.config"

bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/export" > "$fixture/export.log"
test -f "$fixture/export/openwrt-x86-64-generic.manifest"
test ! -e "$fixture/export/Packages.manifest"
cmp "$target/sha256sums" "$fixture/export/sha256sums"
printf 'PASS: export excludes repository indexes and retains original image checksums\n'
(cd "$target" && sha256sum --text openwrt-test.img.gz > sha256sums)
bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/text-mode-export" > "$fixture/text-mode.log"
printf 'PASS: binary and text checksum formats accepted\n'
expect_fail 'non-empty output directory preserved' bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/export"
mkdir -p "$build/bin/targets/other/64"
cp "$target/sha256sums" "$build/bin/targets/other/64/sha256sums"
expect_fail 'duplicate export filenames rejected' bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/duplicate"
rm -- "$build/bin/targets/other/64/sha256sums"
printf 'unlisted firmware\n' > "$target/unlisted.img.gz"
expect_fail 'unlisted image checksum rejected' bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/unlisted"
rm -- "$target/unlisted.img.gz"
printf 'changed\n' >> "$target/openwrt-test.img.gz"
expect_fail 'invalid original checksum rejected' bash "$scripts_dir/export-firmware-output.sh" "$build" "$fixture/corrupt"
printf 'Firmware-output regression tests passed.\n'
