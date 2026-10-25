# Public OpenWrt template rules

- This is the sanitized public repository. Never copy private GitLab history, identities, subscriptions, accounts, production network inventories or raw backups into it.
- Keep public templates empty by default: no Tailscale state/manual restore, proxy nodes, ZeroTier network IDs or Beszel credentials. Keep unconfigured services disabled and management APIs loopback-only.
- Run scripts/validate-public-config.py and the functional regression suite before publishing. Inspect staged files, not only ignore patterns.
- Fetch MosDNS only from the pinned public GitHub submodule. Preserve its GPL license, credits and original copyright headers.
- Preserve attribution to alecthw/openwrt-actions and all directly integrated projects in CREDITS.md.
- Keep firmware workflows manual-only. Ordinary pushes must not compile, release or synchronize upstream automatically.
- Retain existing OpenClash AI/US-AI, scoped QUIC, Docker routing, MosDNS hosts, Tailscale compatibility and Argon dependency gates.
- Do not change private repositories or live routers while maintaining this public template.
