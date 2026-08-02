#!/usr/bin/env bash
# Assembles and signs VibeCat.app.
#
#   Scripts/build-app.sh              # debug build
#   Scripts/build-app.sh release      # release build
#   VIBECAT_SIGN_ID="Apple Development: you (TEAMID)" Scripts/build-app.sh
#
# Why a bundle at all, when `swift run vibecat` works: a bare executable has no
# bundle identifier, so macOS attributes its permission requests to whatever
# launched it — the terminal — and a permission granted that way disappears the
# moment the app is opened any other way. Measured on this project before the
# bundle existed: `Bundle.main.bundleIdentifier` was nil and
# CGPreflightScreenCaptureAccess() returned true purely by inheriting the
# terminal's grant.
#
# Why signing with a real identity and not `codesign -s -`: TCC remembers a
# grant against the bundle id *and* the code's designated requirement. Ad-hoc
# signing puts the binary's cdhash in that requirement, and every rebuild
# changes it, so every rebuild asks again. An Apple Development or Developer ID
# certificate puts the team identifier there instead, and the grant survives.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
BIN=$(swift build -c "$CONFIG" --show-bin-path)
APP=".build/VibeCat.app"

echo "building ($CONFIG)…"
swift build -c "$CONFIG" --product vibecat

echo "assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/vibecat" "$APP/Contents/MacOS/vibecat"
cp Sources/VibeCatApp/Info.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Prefer an explicit identity, then the first Apple Development / Developer ID
# certificate in the keychain, and only then fall back to ad-hoc — loudly,
# because ad-hoc means re-granting every permission after every build.
SIGN_ID="${VIBECAT_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
fi

if [ -n "$SIGN_ID" ]; then
  echo "signing with: $SIGN_ID"
  codesign --force --sign "$SIGN_ID" --timestamp=none \
           --options runtime "$APP" >/dev/null 2>&1 \
    || codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "WARNING: no signing certificate found — falling back to ad-hoc." >&2
  echo "         Every rebuild will change the code hash, so macOS will treat" >&2
  echo "         each build as a new program and re-ask for every permission." >&2
  codesign --force --sign - -i com.gcat332.vibecat "$APP"
fi

codesign --verify --strict "$APP"
echo
echo "built: $APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" | sed 's/^/  /' || true
echo
echo "run it with:   open $APP"
echo "  (not by running the binary inside it — launching it from a shell makes"
echo "   the shell the responsible process again, which is the thing the bundle"
echo "   exists to avoid)"
