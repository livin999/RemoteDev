#!/usr/bin/env bash
#
# publish-appstore.sh — publish the latest APK to the private app store.
#
# APK → GitHub Release asset (github.com/livin999/appstore, tag: <slug>-latest)
# Manifest → apps.json updated, then Firebase Hosting deployed (HTML + JSON only)
# Page → https://wome-app.web.app
#
# Usage:
#   ./publish-appstore.sh               # auto-find newest APK
#   ./publish-appstore.sh path/to/app.apk
#
# Config (project root):
#   .appstore-config   APP_NAME=<display name>  APP_SLUG=<url-safe id>

set -euo pipefail

APPSTORE_DIR="${APPSTORE_DIR:-$HOME/projects/dev/RemoteDev/appstore}"
APPSTORE_PROJECT="wome-app"
GH_REPO="livin999/appstore"

# Read GitHub token from creds file
CREDS_FILE="${CREDS_FILE:-$HOME/projects/dev/Creds/creds}"
if [[ ! -f "$CREDS_FILE" ]]; then
  echo "X Creds file not found: $CREDS_FILE" >&2
  echo "  Set CREDS_FILE env var or create the file with GITHUB_TOKEN=..." >&2
  exit 1
fi
GH_TOKEN=$(grep '^GITHUB_TOKEN=' "$CREDS_FILE" | cut -d= -f2-)
if [[ -z "$GH_TOKEN" ]]; then
  echo "X GITHUB_TOKEN missing in $CREDS_FILE" >&2
  exit 1
fi

# ---- per-project config -----------------------------------------------------
if [[ ! -f .appstore-config ]]; then
  echo "X No .appstore-config found in $(pwd)." >&2
  echo "  Create one:" >&2
  echo "    printf 'APP_NAME=MyApp\nAPP_SLUG=myapp\n' > .appstore-config" >&2
  exit 1
fi
APP_NAME=$(grep '^APP_NAME=' .appstore-config | cut -d= -f2-)
APP_SLUG=$(grep '^APP_SLUG=' .appstore-config | cut -d= -f2-)
if [[ -z "$APP_NAME" || -z "$APP_SLUG" ]]; then
  echo "X .appstore-config must have APP_NAME and APP_SLUG lines." >&2
  exit 1
fi

# ---- locate APK -------------------------------------------------------------
APK="${1:-}"
if [[ -z "$APK" ]]; then
  APK=$(find . -name '*.apk' -path '*/outputs/*' \
         -not -path '*/intermediates/*' \
         -printf '%T@ %p\n' 2>/dev/null \
         | sort -n | tail -1 | cut -d' ' -f2-)
fi
if [[ -z "$APK" || ! -f "$APK" ]]; then
  echo "X No APK found. Pass one explicitly:" >&2
  echo "    ./publish-appstore.sh build/app/outputs/flutter-apk/app-debug.apk" >&2
  exit 1
fi

# ---- version ----------------------------------------------------------------
VERSION="latest"
BUILD_NUM="?"
if [[ -f pubspec.yaml ]]; then
  RAW=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}')
  VERSION="${RAW%%+*}"
  BUILD_NUM="${RAW##*+}"
  [[ "$BUILD_NUM" == "$RAW" ]] && BUILD_NUM="?"
else
  # Native Android — read from app/build.gradle.kts or app/build.gradle
  for GRADLE_FILE in app/build.gradle.kts app/build.gradle; do
    if [[ -f "$GRADLE_FILE" ]]; then
      VERSION=$(grep 'versionName' "$GRADLE_FILE" | head -1 | grep -o '"[^"]*"' | tr -d '"')
      BUILD_NUM=$(grep 'versionCode' "$GRADLE_FILE" | head -1 | grep -o '[0-9]\+')
      [[ -z "$VERSION" ]] && VERSION="latest"
      [[ -z "$BUILD_NUM" ]] && BUILD_NUM="?"
      break
    fi
  done
fi

APK_SIZE=$(du -h "$APK" | cut -f1)
NOTES="New build"
if git rev-parse --git-dir >/dev/null 2>&1; then
  NOTES=$(git log -1 --pretty=%s 2>/dev/null || echo "New build")
fi
DATE_DISPLAY=$(date -u +"%Y-%m-%d")
UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TAG="${APP_SLUG}-latest"
ASSET_NAME="${APP_SLUG}-latest.apk"

