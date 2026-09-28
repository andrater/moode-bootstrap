#!/bin/bash
#
# moOde MQTT bridge
# -----------------
# Runs on the moOde (Raspberry Pi) box.
#
#   * Publishes the Bluetooth link state of a paired device (TV / streaming
#     stick) and the AirPlay "active" state to MQTT.
#   * Subscribes to an MQTT command topic and runs the local moOde tools
#     (blu-control.sh / moodeutl) when a command arrives.
#
# Configuration lives in /etc/moode-mqtt-bridge.conf (see
# moode-mqtt-bridge.conf.example). Installed by install.sh.
#
set -u

CONF="/etc/moode-mqtt-bridge.conf"
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"

# --- required ---
MQTT_HOST="${MQTT_HOST:-}"
TV_MAC="${TV_MAC:-}"

# --- optional (defaults) ---
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-}"
MQTT_PASS="${MQTT_PASS:-}"
STATE_TOPIC="${STATE_TOPIC:-moode/bluetooth/state}"
APL_TOPIC="${APL_TOPIC:-moode/airplay/active}"
CMD_TOPIC="${CMD_TOPIC:-moode/cmd}"
POLL_SECS="${POLL_SECS:-5}"

[ -n "$MQTT_HOST" ] || { echo "MQTT_HOST not set in $CONF" >&2; exit 1; }
[ -n "$TV_MAC" ]    || { echo "TV_MAC not set in $CONF" >&2; exit 1; }

# --- paths on moOde ---
MOODEUTL=/usr/local/bin/moodeutl
BLUCTL=/var/www/util/blu-control.sh
SQLDB=/var/local/www/db/moode-sqlite3.db

# Build mosquitto client options once.
MQTT_OPTS=(-h "$MQTT_HOST" -p "$MQTT_PORT")
[ -n "$MQTT_USER" ] && MQTT_OPTS+=(-u "$MQTT_USER")
[ -n "$MQTT_PASS" ] && MQTT_OPTS+=(-P "$MQTT_PASS")

pub() { mosquitto_pub "${MQTT_OPTS[@]}" -t "$1" -m "$2" -r; }

# Is the TV/streaming device connected over classic Bluetooth?
bt_connected() { timeout 5 /usr/bin/bluetoothctl info "$TV_MAC" 2>/dev/null | grep -q "Connected: yes"; }

# Is an AirPlay session active? (moOde sets cfg_system.aplactive=1 while playing.)
apl_active() { [ "$(sqlite3 "$SQLDB" "SELECT value FROM cfg_system WHERE param='aplactive';" 2>/dev/null)" = "1" ]; }

state_loop() {
  local last_bt="" last_ap=""
  while true; do
    local bt="disconnected" ap="off"
    bt_connected && bt="connected"
    apl_active   && ap="on"
    [ "$bt" != "$last_bt" ] && { pub "$STATE_TOPIC" "$bt"; last_bt="$bt"; }
    [ "$ap" != "$last_ap" ] && { pub "$APL_TOPIC"   "$ap"; last_ap="$ap"; }
    sleep "$POLL_SECS"
  done
}

do_cmd() {
  case "$1" in
    tv_on)
      timeout 60 "$MOODEUTL" -Ro --bluetooth on
      sleep 3
      timeout 30 "$BLUCTL" -C "$TV_MAC"          # connect (nudge)
      ;;
    tv_off)
      timeout 30 "$BLUCTL" -D                     # disconnect all -> frees DAC
      timeout 60 "$MOODEUTL" -Ro --bluetooth off
      ;;
    airplay_kick) timeout 60 "$MOODEUTL" -R --airplay ;;   # drop idle session, stay discoverable
    airplay_on)   timeout 60 "$MOODEUTL" -Ro --airplay on ;;
    airplay_off)  timeout 60 "$MOODEUTL" -Ro --airplay off ;;
    bt_on)        timeout 60 "$MOODEUTL" -Ro --bluetooth on ;;
    bt_off)       timeout 60 "$MOODEUTL" -Ro --bluetooth off ;;
    *) logger -t moode-mqtt-bridge "Unknown command: $1" ;;
  esac
}

state_loop &
mosquitto_sub "${MQTT_OPTS[@]}" -t "$CMD_TOPIC" | while read -r payload; do
  do_cmd "$payload"
done
