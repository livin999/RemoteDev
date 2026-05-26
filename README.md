# RemoteDev

Private app store infrastructure + cloud VM bootstrap for solo Android/Flutter development.

## What this is

- **`appstore/`** — the static site served at https://remote-dev-store.web.app (Firebase Hosting). Lists all my apps with direct APK download links.
- **`publish-appstore.sh`** — canonical publish script. Copied into each project root; uploads the APK to GitHub Releases, updates `apps.json`, and redeploys the site.
- **`setup-cloud-vm.sh`** — one-shot bootstrap for a fresh Ubuntu VM. Installs Flutter, Android SDK, Java 17, Node, Claude Code, Firebase CLI. Use on Oracle Cloud Ampere (free tier) to go laptop-free.

## Cloud VM quick start

```bash
# On a fresh Ubuntu 22.04+ VM:
curl -fsSL https://raw.githubusercontent.com/livin999/RemoteDev/master/setup-cloud-vm.sh | bash
source ~/.bashrc
flutter doctor
```

Then copy your `~/projects/dev/Creds/creds` and `~/.claude/CLAUDE.md` to the VM, run `claude login`, and clone your project repos.

## Per-project setup

Each Android project needs a `.appstore-config` in its root:

```
APP_NAME=My App
APP_SLUG=myapp
```

Plus a copy of `publish-appstore.sh` (executable). The `firebase-app-distribution` skill creates these automatically on first build.
