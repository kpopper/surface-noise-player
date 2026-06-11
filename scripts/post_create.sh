#!/usr/bin/env bash
# Run this once after `flutter create .` to patch Info.plist and install pods.
# Usage: bash scripts/post_create.sh

set -e
PLIST="ios/Runner/Info.plist"

echo "→ Patching $PLIST for background audio and file access…"

# Insert background audio + document browser keys before closing </dict>
python3 - <<'PYEOF'
import re, sys

plist_path = "ios/Runner/Info.plist"
with open(plist_path) as f:
    content = f.read()

insert = """
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>audio</string>
\t</array>
\t<key>UISupportsDocumentBrowser</key>
\t<true/>
\t<key>LSSupportsOpeningDocumentsInPlace</key>
\t<true/>
"""

# Avoid double-patching
if "UIBackgroundModes" in content:
    print("  Info.plist already patched, skipping.")
    sys.exit(0)

# Insert before last </dict>
patched = re.sub(r'(</dict>\s*</plist>)', insert + r'\1', content)
with open(plist_path, "w") as f:
    f.write(patched)
print("  Done.")
PYEOF

echo "→ Installing Flutter packages…"
flutter pub get

echo "→ Installing CocoaPods…"
cd ios && pod install && cd ..

echo ""
echo "✓ All done! Run the app with: flutter run"
