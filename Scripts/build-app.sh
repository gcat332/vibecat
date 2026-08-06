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
# Plan 7 Task 6: `vibecat-hook` was never bundled, so it only ever existed at
# `.build/{debug,release}/vibecat-hook` — a path that moves with the build
# configuration and lives inside a directory a person may delete. A hook snippet
# pasted into another CLI's config file outlives all of that, so pointing it there
# was not an installation. It now ships inside the bundle, which means it is
# signed in the same `codesign` pass below as the app and cannot drift out of step
# with it. The fixed path a snippet actually names is the mirror
# `HookBinary.installIfNeeded()` writes on launch; see that type's doc comment for
# why there are two locations rather than one.
swift build -c "$CONFIG" --product vibecat-hook

# `${APP}`, braced, not `$APP…`: this machine's `/usr/bin/env bash` is the
# system bash 3.2.57, which reads the ellipsis's UTF-8 bytes as part of the
# variable name and so looks up `APP…` — unbound, and `set -u` aborts the whole
# script before the bundle is ever assembled. Line 28 above escapes this only
# because `)` happens to terminate the name first.
echo "assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/vibecat" "$APP/Contents/MacOS/vibecat"
# Beside `vibecat`, not in `Contents/Helpers` or `Contents/Resources`:
# `HookBinary.bundledURL` resolves "the sibling of the running executable", which
# is the one rule that is correct for both a bundle and a bare `swift run vibecat`
# (where the sibling is `.build/debug/vibecat-hook`). Moving it elsewhere in the
# bundle means teaching that function two rules.
cp "$BIN/vibecat-hook" "$APP/Contents/MacOS/vibecat-hook"
# The generated resource bundle carrying the source icons goes in
# `Contents/Resources`, **not** beside the executable like `vibecat-hook`.
#
# Measured: a `.bundle` in `Contents/MacOS` makes `codesign` fail the whole app with
# "bundle format unrecognized, invalid, or unsuitable" naming the subcomponent —
# nested bundles belong in `Resources`, `Frameworks` or `PlugIns` and nowhere else.
# That location also happens to be the first one SwiftPM's generated `Bundle.module`
# looks in (`Bundle.main.resourceURL`), so the codesign-correct place and the
# findable place are the same place.
#
# Missing it is not fatal: `BundledIcon.path` returns nil and `SourceIcon` falls back
# to `CLIMark`'s neutral geometry, which is what shipped before the icons existed.
mkdir -p "$APP/Contents/Resources"
for RB in "$BIN"/*.bundle; do
  [ -e "$RB" ] || continue
  cp -R "$RB" "$APP/Contents/Resources/"
done
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
  # Inside out: a second Mach-O in `Contents/MacOS` is *nested code*, and
  # `codesign --verify --strict` on the bundle below fails with
  # "code object is not signed at all in subcomponent" unless it carries its own
  # signature first. Signing the bundle does not recurse (`--deep` is deprecated
  # and, per Apple's own note, the wrong tool for this), so the helper is signed
  # explicitly and the app's seal then covers the signed helper.
  codesign --force --sign "$SIGN_ID" --timestamp=none \
           --options runtime "$APP/Contents/MacOS/vibecat-hook" >/dev/null 2>&1 \
    || codesign --force --sign "$SIGN_ID" "$APP/Contents/MacOS/vibecat-hook"
  codesign --force --sign "$SIGN_ID" --timestamp=none \
           --options runtime "$APP" >/dev/null 2>&1 \
    || codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "WARNING: no signing certificate found — falling back to ad-hoc." >&2
  echo "         Every rebuild will change the code hash, so macOS will treat" >&2
  echo "         each build as a new program and re-ask for every permission." >&2
  codesign --force --sign - "$APP/Contents/MacOS/vibecat-hook"
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
