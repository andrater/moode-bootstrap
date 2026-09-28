# moOde Bluetooth + AirPlay bridge

Keeps a moOde (Raspberry Pi) audio box from being held hostage by a stale
Bluetooth connection, and lets Home Assistant drive Bluetooth / AirPlay on it
over MQTT.

## Problem it solves

A TV / Google TV streaming device connects to moOde as a Bluetooth speaker
(A2DP sink on the Pi). When the TV powers off, BlueZ on the Pi can keep the
"connected" state, which holds the ALSA output and blocks AirPlay. This bridge:

- **TV off** -> disconnect the stale Bluetooth link and stop the Bluetooth
  renderer, freeing the output for AirPlay.
- **TV on**  -> start the Bluetooth renderer and reconnect.
- **AirPlay idle** -> terminate an idle session (shairport-sync `session_timeout`)
  and, as a belt-and-braces, restart the session from HA after 20 min.

## Architecture

```
TV / streaming device --Bluetooth(A2DP)--> moOde (sink) --> DAC
        ^                                                      
        | power draw                                           
   Smart plug --Zigbee--> Zigbee2MQTT --> Home Assistant
                                              |
                                    MQTT (Mosquitto)
                                              |
                          moode-mqtt-bridge.sh on the moOde Pi
                            - publishes moode/bluetooth/state
                            - publishes moode/airplay/active
                            - runs blu-control.sh / moodeutl on command
```

HA decides *when*; the Pi executes *what*. No SSH from HA needed.

## Repository layout

```
moode-bt-airplay/
├── install.sh                       # interactive installer (run on the Pi)
├── uninstall.sh
├── moode-mqtt-bridge.sh             # the bridge (installed to /usr/local/bin)
├── moode-mqtt-bridge.service        # systemd unit
├── moode-mqtt-bridge.conf.example   # config template (/etc/moode-mqtt-bridge.conf)
├── home-assistant/
│   ├── configuration.yaml.snippet   # MQTT binary sensors
│   └── automations.yaml.snippet     # the automations
├── README.md
└── CHANGES.md
```

## Install on a fresh moOde system

Copy this folder to the Pi, then:

```bash
cd moode-bt-airplay
sudo ./install.sh
```

It prompts for:

1. **MQTT broker host** — the LAN IP of the machine running Mosquitto/HA.
2. **TV/streaming-device Bluetooth MAC** — find it with `bluetoothctl devices Paired`.
3. AirPlay idle timeout in seconds (default `1200` = 20 minutes).

It then installs `mosquitto-clients expect sqlite3`, installs the bridge and
systemd unit, writes the config, sets the shairport-sync `session_timeout`, and
starts the service.

Non-interactive:

```bash
sudo MQTT_HOST=192.168.1.200 TV_MAC=44:87:63:39:09:DE ./install.sh
```

## Configuration

`/etc/moode-mqtt-bridge.conf`:

| Key | Required | Default | Meaning |
|---|---|---|---|
| `MQTT_HOST` | yes | — | broker host/IP |
| `TV_MAC` | yes | — | paired device to watch/connect |
| `MQTT_PORT` | no | `1883` | broker port |
| `MQTT_USER` / `MQTT_PASS` | no | — | broker credentials |
| `STATE_TOPIC` | no | `moode/bluetooth/state` | link state |
| `APL_TOPIC` | no | `moode/airplay/active` | AirPlay active |
| `CMD_TOPIC` | no | `moode/cmd` | command topic |
| `POLL_SECS` | no | `5` | poll interval |

After editing the config: `sudo systemctl restart moode-mqtt-bridge`.

## MQTT interface

State (retained):

- `moode/bluetooth/state` = `connected` | `disconnected`
- `moode/airplay/active`  = `on` | `off`

Commands (publish to `moode/cmd`):

| Payload | Effect |
|---|---|
| `tv_on` | Bluetooth renderer on + connect to `TV_MAC` |
| `tv_off` | disconnect all + Bluetooth renderer off |
| `airplay_kick` | restart AirPlay renderer (drops idle session, stays discoverable) |
| `airplay_on` / `airplay_off` | AirPlay renderer on/off |
| `bt_on` / `bt_off` | Bluetooth renderer on/off |

Test from HA: Developer Tools -> Actions -> `mqtt.publish`
(`data: {topic: moode/cmd, payload: tv_off}`), or from the Pi:

```bash
mosquitto_pub -h <MQTT_HOST> -t moode/cmd -m tv_off
```

## Verify

```bash
systemctl status moode-mqtt-bridge --no-pager
journalctl -u moode-mqtt-bridge -f
bluetoothctl info 44:87:63:39:09:DE | grep Connected
```

## Home Assistant side

Append `home-assistant/configuration.yaml.snippet` to `config/configuration.yaml`
and `home-assistant/automations.yaml.snippet` to `config/automations.yaml`, then
reload/restart. The snippets assume these entity IDs (change as needed):

- `sensor.0xffffb40e0603ab7b_power` — projector smart plug power (W)
- `media_player.onn_streaming_device_4k_pro` — the Google TV source

## Uninstall

```bash
sudo ./uninstall.sh            # keep config
sudo ./uninstall.sh --purge    # remove config too
```

## moOde facts this relies on

- Renderer on/off: `moodeutl -Ro --bluetooth|--airplay on|off`
  (there is **no** `moodeutl --renderer` flag).
- Restart renderer: `moodeutl -R --airplay`.
- Bluetooth control: `/var/www/util/blu-control.sh -C <MAC>` (connect),
  `-D` (disconnect all), `-c` (list connected).
- AirPlay activity flag: `cfg_system.aplactive` in `/var/local/www/db/moode-sqlite3.db`.
- AirPlay idle: `session_timeout` in `/etc/shairport-sync.conf`
  (moOde default `60`; set `1200` for 20 min).
- `blu-control.sh -C` uses `expect` and can block, so calls are wrapped in `timeout`.

## Caveats

- A moOde software update may overwrite `/etc/shairport-sync.conf`
  (re-check `session_timeout` after updates).
- `session_timeout` fires when the source *disappears*; a paused-but-connected
  sender may keep the session. The HA 20-min `airplay_kick` automation covers that.
- Running `moodeutl -Ro ... on` when already on, or `-D` when nothing is
  connected, is harmless.
- Bluetooth on the Pi is what matters for freeing the DAC; the TV's own view can
  disagree (that mismatch is the original bug).
