# Ruby/Psych compatibility in public CI

## Verification on 2026-10-25

- Ruby 3.0.7 / Psych 3.3.2: reproduced the original unknown-aliases-keyword error;
  new capability check and AI 14 / US-AI 17 / Docker 9 fixtures all passed.
- Ruby 3.4.12 / Psych 5.2.2: exact selected-version check and the same fixtures passed.
- Isolated official Ruby containers used read-only roots, no network, dropped
  capabilities and disposable tmpfs; no firmware build or live service ran there.
- Omarchy Ruby 3.4.10 additionally passed the full public-config gate, privacy
  negative/positive tests, MosDNS, Argon and Tailscale regressions. A simulated
  GitHub invocation correctly rejected 3.4.10 rather than silently using it.
- Both workflows' Ruby selection and early-validation ordering were checked.
  The newly triggered GitHub firmware build still needs its own final result.

The public x86 run [40178519659](https://github.com/Infinifar/openwrt-actions/actions/runs/40178519659)
failed before cloning LEDE: Ubuntu 22.04's Ruby 3.0/Psych rejected the aliases
keyword forwarded by YAML.load_file in the AI regression suite.

## Fix

- Use YAML.safe_load_file(..., aliases: true) consistently in AI/US-AI/Docker
  fixtures and installed OpenClash AI/Docker helpers. This preserves YAML aliases
  and file decoding while rejecting arbitrary Ruby object tags; no unsafe fallback.
- Per user approval, GitHub CI selects maintained Ruby 3.4.12 from .ruby-version
  using the official ruby/setup-ruby action pinned to a reviewed commit. Install
  it after apt cleanup and require the selected version; never fall back to apt's
  Ruby 3.0. No change to the firmware's target Ruby or private GitLab environment.
- scripts/check-ruby-yaml.rb exercises aliases/merge keys, UTF-8 BOM, scalar
  preservation, dump/read idempotence, and rejection of object tags, unresolved
  aliases and syntax errors. It also rejects obsolete loaders in the owned files.
- Keep all privacy, DNS, theme, AI and US-AI gates; run Docker semantics too.
- Both manual workflows run the full configuration gate after dependencies are
  installed, before allocating swap and the simulated disk. Ordinary pushes still
  do not build. A test pass is not evidence of completed firmware compilation.

Scope: sanitized GitHub template only. Private GitLab, router configuration and
running services are unchanged.

Reference: [Ruby 3.0 Psych API](https://ruby-doc.org/stdlib-3.0.0/libdoc/psych/rdoc/Psych.html#method-c-safe_load_file).
