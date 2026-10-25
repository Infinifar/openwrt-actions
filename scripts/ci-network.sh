#!/usr/bin/env bash
# Source in the CI job shell. No global Git/Runner/router proxy settings.
configure_ci_network() {
    if [ -z "${OPENWRT_HTTP_PROXY:-}" ]; then
        printf 'Info: CI download proxy not configured; using existing network settings.\n'
        return 0
    fi
    case "$OPENWRT_HTTP_PROXY" in
        http://*|https://*) ;;
        *) printf 'ERROR: OPENWRT_HTTP_PROXY must be an HTTP(S) proxy URL.\n' >&2; return 1 ;;
    esac
    NO_PROXY="$(python3 - <<'PY'
import os
from urllib.parse import urlsplit
items=['localhost','127.0.0.1','::1','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16']
for key in ['NO_PROXY','no_proxy','OPENWRT_NO_PROXY']:
    items.extend(os.environ.get(key,'').split(','))
items.append(os.environ.get('CI_SERVER_HOST',''))
for key in ['CI_SERVER_URL','CI_PROJECT_URL']:
    items.append(urlsplit(os.environ.get(key,'')).hostname or '')
print(','.join(dict.fromkeys(item.strip() for item in items if item.strip())))
PY
)" || return 1
    export NO_PROXY
    no_proxy="$NO_PROXY"
    HTTP_PROXY="$OPENWRT_HTTP_PROXY"
    HTTPS_PROXY="$OPENWRT_HTTP_PROXY"
    http_proxy="$OPENWRT_HTTP_PROXY"
    https_proxy="$OPENWRT_HTTP_PROXY"
    export no_proxy HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
    # Do not print the proxy URL: a future endpoint may contain authentication.
    curl -fsSL --retry 2 --retry-all-errors --retry-delay 1 --retry-max-time 60 --connect-timeout 10 --max-time 30 -o /dev/null https://github.com/ || {
        printf 'ERROR: CI proxy failed the HTTPS GitHub health check.\n' >&2; return 1;
    }
    if [ -n "${CI_SERVER_URL:-}" ]; then
        curl -fsS --connect-timeout 5 --max-time 20 -o /dev/null "${CI_SERVER_URL%/}/" || {
            printf 'ERROR: Internal GitLab bypass health check failed.\n' >&2; return 1;
        }
    fi
    printf 'Info: CI download proxy healthy; internal GitLab/localhost bypass enabled.\n'
}

configure_ci_network
