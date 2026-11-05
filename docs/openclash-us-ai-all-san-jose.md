# US-AI: all San Jose node names

2026-11-05: US-AI includes every provider or inline leaf whose full name contains `美国圣何塞`.

- Filter: `美国圣何塞`. No digit condition, translation or extra country inference.
- Names with 01/02/04/08/99, or no number, now qualify; US Los Angeles and Japanese San Jose do not.
- All three templates and the final AI overwrite use the same filter. Keep `type: select`, both include-all flags, reject-empty and store-selected behavior.
- Keep existing selections when still present, and do not change AI/Google/GitHub/Proxy defaults, country Auto/Manual behavior, QUIC, DNS, IPv6 or subscriptions.
- Run the US-AI/QUIC, AI, Google, GitHub and Docker regression gates plus the normal configuration validator. Offline checks do not establish live deployment success.
- This update does not build firmware. Live changes require a backup, core config check, reload and API verification of membership and selections.
