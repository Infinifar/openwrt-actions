#!/bin/sh
# A bounded, serialized reload, detached from the LuCI/rpcd request connection.
set -u
runtime=/var/run/tailscale-luci-apply
umask 077
state() { printf '%s\n' "$1" > "$runtime/status.new"; mv "$runtime/status.new" "$runtime/status"; }
step() {
    local name="$1"
    shift
    if timeout 45 "$@" >/dev/null 2>&1; then return 0; fi
    state "${name}_failed"
    logger -t tailscale-luci "${name} failed; inspect the service log before retrying"
    return 1
}
case "${1:-}" in
queue)
    case "${2:-}:${3:-}" in 0:0|0:1|1:0|1:1) ;; *) exit 64 ;; esac
    mkdir -p "$runtime" || exit 1
    exec 9>"$runtime/lock"
    flock -n 9 || exit 75
    state queued
    # Redirect every standard FD; otherwise popen.close() can await this child.
    ( sleep 2; "$0" run "$2" "$3" ) </dev/null >/dev/null 2>&1 &
    ;;
run)
    case "${2:-}:${3:-}" in 0:0|0:1|1:0|1:1) ;; *) exit 64 ;; esac
    state running
    if [ "$2" = 1 ]; then step network /etc/init.d/network reload || exit 1; fi
    if [ "$3" = 1 ]; then step firewall /etc/init.d/firewall reload || exit 1; fi
    # Reconcile committed advertisements even when the UCI zones already exist.
    step settings /etc/init.d/tailscale-settings reload || exit 1
    state success
    logger -t tailscale-luci 'Requested reload and settings apply completed'
    ;;
*) exit 64 ;;
esac
