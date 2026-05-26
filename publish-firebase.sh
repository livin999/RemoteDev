#!/usr/bin/env bash
#
# publish-firebase.sh — push your latest APK to Firebase App Distribution.
#
# Works for ANY of your projects: drop a one-line file named ".firebase-app-id"
# in each project's root containing that app's Firebase App ID, and this same
# script handles them all. Testers get a notification and install/update from
# the "Firebase App Tester" app on their phone.
#
# Usage:
#   ./publish-firebase.sh                     # newest APK, notes from last commit
#   ./publish-firebase.sh path/to/app.apk     # a specific file
#
# Config (per project):
#   .firebase-app-id   file holding the App ID   (or env FIREBASE_APP_ID)
#   FIREBASE_GROUP     tester group alias         (default: testers)

set -euo pipefail

GROUP="${FIREBASE_GROUP:-testers}"

# ---- app id -----------------------------------------------------------------
APP_ID="${FIREBASE_APP_ID:-}"
if [[ -z "$APP_ID" && -f .firebase-app-id ]]; then
  APP_ID=$(tr -d '[:space:]' < .firebase-app-id)
fi
if [[ -z "$APP_ID" ]]; then
  echo "X No Firebase App ID found." >&2
  echo "  Put the app's ID in a file '.firebase-app-id' in this project root," >&2
  echo "  e.g.  echo '1:1234567890:android:abc123' > .firebase-app-id" >&2
  echo "  (find it in Firebase console > Project settings > General)" >&2
  exit 1
fi

# ---- firebase cli -----------------------------------------------------------
if command -v firebase >/dev/null 2>&1; then
  FB=(firebase)
else
  echo "* firebase CLI not found - falling back to npx (slower)." >&2
  echo "  Install once for speed:  npm install -g firebase-tools" >&2
  FB=(npx --yes firebase-tools)
fi

# ---- locate the APK ---------------------------------------------------------
# Covers Flutter  (build/app/outputs/flutter-apk/)
#       Gradle    (app/build/outputs/apk/<variant>/)
# Excludes intermediate build artefacts under */intermediates/*.
# Picks the most recently modified matching APK.
APK="${1:-}"
if [[ -z "$APK" ]]; then
  APK=$(find . -name '*.apk' -path '*/outputs/*' \
         -not -path '*/intermediates/*' \
         -printf '%T@ %p\n' 2>/dev/null \
         | sort -n | tail -1 | cut -d' ' -f2-)
fi
if [[ -z "$APK" || ! -f "$APK" ]]; then
  echo "X No APK found. Pass one explicitly, e.g.:" >&2
  echo "    ./publish-firebase.sh app/build/outputs/apk/debug/app-debug.apk" >&2
  exit 1
fi
echo "* APK:    $APK  ($(du -h "$APK" | cut -f1))"
echo "* App ID: $APP_ID"
echo "* Group:  $GROUP"

# ---- release notes from the last commit (if this is a git repo) -------------
NOTES="New build"
if git rev-parse --git-dir >/dev/null 2>&1; then
  NOTES=$(git log -1 --pretty=%s 2>/dev/null || echo "New build")
fi

# ---- distribute -------------------------------------------------------------
echo "* uploading to Firebase App Distribution..."
"${FB[@]}" appdistribution:distribute "$APK" \
  --app "$APP_ID" \
  --groups "$GROUP" \
  --release-notes "$NOTES"

echo
echo "Done. Your testers get a notification in the Firebase App Tester app."
