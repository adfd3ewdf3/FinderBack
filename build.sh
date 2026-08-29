#!/bin/bash
#
# Builds FinderBack.app with swiftc. No Xcode project, no SPM, no dependencies.
#
# The app is built IN PLACE, here in the project folder. That is the whole install:
# there is no second copy anywhere. To "install" it, drag FinderBack.app wherever you
# want it to live (/Applications) — see walkthrough.md, "Shipping a change".
#
set -euo pipefail
cd "$(dirname "$0")"

APP="FinderBack.app"
BIN="$APP/Contents/MacOS/FinderBack"

echo "==> cleaning $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> copying Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f icon.icns ]; then
    echo "==> copying icon"
    # Info.plist points CFBundleIconFile at "AppIcon", so the file must land under
    # that name regardless of what it is called in the project folder.
    cp icon.icns "$APP/Contents/Resources/AppIcon.icns"
else
    echo "==> no icon.icns — building without an icon"
fi

echo "==> compiling Sources/*.swift"
swiftc \
  -O \
  -target arm64-apple-macos26.0 \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -o "$BIN" \
  Sources/*.swift

echo "==> ad-hoc signing (gives TCC a stable identity for this build)"
# Ad-hoc means "signed by nobody". Fine for running locally, but every rebuild
# produces a new identity, which is why macOS makes you re-grant Accessibility
# after each build. A real Developer ID would make the grant stick — see
# walkthrough.md, "Distribution".
codesign --force --sign - "$APP"

echo
echo "Built ./$APP"
echo "Run it with:  ./run.sh          (or open it: open $APP)"