echo "* App:     $APP_NAME ($APP_SLUG)"
echo "* APK:     $APK  (${APK_SIZE})"
echo "* Version: $VERSION  build $BUILD_NUM"
echo "* Notes:   $NOTES"

# ---- get or create GitHub release -------------------------------------------
GH_AUTH=(-H "Authorization: token $GH_TOKEN" -H "Accept: application/vnd.github+json")

RELEASE_JSON=$(curl -sf "${GH_AUTH[@]}" \
  "https://api.github.com/repos/$GH_REPO/releases/tags/$TAG" 2>/dev/null || echo "{}")
RELEASE_ID=$(echo "$RELEASE_JSON" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

if [[ -z "$RELEASE_ID" ]]; then
  echo "* Creating GitHub release $TAG..."
  RELEASE_JSON=$(curl -sf -X POST "${GH_AUTH[@]}" \
    "https://api.github.com/repos/$GH_REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"$APP_NAME Latest\",\"body\":\"$NOTES\",\"prerelease\":true}")
  RELEASE_ID=$(echo "$RELEASE_JSON" | python3 -c \
    "import sys,json; print(json.load(sys.stdin)['id'])")
else
  echo "* Updating GitHub release $TAG..."
  curl -sf -X PATCH "${GH_AUTH[@]}" \
    "https://api.github.com/repos/$GH_REPO/releases/$RELEASE_ID" \
    -d "{\"body\":\"$NOTES\"}" > /dev/null
  # Delete existing APK asset so we can re-upload
  ASSET_ID=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
assets = json.load(sys.stdin).get('assets', [])
match = [a['id'] for a in assets if a['name'] == '$ASSET_NAME']
print(match[0] if match else '')" 2>/dev/null || echo "")
  if [[ -n "$ASSET_ID" ]]; then
    curl -sf -X DELETE "${GH_AUTH[@]}" \
      "https://api.github.com/repos/$GH_REPO/releases/assets/$ASSET_ID" || true
  fi
fi

# ---- upload APK asset -------------------------------------------------------
echo "* Uploading APK to GitHub Releases..."
UPLOAD_RESPONSE=$(curl -sf -X POST "${GH_AUTH[@]}" \
  -H "Content-Type: application/vnd.android.package-archive" \
  "https://uploads.github.com/repos/$GH_REPO/releases/$RELEASE_ID/assets?name=$ASSET_NAME" \
  --data-binary @"$APK")

APK_URL=$(echo "$UPLOAD_RESPONSE" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['browser_download_url'])")
echo "* Uploaded → $APK_URL"

# ---- update apps.json -------------------------------------------------------
APPS_JSON="$APPSTORE_DIR/apps.json"

APP_NAME="$APP_NAME" APP_SLUG="$APP_SLUG" VERSION="$VERSION" \
BUILD_NUM="$BUILD_NUM" DATE_DISPLAY="$DATE_DISPLAY" NOTES="$NOTES" \
APK_SIZE="$APK_SIZE" UPDATED="$UPDATED" APK_URL="$APK_URL" \
APPS_JSON="$APPS_JSON" \
python3 - <<'PYEOF'
import json, os

path      = os.environ['APPS_JSON']
app_name  = os.environ['APP_NAME']
app_slug  = os.environ['APP_SLUG']
version   = os.environ['VERSION']
build_num = os.environ['BUILD_NUM']
date_disp = os.environ['DATE_DISPLAY']
notes     = os.environ['NOTES']
apk_size  = os.environ['APK_SIZE']
updated   = os.environ['UPDATED']
apk_url   = os.environ['APK_URL']

with open(path) as f:
    data = json.load(f)

entry = {
    "name":    app_name,
    "slug":    app_slug,
    "version": version,
    "build":   build_num,
    "updated": date_disp,
    "notes":   notes,
    "size":    apk_size,
    "apk":     apk_url,
}

data["apps"] = [a for a in data.get("apps", []) if a["slug"] != app_slug]
data["apps"].append(entry)
data["apps"].sort(key=lambda a: a["name"].lower())
data["updated"] = updated

with open(path, "w") as f:
    json.dump(data, f, indent=2)

print(f"* Updated apps.json ({len(data['apps'])} app(s))")
PYEOF

# ---- deploy Hosting (2 files: index.html + apps.json) -----------------------
echo "* Deploying Hosting..."
(cd "$(dirname "$APPSTORE_DIR")" && \
  firebase deploy --only hosting --project "$APPSTORE_PROJECT")

echo
echo "✓ Live at https://${APPSTORE_PROJECT}.web.app"
