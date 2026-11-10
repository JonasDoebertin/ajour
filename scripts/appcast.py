"""Builds, signs and verifies the Sparkle appcast for the latest published release.

    python3 -I scripts/appcast.py --release release.json --notes notes.html \
        --archive Ajour.zip --key-file seed --output appcast.xml

release.json is GitHub's "latest release" response, notes.html the rendered release notes and
seed the base64 Ed25519 seed exported by Sparkle's generate_keys -x. Needs OpenSSL 3.

Writes the feed and exits 0, or prints the problem and exits 1.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import email.utils
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DOWNLOAD_URL = "https://github.com/JonasDoebertin/ajour/releases/download/{tag}/Ajour.zip"
INFO_PLIST = "Ajour.app/Contents/Info.plist"
PRIVATE_KEY_PREFIX = bytes.fromhex("302e020100300506032b657004220420")
PUBLIC_KEY_PREFIX = bytes.fromhex("302a300506032b6570032100")
SEED_PROBLEM = "SPARKLE_PRIVATE_KEY must be the base64 32-byte seed from generate_keys -x"

ElementTree.register_namespace("sparkle", SPARKLE_NAMESPACE)


class AppcastError(Exception):
    pass


@dataclass
class BundleInfo:
    version: str
    short_version: str
    minimum_system_version: str
    public_key: str | None


@dataclass
class AppcastItem:
    title: str
    version: str
    short_version: str
    minimum_system_version: str
    published_at: datetime
    notes_html: str
    download_url: str
    length: int
    signature: str


def bundle_info(archive: Path) -> BundleInfo:
    try:
        with zipfile.ZipFile(archive) as bundle:
            info = plistlib.loads(bundle.read(INFO_PLIST))
    except (OSError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise AppcastError(f"cannot read {INFO_PLIST} from {archive}: {error}") from error
    try:
        return BundleInfo(
            version=info["CFBundleVersion"],
            short_version=info["CFBundleShortVersionString"],
            minimum_system_version=info["LSMinimumSystemVersion"],
            public_key=info.get("SUPublicEDKey"),
        )
    except KeyError as error:
        raise AppcastError(f"{INFO_PLIST} has no {error.args[0]}") from error


def decode_seed(seed_b64: str) -> bytes:
    try:
        seed = base64.b64decode(seed_b64.strip(), validate=True)
    except binascii.Error as error:
        raise AppcastError(SEED_PROBLEM) from error
    if len(seed) != 32:
        raise AppcastError(SEED_PROBLEM)
    return seed


def pem(label: str, der: bytes) -> bytes:
    body = base64.encodebytes(der).decode()
    return f"-----BEGIN {label}-----\n{body}-----END {label}-----\n".encode()


def write_private(path: Path, content: bytes):
    with open(path, "xb", opener=lambda name, flags: os.open(name, flags, 0o600)) as file:
        file.write(content)


def openssl(*arguments: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["openssl", *arguments], capture_output=True)
    except OSError as error:
        raise AppcastError(f"cannot run openssl: {error}") from error


def public_key_for(seed_b64: str) -> str:
    seed = decode_seed(seed_b64)
    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / "private.pem"
        write_private(key, pem("PRIVATE KEY", PRIVATE_KEY_PREFIX + seed))
        result = openssl("pkey", "-in", str(key), "-pubout", "-outform", "DER")
    if result.returncode != 0 or not result.stdout.startswith(PUBLIC_KEY_PREFIX):
        raise AppcastError("openssl could not derive the public key; OpenSSL 3 is required for Ed25519")
    return base64.b64encode(result.stdout[len(PUBLIC_KEY_PREFIX):]).decode()


def sign(archive: Path, seed_b64: str) -> str:
    seed = decode_seed(seed_b64)
    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / "private.pem"
        signature = Path(directory) / "signature"
        write_private(key, pem("PRIVATE KEY", PRIVATE_KEY_PREFIX + seed))
        result = openssl(
            "pkeyutl", "-sign", "-rawin", "-inkey", str(key), "-in", str(archive), "-out", str(signature)
        )
        if result.returncode != 0:
            raise AppcastError("openssl could not sign the archive; OpenSSL 3 is required for Ed25519")
        return base64.b64encode(signature.read_bytes()).decode()


def verify(archive: Path, signature_b64: str, public_key_b64: str) -> bool:
    try:
        signature = base64.b64decode(signature_b64, validate=True)
        public_key = base64.b64decode(public_key_b64, validate=True)
    except binascii.Error:
        return False
    if len(public_key) != 32:
        return False
    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / "public.pem"
        signature_file = Path(directory) / "signature"
        key.write_bytes(pem("PUBLIC KEY", PUBLIC_KEY_PREFIX + public_key))
        signature_file.write_bytes(signature)
        result = openssl(
            "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(key),
            "-sigfile", str(signature_file), "-in", str(archive),
        )
    return result.returncode == 0


def appcast(item: AppcastItem) -> str:
    def sparkle(name: str) -> str:
        return f"{{{SPARKLE_NAMESPACE}}}{name}"

    rss = ElementTree.Element("rss", {"version": "2.0"})
    channel = ElementTree.SubElement(rss, "channel")
    ElementTree.SubElement(channel, "title").text = "Ajour"
    ElementTree.SubElement(channel, "link").text = "https://ajour.email/"
    entry = ElementTree.SubElement(channel, "item")
    ElementTree.SubElement(entry, "title").text = item.title
    ElementTree.SubElement(entry, "pubDate").text = email.utils.format_datetime(item.published_at)
    ElementTree.SubElement(entry, sparkle("version")).text = item.version
    ElementTree.SubElement(entry, sparkle("shortVersionString")).text = item.short_version
    ElementTree.SubElement(entry, sparkle("minimumSystemVersion")).text = item.minimum_system_version
    ElementTree.SubElement(entry, "description").text = item.notes_html
    ElementTree.SubElement(entry, "enclosure", {
        "url": item.download_url,
        "length": str(item.length),
        "type": "application/octet-stream",
        sparkle("edSignature"): item.signature,
    })
    ElementTree.indent(rss)
    return ElementTree.tostring(rss, encoding="unicode", xml_declaration=True) + "\n"


def read_release(path: Path) -> dict:
    try:
        release = json.loads(path.read_text(encoding="utf-8"))
        return {"tag_name": release["tag_name"], "published_at": release["published_at"]}
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise AppcastError(f"{path} is not a GitHub release: {error!r}") from error


def build(arguments: argparse.Namespace) -> int:
    info = bundle_info(arguments.archive)
    if info.public_key is None:
        raise AppcastError("the app has no SUPublicEDKey, so it cannot verify updates")

    release = read_release(arguments.release)
    published_at = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    try:
        seed = arguments.key_file.read_text(encoding="ascii")
    except (OSError, UnicodeDecodeError) as error:
        raise AppcastError(f"cannot read the key file: {error.__class__.__name__}") from error

    signature = sign(arguments.archive, seed)
    if not verify(arguments.archive, signature, info.public_key):
        raise AppcastError("the signature does not verify against the app's SUPublicEDKey; wrong SPARKLE_PRIVATE_KEY?")

    feed = appcast(AppcastItem(
        title=f"Ajour {info.short_version}",
        version=info.version,
        short_version=info.short_version,
        minimum_system_version=info.minimum_system_version,
        published_at=published_at,
        notes_html=arguments.notes.read_text(encoding="utf-8"),
        download_url=DOWNLOAD_URL.format(tag=release["tag_name"]),
        length=arguments.archive.stat().st_size,
        signature=signature,
    ))
    arguments.output.write_text(feed, encoding="utf-8")
    print(f"{arguments.output} written for {info.short_version} ({info.version})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Builds and signs the Sparkle appcast.")
    for name in ("release", "notes", "archive", "key-file", "output"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        return build(arguments)
    except (AppcastError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
