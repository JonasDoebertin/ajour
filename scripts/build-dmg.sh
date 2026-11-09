#!/bin/bash
# Builds Ajour's disk image from an app bundle without Finder.
# Usage: scripts/build-dmg.sh <path to Ajour.app> <path of the .dmg to write>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <app> <output.dmg>" >&2
  exit 2
fi

app="$1"
output="$2"
repository="$(cd "$(dirname "$0")/.." && pwd)"
packaging="$repository/packaging/dmg"
venv="$repository/build/dmg-venv"

if [ ! -x "$venv/bin/python" ]; then
  python3 -m venv "$venv"
fi
"$venv/bin/pip" install --quiet --disable-pip-version-check --only-binary :all: --require-hashes \
  -r "$packaging/requirements.txt"

rm -f "$output"
"$venv/bin/python" -I -m dmgbuild \
  -s "$packaging/settings.py" \
  -D app="$app" \
  -D background="$packaging/background.png" \
  Ajour "$output"

echo "$output"
