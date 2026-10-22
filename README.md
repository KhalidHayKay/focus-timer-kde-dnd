# Focus Timer ↔ KDE Plasma Do Not Disturb

A host-side bridge that automatically enables KDE Plasma's manual Do Not Disturb (DND) while [Focus Timer](https://github.com/focustimerhq/focustimer) is running a focus/pomodoro session, and restores the previous state when you take a break or stop. It works with the Focus Timer Flatpak with **no extra Flatpak permissions** required (Option A′).

> **Note:** This is a community integration, not an official Focus Timer or KDE component. The original maintainers have not necessarily reviewed or endorsed it.

## What it does

- Observes Focus Timer's D-Bus API on the session bus (`io.github.focustimerhq.FocusTimer`).
- Uses a host-side Python service (`focus-dnd-service`) to decide when work starts/ends.
- Delegates actuation to two small shell helpers (`focus-dnd-on`, `focus-dnd-off`) that enforce strict ownership rules.
- Integrates with KDE Plasma via the "toggle do not disturb" shortcut and Plasma's `plasmanotifyrc` manual DND flag.
- Tracks ownership so it never clears a DND that the user turned on manually.

## Supported environment

- Arch Linux (tested), with KDE Plasma 6.x
- Focus Timer installed as a Flatpak (tested with 1.1.5) or from source on the host session bus
- User session bus (D-Bus) and `systemctl --user`
- Required tools: `python3`, `PyGObject` (`python-gobject`), `qdbus6`/`qdbus`, `awk`, `date`, `flock`, `systemd` (user units)

## Architecture

```text
Focus Timer (Flatpak/host) ──D-Bus──► focus-dnd-service (Python)
                                           │
                                           ▼
                                    focus-dnd-on / focus-dnd-off
                                           │
                                           ├── reads/writes manual DND in ~/.config/plasmanotifyrc
                                           └── invokes Plasma shortcut to toggle DND
```

- **Service:** `bin/focus-dnd-service` — owns D-Bus name `io.github.haykay.FocusDND`, polls/subscribes to Focus Timer signals, enforces the policy and calls the helpers.
- **Helpers:** `bin/focus-dnd-on`, `bin/focus-dnd-off` — implement the safety rules (ownership, pre-session snapshot, composite-inhibition guard, tolerant parsing of KDE's timestamp format).
- **Unit:** `systemd/focus-dnd.service` — runs the service as a user service.

## Safety rules (preserved)

1. **Only the manual flag matters** — decisions are based on `[DoNotDisturb] Until` in `plasmanotifyrc`, never the composite `org.freedesktop.Notifications.Inhibited` property.
2. **Never touch a user DND** — if DND was on before the session, ownership is recorded as `pre=manual-on` and the automation will not claim ownership or turn it off.
3. **Ownership tracked** — only DND enabled by this automation is restored on pause/break/stop/completion.
4. **Respect external actions** — if the user turns DND off during a session we own, we release ownership and do not reassert it.
5. **Composite inhibition guard** — if another source inhibits notifications while manual DND is off, we refuse to enable/restore (to avoid toggling away that source).
6. **No blind toggles / unknown state** — unreadable/unknown state is not treated as safe to toggle; the helpers fail safely.
7. **Tolerant timestamp parsing** — KDE writes unpadded seconds (e.g. `0.101`); the parser accepts 1-2 digit fields.
8. **Idempotent and race-aware** — flocking, state pruning, no retry after unexpected verification failures.

## KDE limitation (important)

**Turning DND off via Plasma's shortcut can revoke application-level notification inhibition requests and fullscreen/mirrored-screen inhibition flags.** When this integration disables DND that *it owns*, Plasma's `revokeInhibitions()` may clear suppressions registered by other apps. The helpers log a disclosure when this happens. 

We cannot perfectly distinguish all inhibition sources from the available interfaces; the integration follows the rules above to minimize risk, but **other applications may need to reassert their inhibition requests** after an automation-owned DND is turned off by this bridge.

## Installation (Arch Linux)

### Prerequisites

```bash
sudo pacman -S python python-gobject dbus python-dbus qt6-tools  # qdbus6 usually via qt6-tools
```

(Adjust package names for your distro; `qdbus6` or `qdbus` is required.)

### Install

```bash
git clone https://github.com/KhalidHayKay/focus-timer-kde-dnd.git focus-timer-kde-dnd
cd focus-timer-kde-dnd
./install.sh
```

The installer will:
- Check for required commands (`python3`, `qdbus6`/`qdbus`, `flock`, `systemctl`)
- Install helpers to `~/.local/bin/`
- Install the user systemd unit to `~/.config/systemd/user/`
- Enable and start `focus-dnd.service`
- Explain changes before applying where practical

### Verify

```bash
systemctl --user status focus-dnd.service
qdbus6 io.github.haykay.FocusDND /io/github/haykay/FocusDND io.github.haykay.FocusDND.GetState
journalctl --user -u focus-dnd.service -n 20
```

## Usage

Just run Focus Timer and start a pomodoro/focus session. The service will enable DND during work and restore state on breaks/stops. If you have DND manually enabled before starting a session, the integration will leave it alone and will not turn it off.

## Updating

Pull the latest changes and re-run `./install.sh`. The installer is designed to be repeatable and safe.

## Uninstallation

```bash
./uninstall.sh
```

The uninstaller stops/disables only this project's service, removes only files it installed, preserves your config/logs/backups, and **never** toggles DND as part of uninstall.

## Troubleshooting

- **Service not starting:** Check `journalctl --user -u focus-dnd.service -n 50`
- **DND not toggling:** Ensure Focus Timer is running and on the session bus. Check `qdbus6 | grep focustimer`
- **DND left on unexpectedly:** Check ownership with `GetState()`; if not-owned it's treated as the user's DND
- **Permissions issues:** This integration needs no Flatpak permissions for Focus Timer

## Security / permissions

- Host-side only; no broad `org.freedesktop.Flatpak` talk permissions added
- Runs as your user service, writes only to `~/.config/plasmanotifyrc` (via Plasma shortcut) and `~/.local/state/focus-dnd/`
- No `sudo` required

## Tests

### Offline regression tests (safe, no desktop/DND changes)
```bash
cd tests
bash parser-regression.sh
bash decision-tests.sh
```

### Live integration tests (manual, opt-in only)
See `tests/focus-dnd/README.md`. These interact with the live Focus Timer, Plasma DND, and the running service. They must preserve and restore state; do not run them during packaging.

## License

MIT License. See [LICENSE](LICENSE). Copyright notices from the original implementation are preserved where present.

## Contributing / upstream

If you want to propose upstream integration to the Focus Timer project, see the prepared upstream message in `docs/UPSTREAM.md` (or in the project discussion). This is community-maintained and not officially endorsed.
