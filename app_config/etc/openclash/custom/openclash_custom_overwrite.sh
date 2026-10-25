#!/bin/sh
. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh

# OpenClash runs this after its own DNS, sniffer, and rule transformations.
# Keep ordinary rules in openclash_custom_rules.list; use this hook only for
# idempotent structural fixes that must also apply to downloaded profiles.
CONFIG_FILE="$1"
[ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ] || exit 0

LOG_TIP "Applying local Mihomo compatibility overrides..."

# Mihomo 1.19.30 removed the global form. Per-proxy client-fingerprint
# remains valid and is left untouched.
ruby_delete "$CONFIG_FILE" "" "global-client-fingerprint"

# Process matching is unnecessary overhead for forwarded router traffic.
# Mihomo's documentation recommends off on routers.
ruby_edit "$CONFIG_FILE" "['find-process-mode']" "'off'"

# Reapply manual AI country/US-AI choices and working country icon URLs,
# including the small built-in OpenAI domain safety net.
if ! ruby -E UTF-8 "$(dirname "$0")/openclash_ai_policy.rb" "$CONFIG_FILE"; then
    LOG_TIP "Failed to apply the AI stability policy; inspect this profile."
    exit 1
fi

# Preserve the dedicated Docker choice, repair only its known old rule URL,
# and keep the preloaded supplement ahead of generic direct downloads.
if ! ruby -E UTF-8 "$(dirname "$0")/openclash_docker_policy.rb" "$CONFIG_FILE"; then
    LOG_TIP "Failed to apply the Docker rules policy; inspect this profile."
    exit 1
fi

exit 0
