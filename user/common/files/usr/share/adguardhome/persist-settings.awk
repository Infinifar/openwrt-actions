# Change only owned scalars; preserve users, subscriptions, DNS and comments.
/^[^[:space:]#][^:]*:/ {
    section = $0
    sub(/:.*/, "", section)
}
/^http_proxy:/ {
    seen["proxy"]++
    print "http_proxy: http://127.0.0.1:7890"
    next
}
section == "querylog" && /^  dir_path:/ {
    seen["querydir"]++
    print "  dir_path: /etc/AdGuardHome/work/data"
    next
}
section == "querylog" && /^  file_enabled:/ {
    seen["queryfile"]++
    print "  file_enabled: false"
    next
}
section == "statistics" && /^  dir_path:/ {
    seen["statsdir"]++
    print "  dir_path: /etc/AdGuardHome/work/data"
    next
}
section == "statistics" && /^  interval:/ {
    seen["statsinterval"]++
    print "  interval: 168h"
    next
}
section == "filtering" && /^  filters_update_interval:/ {
    seen["updates"]++
    print "  filters_update_interval: 24"
    next
}
{ print }
END {
    split("proxy querydir queryfile statsdir statsinterval updates", required, " ")
    for (i in required)
        if (seen[required[i]] != 1)
            exit 1
}
