#!/usr/bin/env bash
# Build-time refresh only. Never weaken TLS or fall back to a stale ruleset.
set -euo pipefail
destination=${1:?Usage: update-docker-rules.sh RULE_PROVIDER_DIRECTORY}
[[ -d "$destination" ]] || { echo 'Docker rules: destination directory is missing' >&2; exit 1; }
for command in curl zstd od sha256sum; do
    command -v "$command" >/dev/null || { echo "Docker rules: $command is required" >&2; exit 1; }
done
temporary=$(mktemp -d "$destination/.docker-rules.XXXXXX")
cleanup() {
    rm -f -- "$temporary/download.mrs" "$temporary/decoded"
    rmdir -- "$temporary"
}
trap cleanup EXIT
url=https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/docker.mrs
curl --fail --silent --show-error --location --retry 3 \
    --connect-timeout 10 --max-time 120 "$url" -o "$temporary/download.mrs"
# MRS is a Zstandard frame. Test frame completeness and the decoded MRS v1
# header, not the compressed bytes. Mihomo loading is tested separately.
zstd -tq "$temporary/download.mrs"
zstd -dc "$temporary/download.mrs" > "$temporary/decoded"
magic=$(od -An -tx1 -N4 "$temporary/decoded" | tr -d ' \n')
[[ "$magic" == 4d525301 ]] || { echo 'Docker rules: invalid MRS v1 header' >&2; exit 1; }
[[ $(wc -c < "$temporary/decoded") -gt 16 ]] || { echo 'Docker rules: empty/truncated MRS data' >&2; exit 1; }
chmod 644 "$temporary/download.mrs"
# Same-filesystem rename: failed downloads/checks cannot replace an old copy.
mv -f -- "$temporary/download.mrs" "$destination/DockerHubExtra.mrs"
printf 'DockerHubExtra refreshed (SHA256): '
sha256sum "$destination/DockerHubExtra.mrs"
