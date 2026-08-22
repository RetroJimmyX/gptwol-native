#!/bin/sh
set -eu

APP_DIR=/opt/gptwol
DATA_DIR=/var/lib/gptwol
SERVICE_USER=gptwol
BOOTSTRAP_VERSION=5.3.8
FONTAWESOME_VERSION=7.3.1

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer with sudo/root." >&2
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

mkdir -p "$APP_DIR" "$DATA_DIR"

# Stage the checked-out application into the native installation directory.
# Exclude Git metadata and the development venv; the native installer creates
# its own venv below. This also makes the installer safe to run from /tmp.
tar -C "$SOURCE_DIR" \
  --exclude=.git \
  --exclude=.venv \
  -cf - . | tar -C "$APP_DIR" -xf -

if [ -f /app/db/computers.db ] && [ ! -f "$DATA_DIR/computers.db" ]; then
  cp -a /app/db/computers.db "$DATA_DIR/computers.db"
fi

if [ -f /app/db/computers.txt ] && [ ! -f "$DATA_DIR/computers.txt" ]; then
  cp -a /app/db/computers.txt "$DATA_DIR/computers.txt"
fi

# Docker builds vendor these exact frontend assets into the image. Do the same
# for native installs so the web UI does not depend on a CDN at runtime.
apt-get update
apt-get install -y --no-install-recommends curl unzip
rm -rf /var/lib/apt/lists/*

mkdir -p "$APP_DIR/app/templates/assets/bootstrap/css" \
         "$APP_DIR/app/templates/assets/bootstrap/js" \
         "$APP_DIR/app/templates/assets/fontawesome/css" \
         "$APP_DIR/app/templates/assets/fontawesome/webfonts"

if [ ! -f "$APP_DIR/app/templates/assets/bootstrap/css/bootstrap.min.css" ] || \
   [ ! -f "$APP_DIR/app/templates/assets/bootstrap/js/bootstrap.bundle.min.js" ]; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  curl -fsSL "https://github.com/twbs/bootstrap/releases/download/v${BOOTSTRAP_VERSION}/bootstrap-${BOOTSTRAP_VERSION}-dist.zip" \
    -o "$tmpdir/bootstrap.zip"
  unzip -q "$tmpdir/bootstrap.zip" \
    "bootstrap-${BOOTSTRAP_VERSION}-dist/css/bootstrap.min.css" \
    "bootstrap-${BOOTSTRAP_VERSION}-dist/js/bootstrap.bundle.min.js" \
    -d "$tmpdir/bootstrap"
  cp "$tmpdir/bootstrap/bootstrap-${BOOTSTRAP_VERSION}-dist/css/bootstrap.min.css" \
     "$APP_DIR/app/templates/assets/bootstrap/css/"
  cp "$tmpdir/bootstrap/bootstrap-${BOOTSTRAP_VERSION}-dist/js/bootstrap.bundle.min.js" \
     "$APP_DIR/app/templates/assets/bootstrap/js/"
fi

if [ ! -f "$APP_DIR/app/templates/assets/fontawesome/css/fontawesome.min.css" ] || \
   [ ! -f "$APP_DIR/app/templates/assets/fontawesome/css/brands.min.css" ] || \
   [ ! -f "$APP_DIR/app/templates/assets/fontawesome/css/solid.min.css" ]; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  curl -fsSL "https://use.fontawesome.com/releases/v${FONTAWESOME_VERSION}/fontawesome-free-${FONTAWESOME_VERSION}-web.zip" \
    -o "$tmpdir/fontawesome.zip"
  unzip -q "$tmpdir/fontawesome.zip" \
    "fontawesome-free-${FONTAWESOME_VERSION}-web/css/brands.min.css" \
    "fontawesome-free-${FONTAWESOME_VERSION}-web/css/fontawesome.min.css" \
    "fontawesome-free-${FONTAWESOME_VERSION}-web/css/solid.min.css" \
    "fontawesome-free-${FONTAWESOME_VERSION}-web/webfonts/*" \
    -d "$tmpdir/fontawesome"
  cp "$tmpdir/fontawesome/fontawesome-free-${FONTAWESOME_VERSION}-web/css/brands.min.css" \
     "$APP_DIR/app/templates/assets/fontawesome/css/"
  cp "$tmpdir/fontawesome/fontawesome-free-${FONTAWESOME_VERSION}-web/css/fontawesome.min.css" \
     "$APP_DIR/app/templates/assets/fontawesome/css/"
  cp "$tmpdir/fontawesome/fontawesome-free-${FONTAWESOME_VERSION}-web/css/solid.min.css" \
     "$APP_DIR/app/templates/assets/fontawesome/css/"
  cp "$tmpdir/fontawesome/fontawesome-free-${FONTAWESOME_VERSION}-web/webfonts/"* \
     "$APP_DIR/app/templates/assets/fontawesome/webfonts/"
fi

rm -rf "$APP_DIR/app/templates/assets/bootstrap/bootstrap-${BOOTSTRAP_VERSION}-dist" \
       "$APP_DIR/app/templates/assets/fontawesome/fontawesome-free-${FONTAWESOME_VERSION}-web"

chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" "$DATA_DIR"

python3 -m venv --system-site-packages "$APP_DIR/.venv" 2>/dev/null || python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/app/requirements.txt"

WAKEONLAN_BIN=$(command -v wakeonlan || true)
if [ -z "$WAKEONLAN_BIN" ]; then
  echo "wakeonlan is not installed. Install the wakeonlan package before enabling scheduled WOL." >&2
  exit 1
fi
if [ "$WAKEONLAN_BIN" != /usr/local/bin/wakeonlan ]; then
  ln -sf "$WAKEONLAN_BIN" /usr/local/bin/wakeonlan
fi

install -o root -g root -m 0644 "$APP_DIR/systemd/gptwol.service" /etc/systemd/system/gptwol.service
install -o root -g root -m 0644 "$APP_DIR/systemd/gptwol-scheduler.service" /etc/systemd/system/gptwol-scheduler.service
install -o root -g root -m 0644 "$APP_DIR/systemd/gptwol-scheduler.timer" /etc/systemd/system/gptwol-scheduler.timer

systemctl daemon-reload
systemctl enable --now gptwol.service
systemctl enable --now gptwol-scheduler.timer

if systemctl is-enabled cron.service >/dev/null 2>&1; then
  echo "NOTE: system cron remains enabled for other system jobs; GPTWOL no longer uses cron."
fi

systemctl --no-pager --full status gptwol.service || true
systemctl --no-pager --full status gptwol-scheduler.timer || true
