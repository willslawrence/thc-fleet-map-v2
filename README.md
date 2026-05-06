# THC Fleet Map

Real-time helicopter operations dashboard for THC. Live at
<https://willslawrence.github.io/thc-ops-map/>.

The site shows aircraft positions on an interactive Leaflet map, current
flight status, pilot currency (medical / REMS / competency), and a 12-month
mission timeline.

## Data flow

```
Obsidian vault (THC Vault)
  └── THC/Helicopters/*.md, Pilots/*.md, Missions/*.md, Flights Schedule.md
        │
        ▼
  generate.py  ──► substitutes generated regions in index.html
        │
        ▼
  fleetpush.sh / auto-update.sh  ──►  git push  ──►  GitHub Pages
```

`index.html` is **edited by hand** for layout / styling, but the generator
also rewrites a few delimited regions inside it (see `update()` in
`generate.py`):

- `const fleet = [...]`
- `<!-- FLIGHTS_START --> ... <!-- FLIGHTS_END -->`
- `<!-- CURRENCY_START --> ... <!-- CURRENCY_END -->`
- `<!-- TIMELINE_START --> ... <!-- TIMELINE_END -->`
- `<title>`, `<!-- LAST_UPDATED -->`, `<!-- REPORT_PERIOD -->`

So CSS / JS / structural HTML edits are safe to make directly in
`index.html`.

## Local setup

Requirements: Python 3.9+, git. No third-party Python packages.

The generator looks for the Obsidian vault in this order:

1. `$THC_VAULT` (if set)
2. `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/THC Vault`
3. `~/Library/Mobile Documents/com~apple~CloudDocs/THC Vault`

If none exist, `generate.py` exits with a message. Set `THC_VAULT` to
override:

```bash
export THC_VAULT="/path/to/THC Vault"
```

## Running manually

```bash
python3 generate.py        # regenerate index.html in place
./fleetpush.sh             # commit and push
# or, with extra logging / dry-run support:
./auto-update.sh           # generate + commit + push
./auto-update.sh --dry-run # generate + commit, no push
```

## Scheduled jobs (macOS launchd)

Three plists drive the schedule (Saudi Arabia time, GMT+3):

| Plist | Time | Action |
| --- | --- | --- |
| `com.thc.fleetmap.morning.plist` | 08:45 | Run `generate.py` |
| `com.thc.fleetmap.afternoon.plist` | 13:00 | Run `generate.py` |
| `com.thc.fleetmap.push.plist` | 08:50, 13:05 | `git add / commit / push` |

The plists hardcode `/Users/willlawrence/Desktop/Willy/FleetMapAndTimeline`.
If you move the repo, update them and reload:

```bash
launchctl unload ~/Library/LaunchAgents/com.thc.fleetmap.morning.plist
cp com.thc.fleetmap.morning.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.thc.fleetmap.morning.plist
```

To pass `THC_VAULT` to a plist, add it under `EnvironmentVariables`:

```xml
<key>EnvironmentVariables</key>
<dict>
  <key>THC_VAULT</key>
  <string>/path/to/THC Vault</string>
</dict>
```

## Files

- `generate.py` — main generator (reads vault, rewrites `index.html`).
- `generate_sandbox.py` — scratch / experimental copy, not run by launchd.
- `index.html` — the dashboard.
- `stadiums.html` — auxiliary page.
- `auto-update.sh` — generate + commit + push, with `--dry-run`.
- `fleetpush.sh` — minimal generate + commit + push.
- `com.thc.fleetmap.*.plist` — launchd schedules.
- `fleetpush.log` — local push log (gitignored).
