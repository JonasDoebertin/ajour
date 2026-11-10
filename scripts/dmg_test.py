import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
BUILD_SCRIPT = REPOSITORY / "scripts" / "build-dmg.sh"
VENV_PYTHON = REPOSITORY / "build" / "dmg-venv" / "bin" / "python"
GENERIC_ICON = Path("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
STUB_EXECUTABLE = Path("/usr/bin/true")
HAS_CUSTOM_ICON = 0x0400

READ_LAYOUT = """
import json, sys
from ds_store import DSStore

with DSStore.open(sys.argv[1], "r") as store:
    def value(name, code):
        try:
            return store[name][code]
        except KeyError:
            return None

    print(json.dumps({
        "app": list(value("Ajour.app", "Iloc") or []),
        "applications": list(value("Applications", "Iloc") or []),
        "window": value(".", "bwsp"),
        "icon_view": value(".", "icvp"),
    }, default=str))
"""


def make_stub_app(directory: Path) -> Path:
    """An ad-hoc signed app, so the tests can check that the image keeps its signature intact."""
    app = directory / "Ajour.app"
    resources = app / "Contents" / "Resources"
    resources.mkdir(parents=True)
    (app / "Contents" / "MacOS").mkdir()
    shutil.copy(STUB_EXECUTABLE, app / "Contents" / "MacOS" / "Ajour")
    shutil.copy(GENERIC_ICON, resources / "AppIcon.icns")
    with open(app / "Contents" / "Info.plist", "wb") as info:
        plistlib.dump({
            "CFBundleExecutable": "Ajour",
            "CFBundleIdentifier": "de.dieserjonas.ajour.dmg-test",
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
        }, info)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    return app


@unittest.skipUnless(sys.platform == "darwin", "disk images are built on macOS only")
class DiskImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Class cleanups run even when setUpClass fails halfway, unlike tearDownClass.
        cls.directory = Path(tempfile.mkdtemp())
        cls.addClassCleanup(shutil.rmtree, cls.directory, ignore_errors=True)
        cls.image = cls.directory / "Ajour.dmg"
        cls.mount = cls.directory / "mount"
        app = make_stub_app(cls.directory)
        subprocess.run([str(BUILD_SCRIPT), str(app), str(cls.image)], check=True, cwd=REPOSITORY)
        subprocess.run(
            ["hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", str(cls.mount), str(cls.image)],
            check=True, capture_output=True,
        )
        cls.addClassCleanup(subprocess.run, ["hdiutil", "detach", str(cls.mount), "-force"], capture_output=True)

    def layout(self) -> dict:
        result = subprocess.run(
            [str(VENV_PYTHON), "-I", "-c", READ_LAYOUT, str(self.mount / ".DS_Store")],
            check=True, capture_output=True, text=True,
        )
        return json.loads(result.stdout)

    def test_volume_is_named_ajour(self):
        info = plistlib.loads(subprocess.run(
            ["diskutil", "info", "-plist", str(self.mount)], check=True, capture_output=True,
        ).stdout)
        self.assertEqual(info["VolumeName"], "Ajour")

    def test_contains_the_app_and_an_applications_link(self):
        self.assertTrue((self.mount / "Ajour.app").is_dir())
        self.assertEqual(os.readlink(self.mount / "Applications"), "/Applications")

    def test_keeps_the_app_signature_valid(self):
        result = subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(self.mount / "Ajour.app")], capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_has_background_and_volume_icon(self):
        background = self.mount / ".background.tiff"
        self.assertTrue(background.is_file())
        info = subprocess.run(["tiffutil", "-info", str(background)], check=True, capture_output=True, text=True)
        self.assertEqual(info.stdout.count("Directory at"), 2, info.stdout)
        self.assertTrue((self.mount / ".VolumeIcon.icns").is_file())

    def test_volume_uses_its_custom_icon(self):
        result = subprocess.run(["xattr", "-px", "com.apple.FinderInfo", str(self.mount)], capture_output=True, text=True)
        finder_info = bytes.fromhex(result.stdout) if result.returncode == 0 else bytes(32)
        flags = int.from_bytes(finder_info[8:10], "big")
        self.assertTrue(flags & HAS_CUSTOM_ICON, f"Finder flags {flags:#06x}")

    def test_window_layout(self):
        layout = self.layout()
        self.assertEqual(layout["app"], [160, 260])
        self.assertEqual(layout["applications"], [480, 260])
        self.assertEqual(layout["icon_view"]["iconSize"], 128)
        self.assertEqual(layout["icon_view"]["textSize"], 13)
        self.assertRegex(layout["window"]["WindowBounds"], r"\{\{-?\d+, -?\d+\}, \{640, 432\}\}")
        for bar in ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar", "ShowTabView"):
            self.assertFalse(layout["window"].get(bar, False), bar)


if __name__ == "__main__":
    unittest.main()
