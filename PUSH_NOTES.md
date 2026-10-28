# Push notes

## 2026-10-28 - public US-first Proxy and optional US-AI

- Apply only the generic routing-policy patch on existing public history: three manual Proxy lists prefer their existing US country, append US-AI once, and keep every other option in its relative order. The final helper repairs the same layout idempotently.
- Preserve AI/Google defaults, country Auto/Manual behavior, safe YAML loading, empty subscriptions/accounts/identities and loopback management. Do not import private files/history or mutate private repositories/live services.
- Validate the public privacy gate, functional regressions and source-YAML semantic scope before publishing. List ordering does not override saved runtime selections.
- Validation passed on host Ruby 3.4.10/Psych 5.2.2: public privacy and personal-config gates, all Python/Node/shell/Ruby functional regressions (including AI19/US-AI17/Docker9 and public12 fixtures), whitespace checks, and semantic comparison restricting each source YAML change to Proxy.proxies. The pinned GitHub CI Ruby remains 3.4.12; no firmware or CI execution is claimed.
- Publish only the reviewed public commit to Infinifar/openwrt-actions after review. No build, workflow dispatch or continuous monitoring is requested by this routing-policy synchronization.

- User subsequently approved upgrading CI Ruby: .ruby-version pins 3.4.12; both workflows select it after apt cleanup through the official action at 7f797815d8adceb1c412e7abefdd1ab4abc47a5f, with an actual-runtime check. Target firmware Ruby/private GitLab remain unchanged.

## 2026-10-25 - repair public GitHub YAML gate

- Replace unsupported load_file/aliases calls with safe_load_file and retain alias/scalar semantics while refusing Ruby object tags. Keep all existing gates and add Docker/YAML capabilities; move configuration checks ahead of swap/disk creation in both manual workflows.
- Validate before pushing to public GitHub; trigger only the x86 workflow once, without continuous monitoring. Do not modify private GitLab or live services. See docs/ruby-yaml-ci.md.

## 2026-10-25 - refresh Tailscale LuCI after upstream #81

- Adopt fresh master containing upstream #80/#81, retain its UI/status/worker/lifecycle and replace the incompatible legacy patch with narrow firmware guards. Preserve private/public separation and all device policies.
- Trigger one manual x86 build in the appropriate GitLab/GitHub service after pushing; no live-router changes or continuous monitoring. See docs/tailscale-upstream-81.md.

Destination: existing public GitHub repository Infinifar/openwrt-actions, master.

Follow-ups: approved public networking now includes LAN192.168.11.4/gateway192.168.11.1, WAN/WAN6 removal, LAN IPv4 DHCP off, LAN6 DHCPv6 client on LAN and dnsmasq3553 with cache/redirection off and local MosDNS5335 forwarding. Original credentials, identities, MAC/SSH and RA/DHCPv6-server customization remain excluded; private GitLab and live devices stay untouched.

This is a reviewed file-level export on top of existing public history, not a private mirror. Accounts, subscriptions, device state, deployment inventory and private GitLab CI are excluded. The private source is read-only and unchanged.

MosDNS is published separately with its original license and attribution; the firmware points at its public commit. For this follow-up the user requested no extra checks: regression fixtures/allowlist are updated but not executed by the agent. Trigger the manual GitHub x86 build after publishing, without continuous status monitoring.
