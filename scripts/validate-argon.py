#!/usr/bin/env python3
"""Read-only Argon source/config/rootfs gates; no router commands are executed."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
WALLPAPER = Path('www/luci-static/argon/background/background.png')
WALLPAPER_SHA256 = '3a0919015f0899d3367e60ae2706d0bff35bc614cede5d0b2a18c7d308e87703'
PACKAGES = ('luci-theme-argon-jerrykuku', 'coreutils', 'coreutils-timeout',
            'ucode-mod-math', 'flock', 'jsonfilter')
EXPLICIT_PACKAGES = PACKAGES[:3]
TARGETS = ('lede-openclash-x86-amd64', 'lede-common-n1-arm64')
DEFAULTS = Path('etc/uci-defaults/zzzz-extra-settings')
ASSETS = (
    'www/luci-static/argon/css/cascade.css',
    'www/luci-static/argon/fonts/GoogleSans-Regular.woff2',
    'www/luci-static/argon/fonts/TypoGraphica.woff2',
    'www/luci-static/resources/menu-argon.js',
    'www/luci-static/resources/argon-appearance.js',
    'www/luci-static/resources/argon-graphs.js',
    'www/luci-static/resources/argon-overview.js',
    'www/luci-static/resources/argon-sshkeys.js',
    'www/luci-static/resources/argon/branding.js',
    'www/luci-static/resources/argon/updates.js',
    'www/luci-static/resources/view/argon-config.js',
    *('usr/share/ucode/luci/template/themes/argon/' + name + '.ut' for name in (
        'head', 'head_meta', 'header', 'footer', 'sysauth', 'header_login',
        'footer_login', 'out_header_login', 'login_form', 'login_background', 'page_scripts')),
    'etc/config/argon',
    'etc/uci-defaults/30_luci-theme-argon',
    'usr/share/ucode/luci/argon-branding.uc',
    'usr/share/ucode/luci/argon-palette.uc',
    'usr/share/luci/menu.d/luci-app-argon-config.json',
    'usr/share/rpcd/acl.d/luci-app-argon-config.json',
    'usr/share/rpcd/acl.d/luci-theme-argon.json',
    'usr/share/argon/config-integrated',
    *('usr/libexec/rpcd/luci.' + name for name in (
        'argon', 'argon_appearance', 'argon_update', 'argon_wallpaper', 'argon_branding')),
)


class ValidationError(ValueError):
    pass


def payload(path):
    if not path.is_file() or path.stat().st_size == 0:
        raise ValidationError(f'missing or empty Argon file: {path}')
    return path.read_bytes()


def wallpaper(path):
    data = payload(path)
    digest = hashlib.sha256(data).hexdigest()
    if not data.startswith(b'\x89PNG\r\n\x1a\n') or digest != WALLPAPER_SHA256:
        raise ValidationError(f'public placeholder wallpaper checksum/signature mismatch: {path}')
    return digest


def config(path, packages=PACKAGES):
    lines = set(payload(path).decode().splitlines())
    for package in packages:
        if f'CONFIG_PACKAGE_{package}=y' not in lines:
            raise ValidationError(f'Argon dependency must remain selected as =y: {package} ({path})')


def defaults(path):
    text = payload(path).decode()
    try:
        block = text.split('# BEGIN personal Argon defaults\n', 1)[1].split('# END personal Argon defaults', 1)[0]
    except IndexError as error:
        raise ValidationError(f'missing guarded Argon boot policy: {path}') from error
    required = (
        'theme=argon',
        '[ -s "/www/luci-static/$theme/css/cascade.css" ]',
        '[ -s "/usr/share/ucode/luci/template/themes/$theme/header.ut" ]',
        '[ -s "/usr/share/ucode/luci/template/themes/$theme/footer.ut" ]',
        '[ -s "/usr/share/ucode/luci/template/themes/$theme/sysauth.ut" ]',
        'uci set luci.themes.Argon=/luci-static/$theme',
        'uci set luci.main.mediaurlbase=/luci-static/$theme',
        "uci set 'argon.@global[0].online_wallpaper=none'",
    )
    if not all(value in block for value in required):
        raise ValidationError(f'incomplete Argon asset/default/wallpaper boot guard: {path}')
    return block


def source(repo):
    for target in TARGETS:
        config(repo / 'user' / target / 'config.diff', EXPLICIT_PACKAGES)
    defaults(repo / 'app_config' / DEFAULTS)
    wallpaper(repo / 'user/common/files' / WALLPAPER)


def rootfs(root):
    hashes = {}
    for name in ASSETS:
        path = root / name
        data = payload(path)
        if path.suffix == '.woff2':
            if not data.startswith(b'wOF2'):
                raise ValidationError(f'Argon font is not WOFF2: {path}')
        elif path.suffix in ('.js', '.css', '.ut'):
            if path.suffix in ('.js', '.css') and data.lstrip().lower().startswith((b'<!doctype html', b'<html')):
                raise ValidationError(f'HTML error response instead of an Argon asset: {path}')
            data.decode('utf-8')
        elif path.suffix == '.json':
            json.loads(data)
        elif path.suffix == '.uc':
            data.decode('utf-8')
        if name.startswith('usr/libexec/rpcd/') and not path.stat().st_mode & 0o111:
            raise ValidationError(f'Argon RPC helper is not executable: {path}')
        hashes[name] = hashlib.sha256(data).hexdigest()
    defaults(root / DEFAULTS)
    if not re.search(r"(?m)^\s*option\s+online_wallpaper\s+['\"]?none['\"]?\s*$",
                     (root / 'etc/config/argon').read_text()):
        raise ValidationError('Argon must default to the preserved local wallpaper, not an online provider')
    hashes[str(WALLPAPER)] = wallpaper(root / WALLPAPER)
    return hashes


def build(tree):
    config(tree / '.config')
    manifests = sorted((tree / 'bin/targets').glob('*/*/*.manifest'))
    manifests = [path for path in manifests if path.name != 'Packages.manifest']
    if not manifests:
        raise ValidationError('no image-level firmware manifest for Argon verification')
    versions = {}
    for manifest in manifests:
        packages = dict(line.split(' - ', 1) for line in payload(manifest).decode().splitlines() if ' - ' in line)
        for package in PACKAGES:
            if package not in packages:
                raise ValidationError(f'missing Argon package from image manifest: {package} ({manifest})')
        versions[str(manifest.relative_to(tree))] = {package: packages[package] for package in PACKAGES}
    roots = [path for path in (tree / 'build_dir').glob('*/root-x86') if path.is_dir()]
    if len(roots) != 1:
        raise ValidationError('expected exactly one installed x86 rootfs for Argon verification')
    return {'schema': 1, 'packages': versions, 'files': rootfs(roots[0]),
            'wallpaper_sha256': WALLPAPER_SHA256}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('source', 'config', 'build'))
    parser.add_argument('path', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        result = {'mode': args.mode}
        if args.mode == 'source':
            source(args.path)
        elif args.mode == 'config':
            config(args.path)
        else:
            result = build(args.path)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
        print(f'Argon {args.mode} verified: required packages, real theme assets and/or original wallpaper')
    except (OSError, ValueError, UnicodeError) as error:
        print(f'Argon validation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
