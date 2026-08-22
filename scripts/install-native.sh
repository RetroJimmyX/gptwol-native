#!/bin/sh
set -eu

APP_DIR=/opt/gptwol
DATA_DIR=/var/lib/gptwol
SERVICE_USER=gptwol

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this installer with sudo/root." >&2
  exit 1
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi

mkdir -p "$APP_DIR" "$DATA_DIR"

if [ -f /app/db/computers.db ] && [ ! -f "$DATA_DIR/computers.db" ]; then
  cp -a /app/db/computers.db "$DATA_DIR/computers.db"
fi

if [ -f /app/db/computers.txt ] && [ ! -f "$DATA_DIR/computers.txt" ]; then
  cp -a /app/db/computers.txt "$DATA_DIR/computers.txt"
fi

chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" "$DATA_DIR"

python3 -m venv --system-site-packages "$APP_DIR/.venv" 2>/dev/null || python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt" gunicorn

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
