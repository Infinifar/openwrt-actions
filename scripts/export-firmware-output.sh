#!/usr/bin/env bash
set -euo pipefail

build_dir=$(cd "${1:?Usage: export-firmware-output.sh BUILD_DIR OUTPUT_DIR}" && pwd -P)
output=${2:?Output directory is required.}
target_dir="$build_dir/bin/targets"
test -f "$build_dir/.config"

# Do not descend into packages/: its indexes/checksums have different meanings
# and may otherwise overwrite the image-level files when flattening the export.
mapfile -d '' artifacts < <(find "$target_dir" -mindepth 3 -maxdepth 3 -type f \
    \( -name '*.img.gz' -o -name '*.manifest' -o -name '*.buildinfo' \
    -o -name profiles.json -o -name sha256sums \) ! -name Packages.manifest -print0)
(( ${#artifacts[@]} > 0 )) || { echo 'No image artifacts found.' >&2; exit 1; }

mkdir -p "$output"
output=$(cd "$output" && pwd -P)
[[ -z $(find "$output" -mindepth 1 -maxdepth 1 -print -quit) ]] || {
    echo 'Output directory must be empty; existing files will not be overwritten.' >&2
    exit 1
}
cp "$build_dir/.config" "$output/config"
for artifact in "${artifacts[@]}"; do
    name=${artifact##*/}
    [[ ! -e "$output/$name" ]] || { echo "Duplicate artifact name: $name" >&2; exit 1; }
    cp "$artifact" "$output/$name"
done
find "$output" -maxdepth 1 -type f -name '*.img.gz' -print -quit | grep -q . || {
    echo 'No firmware image was exported.' >&2; exit 1;
}
test -f "$output/sha256sums"
# Verify the original build's checksums before creating the export checksum set.
for image in "$output"/*.img.gz; do
    checksum_line=$(cd "$output" && sha256sum -- "${image##*/}")
    checksum=${checksum_line:0:64}
    # OpenWrt emits binary-mode lines (hash *name); also accept text mode.
    grep -Fxq "$checksum  ${image##*/}" "$output/sha256sums" || \
    grep -Fxq "$checksum *${image##*/}" "$output/sha256sums" || {
        echo "Image checksum missing or incorrect: ${image##*/}" >&2; exit 1;
    }
done
(cd "$output" && sha256sum --check --ignore-missing sha256sums)

{
    printf 'source_commit=%s\n' "${CI_COMMIT_SHA:-unknown}"
    printf 'source_job_id=%s\n' "${CI_JOB_ID:-unknown}"
} > "$output/BUILD_PROVENANCE.txt"
(
    cd "$output"
    find . -maxdepth 1 -type f ! -name SHA256SUMS.selected -print0 \
        | sort -z | xargs -0 sha256sum > SHA256SUMS.selected
    sha256sum --check SHA256SUMS.selected
)
ls -lh "$output"
