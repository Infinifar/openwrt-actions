#!/usr/bin/env python3
"""Offline regression tests; never download or alter a real package."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("zashboard", Path(__file__).with_name("update-zashboard.py"))
zashboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zashboard)


class DashboardTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="zashboard-test-")
        self.addCleanup(self.temporary.cleanup)
        self.package = Path(self.temporary.name) / "openclash"
        self.package.mkdir()
        (self.package / "Makefile").write_text("PKG_NAME:=luci-app-openclash\n")
        self.target = self.package / "root/usr/share/openclash/ui/zashboard"
        self.target.mkdir(parents=True)
        (self.target / "old-marker").write_text("preserve on failure")

    def bundle(self, entries=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name, content in (entries or {
                "dist/index.html": '<!doctype html><html><head><script type="module" src="./assets/app.js"></script><link href="./assets/app.css" rel="stylesheet"></head></html>',
                "dist/assets/app.js": "console.log('fixture')",
                "dist/assets/app.css": "body{color:black}",
                "dist/sw.js": 'workbox.precacheAndRoute([{url:"index.html",revision:"upstream"}]);',
            }).items():
                archive.writestr(name, content)
        return stream.getvalue()

    def run_install(self, archive=None, digest=None, tag="v3.29.1", prerelease=False):
        archive = self.bundle() if archive is None else archive
        release = {"tag_name": tag, "prerelease": prerelease, "assets": [{
            "name": "dist.zip", "browser_download_url": f"{zashboard.REPOSITORY}/releases/download/{tag}/dist.zip",
            "digest": digest or "sha256:" + hashlib.sha256(archive).hexdigest(),
        }]}
        with patch.object(zashboard, "download", side_effect=[json.dumps(release).encode(), archive]):
            zashboard.install(self.package)

    def test_install_and_verify_latest_stable(self):
        self.run_install(tag="v3.99.0")
        self.assertFalse((self.target / "old-marker").exists())
        self.assertEqual(zashboard.verify(self.target)["version"], "v3.99.0")
        self.assertTrue((self.target / "firmware-ai-folders.js").is_file())
        self.assertIn('src="./firmware-ai-folders.js"', (self.target / "index.html").read_text())
        worker = (self.target / "sw.js").read_text()
        index_hash = hashlib.sha256((self.target / "index.html").read_bytes()).hexdigest()
        self.assertIn(index_hash, worker)
        self.assertIn('url:"firmware-ai-folders.js"', worker)

    def test_ai_folder_policy_reapply_is_idempotent(self):
        self.run_install()
        before = zashboard.file_hashes(self.target)
        zashboard.apply_ai_folder_policy(self.target)
        self.assertEqual(zashboard.file_hashes(self.target), before)
        html = (self.target / "index.html").read_text()
        worker = (self.target / "sw.js").read_text()
        self.assertEqual(html.count('src="./firmware-ai-folders.js"'), 1)
        self.assertEqual(worker.count('url:"firmware-ai-folders.js"'), 1)
        zashboard.verify(self.target)

    def test_ai_folder_policy_refreshes_owned_cache_revision(self):
        self.run_install()
        worker = self.target / "sw.js"
        text = worker.read_text()
        digest = hashlib.sha256((self.target / "firmware-ai-folders.js").read_bytes()).hexdigest()
        worker.write_text(text.replace(digest, "stale-policy-revision"))
        zashboard.apply_ai_folder_policy(self.target)
        self.assertEqual(worker.read_text(), text)

    def test_duplicate_ai_policy_script_fails_without_replacing_dashboard(self):
        bad = self.bundle({
            "dist/index.html": '<head><script src="./firmware-ai-folders.js"></script><script src="./firmware-ai-folders.js"></script></head>',
            "dist/firmware-ai-folders.js": "old local policy",
        })
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            self.run_install(archive=bad)
        self.assertTrue((self.target / "old-marker").exists())

    def test_bad_checksum_preserves_existing(self):
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            self.run_install(digest="sha256:" + "0" * 64)
        self.assertTrue((self.target / "old-marker").exists())

    def test_prerelease_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "stable"):
            self.run_install(prerelease=True)

    def test_missing_digest_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            self.run_install(digest="not-a-checksum")

    def test_missing_asset_preserves_existing(self):
        bad = self.bundle({"dist/index.html": '<script src="./assets/missing.js"></script>'})
        with self.assertRaisesRegex(ValueError, "Missing or unsafe"):
            self.run_install(archive=bad)
        self.assertTrue((self.target / "old-marker").exists())

    def test_archive_traversal_preserves_existing(self):
        bad = self.bundle({"../escape": "bad"})
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.run_install(archive=bad)
        self.assertTrue((self.target / "old-marker").exists())

    def test_tampering_is_rejected(self):
        self.run_install()
        (self.target / "assets/app.js").write_text("tampered")
        with self.assertRaisesRegex(ValueError, "hashes"):
            zashboard.verify(self.target)

    def test_network_failure_is_not_a_cache_fallback(self):
        with patch.object(zashboard, "download", side_effect=RuntimeError("network failed")):
            with self.assertRaisesRegex(RuntimeError, "network failed"):
                zashboard.install(self.package)
        self.assertTrue((self.target / "old-marker").exists())

    def test_rate_limit_uses_current_official_release_page(self):
        archive = self.bundle()
        digest = "sha256:" + hashlib.sha256(archive).hexdigest()
        page = b'<meta property="og:url" content="/Zephyruso/zashboard/releases/tag/v3.99.0">'
        assets = ('<clipboard-copy aria-label="Copy to clipboard digest for dist.zip" value="' + digest + '"></clipboard-copy>').encode()
        with patch.object(zashboard, "download", side_effect=[subprocess.CalledProcessError(22, "curl"), page, assets, archive]):
            zashboard.install(self.package)
        self.assertEqual(zashboard.verify(self.target)["version"], "v3.99.0")

    def test_rate_limit_without_official_digest_fails_closed(self):
        page = b'<meta property="og:url" content="/Zephyruso/zashboard/releases/tag/v3.29.1">'
        with patch.object(zashboard, "download", side_effect=[subprocess.CalledProcessError(22, "curl"), page, b"no digest"]):
            with self.assertRaisesRegex(ValueError, "SHA256"):
                zashboard.install(self.package)
        self.assertTrue((self.target / "old-marker").exists())


if __name__ == "__main__":
    unittest.main()
