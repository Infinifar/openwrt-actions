# Dedicated GitHub routing

2026-11-01: all three OpenClash profiles provide a manual `GitHub` strategy.

- Default: `Proxy`, then the available US country, optional `US-AI`, SG/JP/HK/TW. Only groups present in that profile are referenced; Only_CN does not gain a missing TW group. Proxy remains US-first; existing stored selections and country Auto/Manual behavior are not migrated.
- The complete public provider comes directly from [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script/blob/master/rule/Clash/GitHub/GitHub.yaml), updates every 12 hours, and precedes broad direct/download/advertising/media rules. It includes associated services such as npm, not just github.com.
- Eight built-in GitHub domain fallbacks cover the website, API, raw/releases/assets and related domains even before provider availability. `api.githubcopilot.com` explicitly uses GitHub for the remote GitHub MCP; a normal hostname rule cannot distinguish its `/mcp` path from other requests to that host.
- `ghcr.io` keeps the Docker strategy ahead of the broader GitHub list. Other Copilot/OpenAI/Claude/Gemini policies and the existing scoped QUIC guards remain unchanged.
- `openclash_github_policy.rb` runs after the AI and Docker hooks, deduplicates/repositions only its owned routes, installs/repairs only the known GitHub provider, and refuses custom provider URL/target collisions without writing. A profile without a GitHub group remains byte-identical.
- No DNS, IPv6, controller credentials, subscription, firewall, BT/PT, device identity or live-node selection changes. Applying routing rules is not proof of region eligibility or of an IPv4-only exit.
- Run `ruby scripts/test-openclash-github-routing.rb` (also part of the normal configuration gate). Fixtures cover all three profiles, repeated combined overwrites, missing providers/groups, collision failures, permissions and preservation of unrelated settings.

This is a repository policy update, not a firmware build or live-router deployment.
