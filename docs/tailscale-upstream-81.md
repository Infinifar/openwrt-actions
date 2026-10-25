# Tailscale LuCI upstream #81 adoption (2026-10-25)

Upstream confirmed the reverse-proxy XHR/reporting defect in [issue #81](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community/issues/81).
[PR #84](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community/pull/84) was merged as 7b6869492fc0545039b41cc77eae6d2138f4f3ee.
Reviewed current master: a7057cb209b8000e97cb8bc3e56fec4b26a1f27b (2026-10-24).

Every firmware preparation still refreshes master, not this snapshot or an old cache.
The daemon package independently refreshes GuNanOvO/openwrt-tailscale main.
The review record is provenance, not a frozen package pin or proof of a completed firmware build.

## Integration

- Keep upstream get_firewall_status, per-job run_id, background worker, UI error handling and new settings-service lifecycle.
- Do not install the former local tailscale.actions/get_apply_status/worker over the new upstream implementation. Historical local assets are no longer installed.
- Remaining exact-anchor guards: reject failed UCI commits; apply committed settings after login; bound CLI to 30 seconds and service reloads to 45 seconds; explicitly restore netfilter=on when requested.
- Delay the first worker reload by two seconds; apply Tailscale settings before reporting done; keep upstream failed/busy states and lock. The UI's click-triggered result wait is bounded to 180 seconds, not an ongoing monitor.
- Missing upstream fix contracts or changed patch anchors are build failures, never reasons to reuse old code. Validate the real fresh worker only with disposable paths and mocked init scripts.
- Keep nftables defaults and existing route/DNS/relay policy. Do not change live devices or automatically approve routes.

The GitLab private firmware retains its private configuration. The GitHub public template remains identity/account/subscription-free and disabled until configured.
The user requested one build of each edition without continuous monitoring.
