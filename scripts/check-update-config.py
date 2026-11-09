"""Checks that the generated Info.plist and entitlements keep the configuration Sparkle needs.

    python3 -I scripts/check-update-config.py

Prints one line per problem and exits 1, or prints "update config OK" and exits 0.
"""

import base64
import binascii
import plistlib
import sys
from pathlib import Path

FEED_URL = "https://ajour.email/appcast.xml"
PUBLIC_KEY_LENGTH = 32
MACH_LOOKUP_ENTITLEMENT = "com.apple.security.temporary-exception.mach-lookup.global-name"
MACH_LOOKUP_NAMES = ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"]
ROOT = Path(__file__).resolve().parent.parent


def is_public_key(value):
    try:
        return len(base64.b64decode(value, validate=True)) == PUBLIC_KEY_LENGTH
    except (binascii.Error, TypeError, ValueError):
        return False


def problems(info, entitlements):
    if info.get("SUFeedURL") != FEED_URL:
        yield f"SUFeedURL is not {FEED_URL}"
    if not is_public_key(info.get("SUPublicEDKey")):
        yield "SUPublicEDKey is not a 32-byte Ed25519 public key"
    if info.get("SUEnableInstallerLauncherService") is not True:
        yield "SUEnableInstallerLauncherService is not true"
    if info.get("SUEnableSystemProfiling") is not False:
        yield "SUEnableSystemProfiling is not false"
    granted = entitlements.get(MACH_LOOKUP_ENTITLEMENT, [])
    for name in MACH_LOOKUP_NAMES:
        if name not in granted:
            yield f"{MACH_LOOKUP_ENTITLEMENT} is missing {name}"


def load(path):
    with (ROOT / path).open("rb") as file:
        return plistlib.load(file)


found = list(problems(load("Ajour/Info.plist"), load("Ajour/Ajour.entitlements")))
if found:
    print("\n".join(found))
    sys.exit(1)
print("update config OK")
