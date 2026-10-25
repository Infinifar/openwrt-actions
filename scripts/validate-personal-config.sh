#!/bin/sh
set -eu

# Probe the actual YAML API and reject unsafe/obsolete loaders before other gates.
ruby scripts/check-ruby-yaml.rb

fail() {
    printf 'personal config validation failed: %s\n' "$*" >&2
    exit 1
}

must_contain() {
    file="$1"
    value="$2"
    grep -Fq -- "$value" "$file" || fail "$file does not contain: $value"
}

must_not_match() {
    file="$1"
    pattern="$2"
    if grep -Eq -- "$pattern" "$file"; then
        fail "$file matches forbidden pattern: $pattern"
    fi
}

adguard="app_config/etc/AdGuardHome/AdGuardHome.yaml"
mosdns="app_config/etc/mosdns/config_custom.yaml"
openclash_uci="app_config/etc/config/openclash"

for target_config in user/lede-openclash-x86-amd64/config.diff user/lede-common-n1-arm64/config.diff; do
    for package in iptables-mod-conntrack-extra kmod-ipt-conntrack-extra; do
        grep -Fxq "CONFIG_PACKAGE_${package}=y" "$target_config" || \
            fail "$package must be built into the firmware image in $target_config"
    done
done

# Lock the original wallpaper and the two targets' explicit Argon dependencies.
python3 -B scripts/validate-argon.py source .
# Both DNS paths must derive their exact LAN records from AdGuard, not a third list.
ruby scripts/test-mosdns-lan-hosts.rb
python3 -B scripts/test-mosdns-init.py
# Keep the firmware defaults aligned with the deployed persistent layout.
must_contain "$adguard" '  filters_update_interval: 24'
must_contain "$adguard" 'http_proxy: http://127.0.0.1:7890'
must_contain "$openclash_uci" "option http_port '7890'"
must_contain "$openclash_uci" "option mixed_port '7893'"
must_contain app_config/etc/config/AdGuardHome "option workdir '/etc/AdGuardHome/work'"
must_contain user/common/files/etc/config/adguardhome "option work_dir '/etc/AdGuardHome/work'"
must_contain user/common/files/etc/config/adguardhome "list jail_mount_rw '/etc/AdGuardHome/work'"
persistent_paths="$(grep -Ec '^  dir_path: /etc/AdGuardHome/work/data$' "$adguard" || true)"
[ "$persistent_paths" -eq 2 ] || fail 'AdGuard log/statistics paths must match persistent work/data'
must_contain "$adguard" '  file_enabled: false'
storage_hook=user/common/files/etc/init.d/adguardhome-storage
[ -x "$storage_hook" ] || fail 'AdGuard storage boot hook must be executable'
must_contain "$storage_hook" 'START=18'
must_contain "$storage_hook" 'config_dir=/etc/AdGuardHome'
migration=user/common/files/etc/uci-defaults/zzzz-adguardhome-persist-v2
[ -x "$migration" ] || fail 'AdGuard upgrade migration must be executable'
must_contain "$migration" '/etc/init.d/adguardhome-storage start'
must_contain "$migration" 'persist-settings.awk'
keep=user/common/files/lib/upgrade/keep.d/lede-personal-services
must_contain "$keep" '/etc/AdGuardHome/'
must_contain "$keep" '/etc/tailscale/'
must_contain app_config/etc/config/tailscale "option fw_mode 'nftables'"
must_contain app_config/etc/config/tailscale "option accept_routes '0'"
must_contain app_config/etc/config/tailscale "option advertise_exit_node '0'"
must_contain app_config/etc/config/tailscale "option dns_mode 'disabled'"
must_contain user/common/files/etc/uci-defaults/zzzz-tailscale-lan-policy-v1 \
    "uci set tailscale.settings.accept_routes='0'"
python3 -B scripts/validate-public-config.py
must_contain "$adguard" "@@||dns.weixin.qq.com.cn^"

must_contain "$mosdns" "lazy_cache_ttl: 300"
must_contain "$mosdns" "dump_file: \"/tmp/mosdns-cache.dump\""
must_contain "$mosdns" "- tag: DNSPod_dot"
must_contain "$mosdns" "- tag: Ali_dot"
must_not_match "$mosdns" "^[[:space:]]*-[[:space:]]*tag:[[:space:]]*OneDNS_dot"
must_contain "$mosdns" "- qtype 64 65"
must_contain "$mosdns" "exec: reject 0"

must_contain "$openclash_uci" "option ipv6_enable '0'"
must_contain "$openclash_uci" "option ipv6_dns '0'"
must_contain "$openclash_uci" "option smart_enable '0'"
must_contain "$openclash_uci" "option auto_smart_switch '0'"

for profile in \
    app_config/etc/openclash/config/APP_Rule_Auto.yaml \
    app_config/etc/openclash/config/APP_Rule_Manual.yaml \
    app_config/etc/openclash/config/Only_CN_Rule_Auto.yaml
do
    must_contain "$profile" 'url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Docker/Docker.yaml'
    must_contain "$profile" 'url: https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/docker.mrs'
    must_contain "$profile" 'path: ./rule_provider/DockerHubExtra.mrs'
    must_contain "$profile" 'format: mrs'
    extra_line="$(grep -nFx '  - RULE-SET,DockerHubExtra,Docker' "$profile" | cut -d: -f1)"
    docker_line="$(grep -nFx '  - RULE-SET,Docker,Docker' "$profile" | cut -d: -f1)"
    download_line="$(grep -nFx '  - RULE-SET,Download,Domestic' "$profile" | cut -d: -f1)"
    [ "$extra_line" -lt "$docker_line" ] && [ "$docker_line" -lt "$download_line" ] || fail "Docker rules must precede generic downloads in $profile"
    must_not_match "$profile" 'DOMAIN-SUFFIX,(r2\.cloudflarestorage\.com|cloudflarestorage\.com|cloudflare\.com),Docker'
    must_not_match "$profile" "^[[:space:]]*ipv6:[[:space:]]*true"
    false_count="$(grep -Ec "^[[:space:]]*ipv6:[[:space:]]*false" "$profile" || true)"
    [ "$false_count" -eq 2 ] || fail "expected two ipv6: false entries in $profile, found $false_count"
    ai_group="$(awk '/^  - name: AI$/ { in_ai=1; next } in_ai && /^  - name:/ { exit } in_ai { print }' "$profile")"
    printf '%s\n' "$ai_group" | grep -Fq 'type: select' || fail "AI must be a manual selector in $profile"
    printf '%s\n' "$ai_group" | grep -Fq 'proxies:' || fail "AI must list country groups in $profile"
    printf '%s\n' "$ai_group" | grep -Fq 'empty-fallback: REJECT' || fail "AI must fail closed in $profile"
    if printf '%s\n' "$ai_group" | grep -Eq '^[[:space:]]+(include-all|filter|use|url|interval|strategy):'; then
        fail "AI must not select leaf nodes/providers or switch automatically in $profile"
    fi
    must_not_match "$profile" '^[[:space:]]*- name: AI-US$'
done
# Semantic gates preserve country defaults, manual San Jose leaves and scoped QUIC.
ruby scripts/test-openclash-ai-policy.rb
ruby scripts/test-openclash-us-ai-quic.rb
ruby scripts/test-openclash-docker-policy.rb

printf 'personal config validation passed: persistent daily AdGuard filters, no personal accounts/rewrites/identities, safe MosDNS upstreams, IPv6 policy aligned, manual AI/US-AI selectors, scoped QUIC, Docker priority, Tailscale connmark dependencies\n'
