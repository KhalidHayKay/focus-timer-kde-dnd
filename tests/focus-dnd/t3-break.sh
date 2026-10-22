#!/usr/bin/env bash
# t3-break.sh - verify the pomodoro -> break transition with a 10 s pomodoro.
# The user's pomodoro duration and DND state are restored at the end.
set -uo pipefail

FT=io.github.focustimerhq.FocusTimer
REAL=/home/haykay/.config/plasmanotifyrc
RESTORE_DONE=0

manual() { awk '/^\[DoNotDisturb\]/{f=1;next} /^\[/{f=0} f && /^Until/{sub(/^Until[[:space:]]*=/,""); print; exit}' "$REAL"; }
composite() { qdbus6 org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.Inhibited 2>/dev/null; }
is_on() { local u; u=$(manual); case "$u" in @*|"") return 1;; esac; local iso until_s now; iso=$(printf '%s' "$u" | sed -E 's/^([0-9]{4}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2})(\.[0-9]+)?$/\1-\2-\3 \4:\5:\6\7/'); until_s=$(date -d "$iso" +%s 2>/dev/null) || return 1; now=$(date +%s); [ "$until_s" -gt "$now" ]; }
toggle() { qdbus6 org.kde.kglobalaccel /component/plasmashell invokeShortcut "toggle do not disturb" >/dev/null 2>&1; }
timer() { gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method "io.github.focustimerhq.FocusTimer.Timer.$1" >/dev/null 2>&1; }
appstate() { printf 'state=%s running=%s' \
    "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method org.freedesktop.DBus.Properties.Get io.github.focustimerhq.FocusTimer.Session CurrentState 2>/dev/null | tr -d "<'>")" \
    "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method io.github.focustimerhq.FocusTimer.Timer.IsRunning 2>/dev/null)"; }
setdur() { timeout 60 flatpak run --command=gsettings "$FT" set io.github.focustimerhq.FocusTimer pomodoro-duration "$1" 2>/dev/null; }

restore() {
    [ "$RESTORE_DONE" = "1" ] && return 0
    RESTORE_DONE=1
    echo "--- restoring the pomodoro duration (1800 s)"
    setdur 1800
    echo "    duration now: $(timeout 60 flatpak run --command=gsettings "$FT" get io.github.focustimerhq.FocusTimer pomodoro-duration 2>/dev/null)"
    if ! is_on; then
        if [ "$(composite)" = "false" ]; then
            echo "--- restoring the DND (on)"
            toggle; sleep 1.5
        fi
    fi
    if is_on; then echo "    the DND is on again"; else echo "    WARNING: the DND is not on"; fi
}
trap restore EXIT

echo "=== T3: the pomodoro -> break transition ==="
echo "--- temporarily set the pomodoro duration to 10 s"
setdur 10
sleep 1
echo "--- turn the DND off (baseline)"
toggle; sleep 2
printf '    baseline: DND=%s composite=%s %s\n' "$([ "$(composite)" = true ] && echo on || echo off)" "$(composite)" "$(appstate)"

echo "--- start the pomodoro -> the DND must come ON"
timer Start
sleep 4
printf '    running : DND=%s %s\n' "$([ "$(composite)" = true ] && echo on || echo off)" "$(appstate)"

echo "--- waiting for the pomodoro to end (10 s) and the break to begin"
sleep 14
printf '    after  : DND=%s %s\n' "$([ "$(composite)" = true ] && echo on || echo off)" "$(appstate)"
if [ "$(composite)" = "false" ]; then
    echo "    OK: the DND was released when the pomodoro ended"
else
    echo "    FAIL: the DND is still on after the pomodoro ended"
fi

echo "--- stop the session"
timer Stop; sleep 3
printf '    stopped: DND=%s %s\n' "$([ "$(composite)" = true ] && echo on || echo off)" "$(appstate)"

restore
trap - EXIT
echo
echo "=== the service log of this run ==="
tail -n 22 /home/haykay/.local/state/focus-dnd/focus-dnd.log
