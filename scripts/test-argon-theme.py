#!/usr/bin/env python3
"""Offline negative/positive fixtures; never run the router's full defaults script."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('argon_gate', Path(__file__).with_name('validate-argon.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ArgonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='argon-regression-')
        self.addCleanup(self.temporary.cleanup)
        self.tree = Path(self.temporary.name) / 'build'
        self.root = self.tree / 'build_dir/target-x86_64_musl/root-x86'
        self.manifest = self.tree / 'bin/targets/x86/64/openwrt-x86-64-generic.manifest'
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text(''.join(f'{name} - fixture\n' for name in gate.PACKAGES))
        self.config = self.tree / '.config'
        self.config.write_text(''.join(f'CONFIG_PACKAGE_{name}=y\n' for name in gate.PACKAGES))
        for name in gate.ASSETS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'wOF2fixture' if path.suffix == '.woff2' else b'fixture\n')
            if path.suffix == '.json':
                path.write_text('{"fixture":true}\n')
            if name.startswith('usr/libexec/rpcd/'):
                path.chmod(0o755)
        (self.root / 'etc/config/argon').write_text("config global\n\toption online_wallpaper 'none'\n")
        self.defaults = self.root / gate.DEFAULTS
        self.defaults.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(gate.REPO / 'app_config' / gate.DEFAULTS, self.defaults)
        self.wallpaper = self.root / gate.WALLPAPER
        self.wallpaper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(gate.REPO / 'user/common/files' / gate.WALLPAPER, self.wallpaper)

    def test_actual_source_and_original_wallpaper(self):
        gate.source(gate.REPO)

    def test_valid_config_manifest_assets_and_report(self):
        report = gate.build(self.tree)
        self.assertEqual(report['wallpaper_sha256'], gate.WALLPAPER_SHA256)
        self.assertEqual(len(report['files']), len(gate.ASSETS) + 1)
        self.assertEqual(gate.wallpaper(self.wallpaper), gate.WALLPAPER_SHA256)
        # Package repository indexes are not firmware manifests.
        index = self.manifest.parent / 'packages/Packages.manifest'
        index.parent.mkdir()
        index.write_text('Package: unrelated\n')
        self.assertEqual(gate.build(self.tree), report)

    def test_all_final_dependencies_must_be_builtin(self):
        original = self.config.read_text()
        for name in gate.PACKAGES:
            for value in ('m', 'n'):
                with self.subTest(package=name, value=value):
                    self.config.write_text(original.replace(f'CONFIG_PACKAGE_{name}=y', f'CONFIG_PACKAGE_{name}={value}'))
                    with self.assertRaises(gate.ValidationError):
                        gate.build(self.tree)
        self.config.write_text(original)

    def test_all_required_packages_must_be_in_image(self):
        original = self.manifest.read_text()
        for name in gate.PACKAGES:
            with self.subTest(package=name):
                self.manifest.write_text(original.replace(f'{name} - fixture\n', ''))
                with self.assertRaises(gate.ValidationError):
                    gate.build(self.tree)
        self.manifest.write_text(original)

    def test_package_index_cannot_replace_image_manifest(self):
        self.manifest.unlink()
        index = self.manifest.parent / 'packages/Packages.manifest'
        index.parent.mkdir()
        index.write_text(''.join(f'{name} - fixture\n' for name in gate.PACKAGES))
        with self.assertRaises(gate.ValidationError):
            gate.build(self.tree)

    def test_missing_or_ambiguous_installed_root(self):
        other = self.tree / 'build_dir/another/root-x86'
        other.mkdir(parents=True)
        with self.assertRaises(gate.ValidationError):
            gate.build(self.tree)
        other.rmdir()
        renamed = self.root.with_name('staging-not-installed')
        self.root.rename(renamed)
        with self.assertRaises(gate.ValidationError):
            gate.build(self.tree)

    def test_every_critical_resource_must_be_present_and_nonempty(self):
        for name in gate.ASSETS:
            with self.subTest(asset=name):
                path = self.root / name
                content, mode = path.read_bytes(), path.stat().st_mode & 0o777
                path.unlink()
                with self.assertRaises(gate.ValidationError):
                    gate.rootfs(self.root)
                path.write_bytes(b'')
                with self.assertRaises(gate.ValidationError):
                    gate.rootfs(self.root)
                path.write_bytes(content)
                path.chmod(mode)

    def test_wallpaper_directory_alone_is_not_a_theme(self):
        for name in gate.ASSETS:
            (self.root / name).unlink()
        self.assertTrue(self.wallpaper.is_file())
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)

    def test_wallpaper_missing_empty_or_modified_is_rejected(self):
        original = self.wallpaper.read_bytes()
        self.wallpaper.unlink()
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)
        for data in (b'', original + b'changed'):
            self.wallpaper.write_bytes(data)
            with self.assertRaises(gate.ValidationError):
                gate.rootfs(self.root)

    def test_bad_font_html_asset_and_nonexecutable_rpc_are_rejected(self):
        font = self.root / 'www/luci-static/argon/fonts/GoogleSans-Regular.woff2'
        font.write_text('not a font')
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)
        font.write_bytes(b'wOF2fixture')
        css = self.root / 'www/luci-static/argon/css/cascade.css'
        css.write_text('<!DOCTYPE html><html>upstream error</html>')
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)
        css.write_text('.fixture{}')
        rpc = self.root / 'usr/libexec/rpcd/luci.argon'
        rpc.chmod(0o644)
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)

    def test_online_wallpaper_and_unguarded_theme_defaults_are_rejected(self):
        argon = self.root / 'etc/config/argon'
        argon.write_text("config global\n\toption online_wallpaper 'bing'\n")
        with self.assertRaises(gate.ValidationError):
            gate.rootfs(self.root)
        argon.write_text("config global\n\toption online_wallpaper 'none'\n")
        original = self.defaults.read_text()
        for field in ('luci.main.mediaurlbase', 'luci.themes.Argon', 'online_wallpaper=none', 'css/cascade.css'):
            self.defaults.write_text(original.replace(field, 'removed-fixture'))
            with self.assertRaises(gate.ValidationError):
                gate.rootfs(self.root)

    def test_isolated_boot_policy_never_accepts_a_background_only_directory(self):
        block = gate.defaults(self.defaults)
        # Execute ONLY this small extracted block with a fake UCI/logger.
        # Rewrite absolute read checks into our disposable fixture root.
        block = block.replace('/www/', str(self.root / 'www') + '/').replace(
            '/usr/share/ucode/', str(self.root / 'usr/share/ucode') + '/')
        fake_commands = 'uci() { printf "UCI:%s\\n" "$*"; }; logger() { printf "LOG:%s\\n" "$*"; };\n'
        result = subprocess.run(['sh', '-c', fake_commands + block], capture_output=True, text=True, check=True)
        self.assertIn('luci.main.mediaurlbase=', result.stdout)
        self.assertIn('luci.themes.Argon=', result.stdout)
        self.assertIn('online_wallpaper=none', result.stdout)
        css = self.root / 'www/luci-static/argon/css/cascade.css'
        css.unlink()
        result = subprocess.run(['sh', '-c', fake_commands + block], capture_output=True, text=True, check=True)
        self.assertNotIn('UCI:', result.stdout)
        self.assertIn('Argon resources missing', result.stdout)
        css.write_text('.fixture{}')
        (self.root / 'usr/share/ucode/luci/template/themes/argon/header.ut').unlink()
        result = subprocess.run(['sh', '-c', fake_commands + block], capture_output=True, text=True, check=True)
        self.assertNotIn('UCI:', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
