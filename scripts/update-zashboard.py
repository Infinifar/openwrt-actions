#!/usr/bin/env python3
"""Install the latest stable official dashboard, or verify its staged files."""
import argparse
import hashlib
from html.parser import HTMLParser
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
from urllib.parse import unquote, urlsplit
import zipfile

API = "https://api.github.com/repos/Zephyruso/zashboard/releases/latest"
REPOSITORY = "https://github.com/Zephyruso/zashboard"
INFO = "zashboard-build.json"


def download(url):
    return subprocess.check_output([
        "curl", "--fail", "--silent", "--show-error", "--location",
        "--retry", "3", "--connect-timeout", "10", "--max-time", "180", url,
    ])


def release_asset(release):
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Expected a stable semantic release tag")
    assets = [a for a in release.get("assets", []) if a.get("name") == "dist.zip"]
    if len(assets) != 1:
        raise ValueError("Expected exactly one dist.zip release asset")
    asset = assets[0]
    url = f"{REPOSITORY}/releases/download/{tag}/dist.zip"
    if asset.get("browser_download_url") != url:
        raise ValueError("Unexpected dashboard asset URL")
    digest = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Missing official SHA256 asset digest")
    return tag, url, digest.split(":", 1)[1]


class ReleasePage(HTMLParser):
    """Read GitHub's official release metadata without the API rate quota."""
    def __init__(self):
        super().__init__()
        self.tag = None
        self.digests = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "meta" and attrs.get("property") == "og:url":
            path = urlsplit(attrs.get("content", "")).path
            match = re.fullmatch(r"/Zephyruso/zashboard/releases/tag/(v\d+\.\d+\.\d+)", path)
            if match:
                self.tag = match.group(1)
        if tag == "clipboard-copy" and attrs.get("aria-label") == "Copy to clipboard digest for dist.zip":
            self.digests.append(attrs.get("value", ""))


def latest_asset():
    try:
        release = json.loads(download(API))
    except subprocess.CalledProcessError:
        # Both paths resolve today's latest release; this is not a stale-cache
        # fallback and still requires the digest published by the official site.
        print("GitHub release API unavailable; checking the official latest release page")
        page = ReleasePage()
        page.feed(download(REPOSITORY + "/releases/latest").decode("utf-8"))
        if not page.tag:
            raise ValueError("Could not resolve the official latest stable release")
        assets = ReleasePage()
        assets.feed(download(REPOSITORY + "/releases/expanded_assets/" + page.tag).decode("utf-8"))
        if len(assets.digests) != 1:
            raise ValueError("Missing or ambiguous official dist.zip SHA256")
        release = {"tag_name": page.tag, "assets": [{
            "name": "dist.zip", "digest": assets.digests[0],
            "browser_download_url": f"{REPOSITORY}/releases/download/{page.tag}/dist.zip",
        }]}
    return release_asset(release)

class AssetLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if value and key in ("src", "href"):
                self.links.append(value)


def validate_assets(root):
    index = root / "index.html"
    if not index.is_file() or not index.stat().st_size:
        raise ValueError("Missing dashboard index.html")
    parser = AssetLinks()
    parser.feed(index.read_text(encoding="utf-8"))
    scripts = 0
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            continue
        relative = unquote(url.path).lstrip("/")
        if Path(relative).suffix not in (".js", ".css"):
            continue
        asset = (root / relative).resolve()
        if not asset.is_relative_to(root.resolve()) or not asset.is_file() or not asset.stat().st_size:
            raise ValueError(f"Missing or unsafe dashboard asset: {relative}")
        scripts += asset.suffix == ".js"
    if not scripts:
        raise ValueError("Dashboard has no local JavaScript entry point")


