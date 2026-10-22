#!/usr/bin/env bash
# t2-run.sh - verify the real DND actuation path.
#   baseline (DND off) -> work: DND on -> pause: DND off -> resume: DND on
#   -> stop: DND off -> restore the user's DND (on).
# The user's DND is restored in an EXIT trap, whatever happens.
set -uo pipefail

REAL=/home/haykay/.config/plasmanotifyrc
LOG=/home/haykay/.local/state/focus-dnd/focus-dnd.log
RESTORE_DONE=0

manual() { awk '/^\[DoNotDisturb\]/{f=1;next} /^\[/{f=0} f && /^Until/{sub(/^Until[[:space:]]*=/,""); print; exit}' "$REAL"; }
composite() { qdbus6 org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.Inhibited 2>/dev/null; }
is_on() { local u; u=$(manual); case "$u" in @*|"") return 1;; esac; local iso until_s now; iso=$(printf '%s' "$u" | sed -E 's/^([0-9]{4}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2})(\.[0-9]+)?$/\1-\2-\3 \4:\5:\6\7/'); until_s=$(date -d "$iso" +%s 2>/dev/null) || return 1; now=$(date +%s); [ "$until_s" -gt "$now" ]; }
toggle() { qdbus6 org.kde.kglobalaccel /component/plasmashell invokeShortcut "toggle do not disturb" >/dev/null 2>&1; }
timer() { gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method "io.github.focustimerhq.FocusTimer.Timer.$1" >/dev/null 2>&1; }
svc() { gdbus call --session --dest io.github.haykay.FocusDND --object-path /io/github/haykay/FocusDND --method io.github.haykay.FocusDND.GetState 2>/dev/null; }
owner() { cat /home/haykay/.local/state/focus-dnd/owner 2>/dev/null | tr '\n' ' '; }

restore() {
    [ "$RESTORE_DONE" = "1" ] && return 0
    RESTORE_DONE=1
    if is_on; then
        echo "    [restore] the DND is already on - nothing to do"
        return 0
    fi
    if [ "$(composite)" != "false" ]; then
        echo "    [restore] WARNING: the composite DND is on while the manual flag is off."
        echo "    [restore] Plasma's toggle would revoke the other source instead of enabling"
        echo "    [restore] the manual DND - leaving it to you (see the report)."
        return 1
    fi
    echo "    [restore] turning the DND back on through Plasma's normal path"
    toggle
    sleep 1.5
    if is_on; then echo "    [restore] the DND is on again"; else echo "    [restore] FAILED to turn the DND back on"; fi
}
trap restore EXIT

report() {  # label expected_on
    local label="$1" expect="$2" m c got
    if is_on; then got=on; else got=off; fi
    m=$(manual); c=$(composite)
    if [ "$got" = "$expect" ]; then
        printf '    %-28s DND=%-3s (expected %-3s) OK   composite=%s until=%s\n' "$label" "$got" "$expect" "$c" "$m"
    else
        printf '    %-28s DND=%-3s (expected %-3s) FAIL composite=%s until=%s\n' "$label" "$got" "$expect" "$c" "$m"
    fi
    printf '      app: state=%s running=%s | owner: %s\n' \
        "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method org.freedesktop.DBus.Properties.Get io.github.focustimerhq.FocusTimer.Session CurrentState 2>/dev/null | tr -d "<'>")" \
        "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method io.github.focustimerhq.FocusTimer.Timer.IsRunning 2>/dev/null)" \
        "$(owner)"
}

echo "=== T2: the real actuation path ==="
echo "--- step 0: turn the DND off (the user's own DND, manually, via Plasma)"
toggle; sleep 2
report "baseline (DND off)" off
printf '    service: %s\n' "$(svc)"

echo "--- step 1: start the pomodoro -> the DND must come ON"
timer Start; sleep 5
report "work started" on
printf '    service: %s\n' "$(svc)"

echo "--- step 2: pause -> the DND must go OFF again"
timer Pause; sleep 5
report "paused" off
printf '    service: %s\n' "$(svc)"

echo "--- step 3: resume -> the DND must come ON again"
timer Resume; sleep 5
report "resumed" on
printf '    service: %s\n' "$(svc)"

echo "--- step 4: stop -> the DND must go OFF"
timer Stop; sleep 5
report "stopped" off
printf '    service: %s\n' "$(svc)"

echo "--- restoring the user's DND"
restore
trap - EXIT
report "after the restore" on

echo
echo "=== the service log of this run ==="
tail -n 40 "$LOG"
