## 2026-10-25 - public CI Ruby/Psych compatibility

- User-approved GitHub host toolchain upgrade: select Ruby 3.4.12 through a commit-pinned official setup-ruby action, verify the actual interpreter and retain older-runtime-safe parsing.

- Use safe_load_file for AI/US-AI/Docker fixtures and firmware helpers, add an API/security smoke gate and Docker semantic coverage, and validate both manual targets before swap/disk allocation. No private GitLab or live-router changes.

## 2026-10-25 - Tailscale upstream refresh

- Adopt upstream #80/#81 architecture and truthful firewall job status; update exact-anchor compatibility guards and fresh-source CI regressions. Refresh source for both firmware editions; preserve private/public configuration separation.

# Changelog

## 2026-10-25

- Third follow-up: restore approved LAN6 DHCPv6-client and dnsmasq3553/cache-off/MosDNS5335 forwarding defaults; retain empty identity/account templates. Update allowlist and fixtures without running extra checks, as requested; manually build the public x86 template.

- Second follow-up: also delete logical WAN/WAN6 idempotently and disable LAN IPv4 DHCP as explicitly approved; keep IPv6 and DNS customization pending. Extend isolated boot/negative regression checks.

- Follow-up: retain only user-approved public LAN 192.168.11.4 and gateway 192.168.11.1. Add exact allowlist and isolated first-boot tests; do not restore production DHCP/WAN/IPv6 settings.

- Publish the current reusable OpenWrt customizations as sanitized templates, without private configuration or history.
- Preserve proxy/DNS/UI/package improvements and regressions; change only private-specific validation to public-safe invariants.
- Pin the public MosDNS source with upstream attribution; preserve MIT and component-specific licenses.
- Disable unconfigured services and scheduled workflows, replace the personal wallpaper and add public publication checks.
