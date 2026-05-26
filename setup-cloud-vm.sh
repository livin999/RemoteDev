#!/usr/bin/env bash
#
# setup-cloud-vm.sh — bootstrap a fresh Ubuntu 22.04+ VM for Flutter/Android
# builds with Claude Code. Designed for Oracle Cloud Ampere ARM (free tier).
# Also works on x86_64 (DigitalOcean, Hetzner, etc.) — script auto-detects arch.
#
# Usage on the VM:
#   curl -fsSL https://raw.githubusercontent.com/livin999/RemoteDev/master/setup-cloud-vm.sh | bash
# or:
#   scp setup-cloud-vm.sh ubuntu@<vm-ip>:~ && ssh ubuntu@<vm-ip> 'bash setup-cloud-vm.sh'
#
# After this finishes:
#   1. Paste your /home/vince/projects/dev/Creds/creds file to ~/projects/dev/Creds/creds
#   2. claude login
#   3. firebase login --no-localhost
#   4. Clone your project repos under ~/projects/dev/
#   5. Run claude — it will read CLAUDE.md and handle the rest

set -euo pipefail

ARCH=$(uname -m)
case "$ARCH" in
  aarch64|arm64) ANDROID_ARCH="arm" ;;
  x86_64)        ANDROID_ARCH="x86_64" ;;
  *)             echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

log() { echo "→ $*"; }

# ── 1. System packages ──────────────────────────────────────────────────────
log "Updating apt and installing base packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  curl git unzip zip xz-utils \
  build-essential clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libglu1-mesa \
  openjdk-17-jdk \
  python3 python3-pip \
  tmux htop jq

# ── 2. Node.js + npm (NodeSource for current LTS) ───────────────────────────
if ! command -v node >/dev/null || [[ "$(node -v | sed 's/v//; s/\..*//')" -lt 20 ]]; then
  log "Installing Node.js 20.x..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi

# ── 3. Claude Code ──────────────────────────────────────────────────────────
if ! command -v claude >/dev/null; then
  log "Installing Claude Code..."
  sudo npm install -g @anthropic-ai/claude-code
fi

# ── 4. Firebase CLI ─────────────────────────────────────────────────────────
if ! command -v firebase >/dev/null; then
  log "Installing Firebase CLI..."
  sudo npm install -g firebase-tools
fi

# ── 5. Flutter SDK ──────────────────────────────────────────────────────────
FLUTTER_DIR="$HOME/flutter"
if [[ ! -d "$FLUTTER_DIR" ]]; then
  log "Cloning Flutter (stable channel)..."
  git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR" --depth 1
fi

# ── 6. Android SDK ──────────────────────────────────────────────────────────
ANDROID_SDK="$HOME/Android/Sdk"
if [[ ! -d "$ANDROID_SDK/cmdline-tools/latest" ]]; then
  log "Installing Android command-line tools..."
  mkdir -p "$ANDROID_SDK/cmdline-tools"
  cd /tmp
  curl -fsSL -o cmdtools.zip \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q cmdtools.zip
  mv cmdline-tools "$ANDROID_SDK/cmdline-tools/latest"
  rm -f cmdtools.zip
  cd "$HOME"
fi

# ── 7. PATH + env setup ─────────────────────────────────────────────────────
PROFILE="$HOME/.bashrc"
if ! grep -q "FLUTTER_HOME" "$PROFILE" 2>/dev/null; then
  log "Adding env vars to ~/.bashrc..."
  cat >> "$PROFILE" <<'EOF'

# ── Flutter + Android ────────────────────────────────────────────────────────
export FLUTTER_HOME="$HOME/flutter"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"
EOF
fi

# Source env for this session
export FLUTTER_HOME="$HOME/flutter"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ── 8. Android SDK packages + licenses ──────────────────────────────────────
log "Accepting Android SDK licenses..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true

log "Installing Android SDK packages (this takes ~5 min)..."
sdkmanager --install \
  "platform-tools" \
  "platforms;android-34" \
  "platforms;android-35" \
  "build-tools;34.0.0" \
  "build-tools;35.0.0" >/dev/null

# ── 9. Flutter config + precache ────────────────────────────────────────────
log "Configuring Flutter (Android only, no analytics)..."
flutter config --android-sdk "$ANDROID_HOME" --no-analytics >/dev/null
flutter config --no-enable-ios --no-enable-macos-desktop --no-enable-linux-desktop \
  --no-enable-windows-desktop --no-enable-web >/dev/null
flutter precache --android --no-ios >/dev/null

log "Accepting Flutter Android licenses..."
yes | flutter doctor --android-licenses >/dev/null 2>&1 || true

# ── 10. Workspace dirs ──────────────────────────────────────────────────────
mkdir -p "$HOME/projects/dev/Creds"
mkdir -p "$HOME/.claude"

# ── 11. Final report ────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════════════════════"
echo "  ✓ VM bootstrap complete"
echo "════════════════════════════════════════════════════════════════════"
echo
flutter --version 2>/dev/null | head -1
echo "Java:    $(java -version 2>&1 | head -1)"
echo "Node:    $(node -v)"
echo "Claude:  $(claude --version 2>/dev/null || echo not-logged-in)"
echo "Firebase:$(firebase --version)"
echo
echo "Next steps:"
echo "  1. source ~/.bashrc"
echo "  2. flutter doctor    # confirm Android toolchain is green"
echo "  3. Put your creds:   nano ~/projects/dev/Creds/creds"
echo "  4. Put your CLAUDE.md: nano ~/.claude/CLAUDE.md"
echo "  5. claude login"
echo "  6. firebase login --no-localhost"
echo "  7. Clone your repos under ~/projects/dev/"
echo "  8. Run 'claude' and ask it to build any app"
echo
