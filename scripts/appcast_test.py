import base64
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import appcast

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
SCRIPT = Path(appcast.__file__).resolve()
NOTES = "<p>a & b ]]> c</p>"
RELEASE = {
    "tag_name": "v0.4.0",
    "name": "Ajour 0.4.0",
    "published_at": "2026-11-08T12:34:56Z",
    "html_url": "https://github.com/JonasDoebertin/ajour/releases/tag/v0.4.0",
}


def openssl_signs_ed25519():
    with tempfile.TemporaryDirectory() as directory:
        try:
            key = Path(directory) / "key.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", str(key)], check=True, capture_output=True)
            message = Path(directory) / "message"
            message.write_bytes(b"x")
            subprocess.run(
                ["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(key), "-in", str(message)],
                check=True, capture_output=True,
            )
            return True
        except (OSError, subprocess.CalledProcessError):
            return False


CAN_SIGN = openssl_signs_ed25519()
needs_ed25519 = unittest.skipUnless(CAN_SIGN, "openssl lacks Ed25519 support (LibreSSL); CI runs these on Ubuntu")


def throwaway_key():
    with tempfile.TemporaryDirectory() as directory:
        pem = Path(directory) / "key.pem"
        subprocess.run(["openssl", "genpkey", "-algorithm", "ed25519", "-out", str(pem)], check=True, capture_output=True)
        private = subprocess.run(
            ["openssl", "pkey", "-in", str(pem), "-outform", "DER"], check=True, capture_output=True
        ).stdout
        public = subprocess.run(
            ["openssl", "pkey", "-in", str(pem), "-pubout", "-outform", "DER"], check=True, capture_output=True
        ).stdout
    return base64.b64encode(private[-32:]).decode(), base64.b64encode(public[-32:]).decode()


class AppcastTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.archive = self.directory / "Ajour.zip"
        self.release = self.directory / "release.json"
        self.release.write_text(json.dumps(RELEASE))
        self.notes = self.directory / "notes.html"
        self.notes.write_text(NOTES)
        self.output = self.directory / "appcast.xml"
        self.key_file = self.directory / "seed"

    def write_archive(self, public_key=None):
        info = {"CFBundleVersion": "57", "CFBundleShortVersionString": "0.4.0", "LSMinimumSystemVersion": "26.0"}
        if public_key is not None:
            info["SUPublicEDKey"] = public_key
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("Ajour.app/Contents/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            archive.writestr("Ajour.app/Contents/MacOS/Ajour", b"binary")

    def run_cli(self):
        return subprocess.run(
            [
                sys.executable, "-I", str(SCRIPT),
                "--release", str(self.release), "--notes", str(self.notes), "--archive", str(self.archive),
                "--key-file", str(self.key_file), "--output", str(self.output),
            ],
            capture_output=True, text=True,
        )

    def test_readsVersionsAndKeyFromTheArchive(self):
        self.write_archive(public_key="cHVibGlj")
        info = appcast.bundle_info(self.archive)
        self.assertEqual(info.version, "57")
        self.assertEqual(info.short_version, "0.4.0")
        self.assertEqual(info.minimum_system_version, "26.0")
        self.assertEqual(info.public_key, "cHVibGlj")

    def test_archiveWithoutPublicKeyIsSkipped(self):
        self.write_archive()
        self.key_file.write_text("irrelevant")
        result = self.run_cli()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("SUPublicEDKey", result.stdout)
        self.assertFalse(self.output.exists())

    @needs_ed25519
    def test_signatureVerifiesWithTheMatchingKey(self):
        seed, public = throwaway_key()
        self.write_archive()
        signature = appcast.sign(self.archive, seed)
        self.assertEqual(appcast.public_key_for(seed), public)
        self.assertTrue(appcast.verify(self.archive, signature, public))

    @needs_ed25519
    def test_signatureFailsWithAnotherKey(self):
        seed, _ = throwaway_key()
        _, other_public = throwaway_key()
        self.write_archive()
        signature = appcast.sign(self.archive, seed)
        self.assertFalse(appcast.verify(self.archive, signature, other_public))

    @needs_ed25519
    def test_mismatchedKeyFileFails(self):
        seed, _ = throwaway_key()
        _, other_public = throwaway_key()
        self.write_archive(public_key=other_public)
        self.key_file.write_text(seed + "\n")
        result = self.run_cli()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn(seed, result.stdout + result.stderr)
        self.assertFalse(self.output.exists())

    @needs_ed25519
    def test_seedOfTheWrongLengthFails(self):
        _, public = throwaway_key()
        self.write_archive(public_key=public)
        self.key_file.write_text(base64.b64encode(b"short").decode())
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)
        self.assertIn("SPARKLE_PRIVATE_KEY must be the base64 32-byte seed from generate_keys -x", result.stderr + result.stdout)
        self.assertFalse(self.output.exists())

    @needs_ed25519
    def test_feedHasOneItemWithSparkleFields(self):
        seed, public = throwaway_key()
        self.write_archive(public_key=public)
        self.key_file.write_text(seed + "\n")
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        channel = ElementTree.parse(self.output).getroot().find("channel")
        self.assertEqual(channel.findtext("title"), "Ajour")
        self.assertEqual(channel.findtext("link"), "https://ajour.email/")
        items = channel.findall("item")
        self.assertEqual(len(items), 1)
        item = items[0]
        self.assertEqual(item.findtext("title"), "Ajour 0.4.0")
        self.assertEqual(item.findtext(SPARKLE + "version"), "57")
        self.assertEqual(item.findtext(SPARKLE + "shortVersionString"), "0.4.0")
        self.assertEqual(item.findtext(SPARKLE + "minimumSystemVersion"), "26.0")
        self.assertEqual(item.findtext("pubDate"), "Sun, 08 Nov 2026 12:34:56 +0000")
        enclosure = item.find("enclosure")
        self.assertEqual(
            enclosure.get("url"), "https://github.com/JonasDoebertin/ajour/releases/download/v0.4.0/Ajour.zip"
        )
        self.assertEqual(enclosure.get("length"), str(self.archive.stat().st_size))
        self.assertEqual(enclosure.get("type"), "application/octet-stream")
        self.assertTrue(appcast.verify(self.archive, enclosure.get(SPARKLE + "edSignature"), public))
        self.assertNotIn(seed, self.output.read_text())

    @needs_ed25519
    def test_notesWithMarkupCharactersStayValidXML(self):
        seed, public = throwaway_key()
        self.write_archive(public_key=public)
        self.key_file.write_text(seed)
        self.assertEqual(self.run_cli().returncode, 0)
        root = ElementTree.fromstring(self.output.read_text())
        self.assertEqual(root.find("channel/item/description").text, NOTES)
        self.assertNotIn("CDATA", self.output.read_text())


if __name__ == "__main__":
    unittest.main()
