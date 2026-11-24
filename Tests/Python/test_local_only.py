"""Test the release check with isolated source and manifest fixtures."""

from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from check_local_only import violations


class LocalOnlyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        for folder in ["App", "Keyboard", "Core", "Neural"]:
            (self.root / folder).mkdir()
        self.write("Keyboard/Info.plist", {"NSExtension": {"NSExtensionAttributes": {"RequestsOpenAccess": False}}})
        self.write("App/PrivacyInfo.xcprivacy", {"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": []})

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, value):
        (self.root / name).write_bytes(plistlib.dumps(value))

    def test_local_bundle_reads_pass(self):
        (self.root / "Core/Words.swift").write_text('let data = try Data(contentsOf: bundleURL)\n')
        self.assertEqual(violations(self.root), [])

    def test_network_and_analytics_apis_fail(self):
        for source in ['let session = URLSession.shared', 'import Network', 'import Sentry']:
            with self.subTest(source=source):
                (self.root / "Keyboard/Remote.swift").write_text(source)
                self.assertTrue(violations(self.root))

    def test_nested_network_source_fails(self):
        folder = self.root / "App/Services"
        folder.mkdir()
        (folder / "Remote.swift").write_text("let session = URLSession.shared")
        self.assertTrue(violations(self.root))

    def test_full_access_or_tracking_changes_fail(self):
        self.write("Keyboard/Info.plist", {"NSExtension": {"NSExtensionAttributes": {"RequestsOpenAccess": True}}})
        self.assertTrue(violations(self.root))
        self.write("Keyboard/Info.plist", {"NSExtension": {"NSExtensionAttributes": {"RequestsOpenAccess": False}}})
        self.write("App/PrivacyInfo.xcprivacy", {"NSPrivacyTracking": True, "NSPrivacyCollectedDataTypes": []})
        self.assertTrue(violations(self.root))
        self.write("App/PrivacyInfo.xcprivacy", {"NSPrivacyTracking": False, "NSPrivacyCollectedDataTypes": [{"data": "typing"}]})
        self.assertTrue(violations(self.root))


if __name__ == "__main__":
    unittest.main()
