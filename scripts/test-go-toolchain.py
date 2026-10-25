#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('upgrade', ROOT / 'scripts/update-go-toolchain.py')
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)
PIN = json.loads((ROOT / 'ci/go-toolchain.json').read_text())
RECIPE = 'GO_VERSION_MAJOR_MINOR:=1.27\nGO_VERSION_PATCH:=1\nPKG_HASH:=' + 'a' * 64 + '\nOTHER:=unchanged\n'


class GoTests(unittest.TestCase):
    def test_patch_upgrade_and_preservation(self):
        text, selected = upgrade.upgraded_recipe(RECIPE, PIN, '1.27.3')
        self.assertEqual(selected, '1.27.3')
        self.assertIn('GO_VERSION_PATCH:=3\n', text)
        self.assertIn('PKG_HASH:=' + PIN['sha256'], text)
        self.assertIn('OTHER:=unchanged\n', text)
        self.assertEqual(upgrade.upgraded_recipe(text, PIN, '1.27.3'), (text, selected))

    def test_never_downgrade(self):
        text = RECIPE.replace('PATCH:=1', 'PATCH:=4')
        self.assertEqual(upgrade.upgraded_recipe(text, PIN, '1.27.3'), (text, '1.27.4'))

    def test_future_requirement_fails_before_write(self):
        with self.assertRaisesRegex(ValueError, 'Tailscale requires'):
            upgrade.upgraded_recipe(RECIPE, PIN, '1.28.0')

    def test_family_migration_refused(self):
        with self.assertRaisesRegex(ValueError, 'family migration'):
            upgrade.upgraded_recipe(RECIPE.replace('1.27\n', '1.26\n'), PIN, '1.27.3')

    def test_invalid_hash_and_url(self):
        for broken in [dict(PIN, sha256='skip'), dict(PIN, source='http://example.invalid/go.tar.gz')]:
            with self.assertRaises(ValueError):
                upgrade.upgraded_recipe(RECIPE, broken, '1.27.3')

    def test_missing_or_duplicate_assignment(self):
        for text in [RECIPE.replace('GO_VERSION_PATCH:=1\n', ''), RECIPE + 'PKG_HASH:=' + 'b' * 64 + '\n']:
            with self.assertRaises(ValueError):
                upgrade.upgraded_recipe(text, PIN, '1.27.3')

    def test_module_version_parsing(self):
        self.assertEqual(upgrade.required_go('module tailscale.com\n\ngo 1.27.3\n'), '1.27.3')
        self.assertEqual(upgrade.required_go('go 1.27\n'), '1.27.0')
        for bad in ['go 1.27rc1\n', '', 'go 1.27.1\ngo 1.27.3\n']:
            with self.assertRaises(ValueError):
                upgrade.required_go(bad)


if __name__ == '__main__':
    unittest.main()
