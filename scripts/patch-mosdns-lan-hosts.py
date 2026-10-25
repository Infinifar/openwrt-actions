#!/usr/bin/env python3
"""Install an exact, fail-fast pre-start hook into the fresh MosDNS init script."""
from pathlib import Path
import sys

MARKER = '# lede-personal: prepare exact LAN hosts v1'
HOOK = '''
\t# lede-personal: prepare exact LAN hosts v1
\tif [ "$CONF" = "/etc/mosdns/config_custom.yaml" ]; then
\t\t/usr/share/mosdns/sync-adguard-hosts.rb sync || return 1
\t\t/usr/share/mosdns/sync-adguard-hosts.rb configure "$CONF" || return 1
\tfi
'''
ANCHOR = '\n\tprocd_open_instance mosdns\n'

def patched(text):
    if MARKER in text:
        if text.count(HOOK) == 1:
            return text
        raise ValueError('Unexpected modified MosDNS LAN hook')
    if text.count(ANCHOR) != 1 or 'start_service() {' not in text:
        raise ValueError('MosDNS init layout changed; review required')
    return text.replace(ANCHOR, HOOK + ANCHOR, 1)

if __name__ == '__main__':
    path = Path(sys.argv[1])
    path.write_text(patched(path.read_text()))
    print('MosDNS pre-start LAN hosts hook verified')
