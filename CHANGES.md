# Change log — moOde Bluetooth + AirPlay integration

Date: 2026-09-27
Author: (you)

Environment:
- Home Assistant: `ghcr.io/home-assistant/home-assistant:stable` in Docker (Alpine 3.22)
- MQTT: `eclipse-mosquitto` in the same compose stack (no auth), port 1883
- Zigbee: Zigbee2MQTT, Third Reality "Projector Plug" with power monitoring
- moOde: Raspberry Pi audio player (10.x series)
- TV source: **onn. Streaming Device 4K Pro** (Google TV), added to HA via
  `androidtv_remote`, Bluetooth MAC `44:87:63:39:09:DE`

---

## Home Assistant changes

### `config/configuration.yaml`
Appended a top-level `mqtt:` block defining two binary sensors:

- `binary_sensor.moode_bluetooth`  <- `moode/bluetooth/state` (`connected`/`disconnected`, device_class connectivity)
- `binary_sensor.moode_airplay_active` <- `moode/airplay/active` (`on`/`off`)

### `config/automations.yaml`
Appended these automations:

| id | Alias | Trigger | Action |
|---|---|---|---|
| `1783000000001` | moOde - TV on - Bluetooth on and connect | plug power > 75 W for 5 s | MQTT `moode/cmd` = `tv_on` |
| `1783000000002` | moOde - TV off - Bluetooth disconnect and off | plug power < 20 W for 5 s | MQTT `moode/cmd` = `tv_off` |
| `1783000000003` | moOde - Kick idle AirPlay session after 20 min | `moode_airplay_active` off for 20 min | MQTT `moode/cmd` = `airplay_kick` |
| `1783000000006` | moOde - onn TV off - Bluetooth disconnect and off | onn `on` -> `off`/`standby` for 10 s | MQTT `moode/cmd` = `tv_off` |
| `1783000000007` | moOde - onn TV on - Bluetooth on and connect (projector powered) | onn -> `on` for 2 s **and** plug > 75 W | MQTT `moode/cmd` = `tv_on` |
| `1783000000008` | onn TV - Turn off when projector powered off | plug power < 20 W for 15 s | `media_player.turn_off` onn |
| `1783000000009` | onn TV - Turn on when projector powered on | plug power > 20 W for 5 s | `media_player.turn_on` onn |

Notes:
- Enabled the plug thresholds 75 W on / 20 W off based on real data
  (projector ~280 W when on, 0 W off; turn-on ramp crosses 75 W in ~5-10 s).
- No strict Bluetooth/AirPlay handshake is enforced: both renderers stay
  enabled; AirPlay is only kicked when idle.

### Backups (in `config/`)

```
configuration.yaml.bak-20260927-213523
automations.yaml.bak-20260927-213523
automations.yaml.bak-20260927-223118
automations.yaml.bak-20260927-223513
automations.yaml.bak-20260927-223719
automations.yaml.bak-20260927-224538
automations.yaml.bak-20260927-224706
automations.yaml.bak-20260927-225144
```

All edits were validated with
`docker exec homeassistant python -m homeassistant --script check_config -c /config`
(exit 0). `automations.yaml` ownership was left as `root:root`.

---

## moOde Pi changes

Delivered as the repo files in this folder (see `README.md`), installed by
`install.sh`:

- `/usr/local/bin/moode-mqtt-bridge.sh` — MQTT state publisher + command runner
- `/etc/moode-mqtt-bridge.conf` — holds `MQTT_HOST`, `TV_MAC`, etc.
- `/etc/systemd/system/moode-mqtt-bridge.service` — runs the bridge as root
- `/var/lib/...` — none; uses existing moOde tools
- Packages added: `mosquitto-clients`, `expect`, `sqlite3`
- `/etc/shairport-sync.conf` — `session_timeout` set to `1200` (was `60`)

### MQTT interface

State: `moode/bluetooth/state`, `moode/airplay/active`
Commands: `moode/cmd` = `tv_on` / `tv_off` / `airplay_kick` / `airplay_on` /
`airplay_off` / `bt_on` / `bt_off`

---

## Outstanding / assumptions

- Assumes the TV source is the onn device (`44:87:63:39:09:DE`) and the
  projector plug is `sensor.0xffffb40e0603ab7b_power`.
- Open question: is the onn powered from the projector's USB or its own
  adapter? If it stays `on` when the projector is off, the plug-based
  `…0002` is required for the disconnect; `…0006` alone won't fire.
- `…0001`/`…0002` (plug-based) and `…0006`/`…0007` (onn-based) overlap; they are
  idempotent. Consolidate if desired.
- moOde updates may overwrite `/etc/shairport-sync.conf`.