def file_hashes(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError("Dashboard symlinks are not allowed")
        if path.is_file() and path.relative_to(root).as_posix() != INFO:
            result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def apply_ai_folder_policy(root):
    # Keep Mihomo's single manual AI selector; folder layout is a UI concern.
    name = "firmware-ai-folders.js"
    policy = Path(__file__).with_name("zashboard-ai-folders.js").read_bytes()
    (root / name).write_bytes(policy)
    index = root / "index.html"
    html = index.read_text(encoding="utf-8")
    if "</head>" not in html:
        raise ValueError("Dashboard entry has no head for the local folder policy")
    tag = f'<script src="./{name}"></script>'
    if html.count(tag) > 1:
        raise ValueError("Duplicate local AI folder policy scripts")
    if tag not in html:
        html = html.replace("</head>", tag + "</head>", 1)
    index.write_text(html, encoding="utf-8")
    worker = root / "sw.js"
    if worker.is_file():
        script = worker.read_text(encoding="utf-8")
        index_hash = hashlib.sha256(index.read_bytes()).hexdigest()
        script, count = re.subn(r'(url:\s*"index\.html",\s*revision:)"[^"]+"',
                                lambda m: m.group(1) + '"' + index_hash + '"', script)
        if count != 1 or script.count("precacheAndRoute([") != 1:
            raise ValueError("Unrecognized service-worker precache format")
        entry = '{url:"' + name + '",revision:"' + hashlib.sha256(policy).hexdigest() + '"}'
        owned = r'\{url:\s*"firmware-ai-folders\.js",\s*revision:\s*"[^"]+"\}'
        matches = len(re.findall(owned, script))
        if matches > 1:
            raise ValueError("Duplicate AI folder policy precache entries")
        if matches:
            script = re.sub(owned, lambda _: entry, script, count=1)
        else:
            script = script.replace("precacheAndRoute([", "precacheAndRoute([" + entry + ",", 1)
        worker.write_text(script, encoding="utf-8")

def verify(root):
    validate_assets(root)
    info = json.loads((root / INFO).read_text(encoding="utf-8"))
    policy = Path(__file__).with_name("zashboard-ai-folders.js").read_bytes()
    if info.get("customizations") != ["single-AI strategy folder preference"]:
        raise ValueError("Missing local AI folder preference record")
    if (root / "firmware-ai-folders.js").read_bytes() != policy:
        raise ValueError("Installed AI folder policy differs from this build")
    tag, url, digest = release_asset({
        "tag_name": info["version"], "assets": [{
            "name": "dist.zip", "browser_download_url": info["asset_url"],
            "digest": "sha256:" + info["archive_sha256"],
        }],
    })
    if not info.get("files") or file_hashes(root) != info["files"]:
        raise ValueError("Dashboard file hashes do not match the release build record")
    print(f"Zashboard {tag}: entry assets and all packaged file hashes verified")
    return info


def install(package):
    package = package.resolve(strict=True)
    if not (package / "Makefile").is_file():
        raise ValueError("Expected an OpenClash package directory")
    parent = package / "root/usr/share/openclash/ui"
    target = parent / "zashboard"
    if not target.resolve().is_relative_to(package) or target.is_symlink():
        raise ValueError("Dashboard target escapes the generated package")
    tag, url, digest = latest_asset()
    archive = download(url)
    if hashlib.sha256(archive).hexdigest() != digest:
        raise ValueError("Dashboard archive SHA256 mismatch")
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".zashboard-", dir=parent) as temporary:
        work = Path(temporary)
        unpack = work / "unpack"
        with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
            seen = set()
            if sum(member.file_size for member in bundle.infolist()) > 200 * 1024 * 1024:
                raise ValueError("Dashboard archive is unexpectedly large")
            for member in bundle.infolist():
                path = PurePosixPath(member.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in member.filename or member.filename in seen:
                    raise ValueError("Unsafe or duplicate archive path")
                if stat.S_ISLNK(member.external_attr >> 16):
                    raise ValueError("Dashboard archive contains a symlink")
                seen.add(member.filename)
            bundle.extractall(unpack)
        roots = [root for root in (unpack, unpack / "dist") if (root / "index.html").is_file()]
        if len(roots) != 1:
            raise ValueError("Unrecognized dashboard release layout")
        staged = roots[0]
        validate_assets(staged)
        apply_ai_folder_policy(staged)
        info = {"version": tag, "asset_url": url, "archive_sha256": digest,
                "customizations": ["single-AI strategy folder preference"], "files": file_hashes(staged)}
        (staged / INFO).write_text(json.dumps(info, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        staged.chmod(0o755)
        for path in staged.rglob("*"):
            path.chmod(0o755 if path.is_dir() else 0o644)
        verify(staged)
        backup = work / "previous"
        existed = target.exists()
        if existed:
            target.rename(backup)
        try:
            staged.rename(target)
        except OSError:
            if existed:
                backup.rename(target)
            raise
    print(f"Installed official Zashboard {tag} (dist.zip, local fonts, SHA256 {digest})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("install", "verify", "verify-build"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    if args.command == "install":
        install(args.path)
    elif args.command == "verify":
        verify(args.path)
    else:
        roots = list(args.path.glob("build_dir/*/root-x86/usr/share/openclash/ui/zashboard"))
        if len(roots) != 1:
            raise ValueError("Expected exactly one installed x86 Zashboard rootfs")
        verify(roots[0])


if __name__ == "__main__":
    main()
