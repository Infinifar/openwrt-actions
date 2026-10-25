# Changelog

## 2026-10-25

- Follow-up: retain only user-approved public LAN 192.168.11.4 and gateway 192.168.11.1. Add exact allowlist and isolated first-boot tests; do not restore production DHCP/WAN/IPv6 settings.

- Publish the current reusable OpenWrt customizations as sanitized templates, without private configuration or history.
- Preserve proxy/DNS/UI/package improvements and regressions; change only private-specific validation to public-safe invariants.
- Pin the public MosDNS source with upstream attribution; preserve MIT and component-specific licenses.
- Disable unconfigured services and scheduled workflows, replace the personal wallpaper and add public publication checks.
