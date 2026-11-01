# Antigravity / Gemini routing

2026-11-01: Antigravity and Gemini use the existing `Google` strategy, not `AI`.

- All three profiles map `RULE-SET,Gemini` to Google, including the complete upstream Gemini domain/keyword list.
- Explicit fallback domains are `antigravity.google`, `gemini.google.com` and `generativelanguage.googleapis.com`; they follow the existing five scoped QUIC guards and precede general routing. The overwrite and custom-rule list retain the same policy.
- The final overwrite repairs legacy AI-targeted Gemini provider rules and explicit rules for these domains, without creating a missing Google group/provider or modifying unrelated AI, direct or user-domain rules. Repeated execution is idempotent.
- OpenAI, Claude and Copilot remain in AI. Existing Google/AI/node selections, subscriptions, DNS, credentials, scoped UDP/443 rejection and other rules are preserved. This is a routing-group change, not a node switch or a QUIC exception.
- Run `scripts/test-openclash-google-routing.rb` through the standard personal/public configuration gate. Source checks are not a firmware build or proof of service-region eligibility.
