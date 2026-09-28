#!/bin/bash
#
# Uninstall the moOde MQTT bridge.
#
#   sudo ./uninstall.sh           # removes service + script, keeps the config
#   sudo ./uninstall.sh --purge   # also removes /etc/moode-mqtt-bridge.conf
#
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }

systemctl disable --now moode-mqtt-bridge 2>/dev/null || true
rm -f /etc/systemd/system/moode-mqtt-bridge.service
rm -f /usr/local/bin/moode-mqtt-bridge.sh

if [ "${1:-}" = "--purge" ]; then
  rm -f /etc/moode-mqtt-bridge.conf
  echo "Removed service, script and config."
else
  echo "Removed service and script. (Config kept: /etc/moode-mqtt-bridge.conf)"
fi

systemctl daemon-reload
echo "Note: shairport-sync session_timeout was left as-is."
