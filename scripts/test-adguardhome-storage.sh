#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd -P)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mock_root="$fixture/mock root"
config="$mock_root/etc/AdGuardHome"
runtime="$mock_root/var/lib/adguardhome"
hook="$repo/user/common/files/etc/init.d/adguardhome-storage"

# Execute the real hook with only its two absolute roots redirected into a
# private fixture.  No host /etc, account ownership or init links are modified.
sed -e "s#config_dir=/etc/AdGuardHome#config_dir=\"$config\"#" \
    -e "s#runtime_dir=/var/lib/adguardhome#runtime_dir=\"$runtime\"#" \
    "$hook" > "$fixture/hook.sh"
grep -Fq "config_dir=\"$config\"" "$fixture/hook.sh"
grep -Fq "runtime_dir=\"$runtime\"" "$fixture/hook.sh"
run_hook() {
    sh -c 'id() { return 1; }; . "$1"; start' sh "$fixture/hook.sh"
}

run_hook
test -d "$config/work/data/filters"
test ! -d "$runtime/data"
test "$(stat -c %a "$config/work/data/filters")" = 700
test "$(stat -c %a "$config/work/data")" = 700
printf 'PASS: fresh boot creates protected persistent work directories\n'

mkdir -p "$runtime/data/filters"
printf 'old rules\n' > "$runtime/data/filters/1.txt"
printf 'old second list\n' > "$runtime/data/filters/2.txt"
printf 'new disk copy\n' > "$config/work/data/filters/2.txt"
printf 'query history\n' > "$runtime/data/querylog.json"
printf 'statistics\n' > "$runtime/data/stats.db"
run_hook
cmp "$runtime/data/filters/1.txt" "$config/work/data/filters/1.txt"
test "$(<"$config/work/data/filters/2.txt")" = 'new disk copy'
test -f "$runtime/data/filters/1.txt"
test ! -e "$config/data/querylog.json"
test ! -e "$config/data/stats.db"
test -z "$(find "$config/work/data/filters" -name '.migrate.*' -print -quit)"
printf 'PASS: missing lists seeded atomically without overwriting disk rules or moving logs\n'

mkdir -p "$config/data/filters"
printf 'old disk rule\n' > "$config/data/filters/4.txt"
printf 'older tmpfs rule\n' > "$runtime/data/filters/4.txt"
run_hook
cmp "$config/data/filters/4.txt" "$config/work/data/filters/4.txt"
printf 'PASS: old disk layout migrates first, preserving its source\n'

before=$(sha256sum "$config/work/data/filters/1.txt" "$config/work/data/filters/2.txt")
run_hook
test "$before" = "$(sha256sum "$config/work/data/filters/1.txt" "$config/work/data/filters/2.txt")"
printf 'PASS: repeated startup preserves persistent rule contents\n'

printf 'third list\n' > "$runtime/data/filters/3.txt"
if (
    id() { return 1; }
    cp() { printf 'partial copy\n' > "$2"; return 1; }
    . "$fixture/hook.sh"
    start
) > "$fixture/copy-failure.log" 2>&1; then
    printf 'FAIL: failed filter copy unexpectedly accepted\n' >&2
    exit 1
fi
test ! -e "$config/work/data/filters/3.txt"
test -f "$runtime/data/filters/3.txt"
test -z "$(find "$config/work/data/filters" -name '.migrate.*' -print -quit)"
test "$before" = "$(sha256sum "$config/work/data/filters/1.txt" "$config/work/data/filters/2.txt")"
run_hook
cmp "$runtime/data/filters/3.txt" "$config/work/data/filters/3.txt"
printf 'PASS: copy failure leaves no partial disk list and preserves retry/source data\n'

mv "$runtime" "$fixture/previous-runtime"
run_hook
test ! -d "$runtime/data"
test ! -e "$runtime/data/querylog.json"
test "$before" = "$(sha256sum "$config/work/data/filters/1.txt" "$config/work/data/filters/2.txt")"
printf 'PASS: simulated tmpfs loss retains persistent rules\n'

mv "$config/work/data/filters" "$config/work/data/saved-filters"
ln -s "$runtime/data" "$config/work/data/filters"
if run_hook > "$fixture/rejected.log" 2>&1; then
    printf 'FAIL: persistent filter symlink unexpectedly accepted\n' >&2
    exit 1
fi
test -L "$config/work/data/filters"
test -f "$config/work/data/saved-filters/1.txt"
printf 'PASS: tmpfs filter symlink rejected without deleting user data\n'
printf 'AdGuard Home storage regression tests passed.\n'
