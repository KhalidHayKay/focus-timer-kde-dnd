#!/usr/bin/env bash
# t1-run.sh - drive the Focus Timer through work -> pause -> resume -> stop
# and report the DND state after every step.
# The DND must stay exactly as it was: the user's own DND is never touched.
set -uo pipefail

REAL=/home/haykay/.config/plasmanotifyrc
HASH_BEFORE=$(sha256sum "$REAL" | cut -d' ' -f1)
LOG=/home/haykay/.local/state/focus-dnd/focus-dnd.log

say() { printf '\n=== %s\n' "$*"; }
dnd() {
    printf '    DND manual flag : %s\n' "$(awk '/^\[DoNotDisturb\]/{f=1;next} /^\[/{f=0} f && /^Until/{sub(/^Until[[:space:]]*=/,""); print; exit}' "$REAL")"
    printf '    DND composite   : %s\n' "$(qdbus6 org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications.Inhibited 2>/dev/null)"
    printf '    DND config hash : %s\n' "$(sha256sum "$REAL" | cut -d' ' -f1)"
}
appstate() {
    printf '    app state       : %s  running=%s\n' \
        "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method org.freedesktop.DBus.Properties.Get io.github.focustimerhq.FocusTimer.Session CurrentState 2>/dev/null | tr -d "<'>")" \
        "$(gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method io.github.focustimerhq.FocusTimer.Timer.IsRunning 2>/dev/null)"
}
svcstate() {
    printf '    service state   : %s\n' "$(gdbus call --session --dest io.github.haykay.FocusDND --object-path /io/github/haykay/FocusDND --method io.github.haykay.FocusDND.GetState 2>/dev/null)"
}
timer() { gdbus call --session --dest io.github.focustimerhq.FocusTimer --object-path /io/github/focustimerhq/FocusTimer --method "io.github.focustimerhq.FocusTimer.Timer.$1" 2>&1; }
logsince() { sed -n "/$1/,\$p" "$LOG" 2>/dev/null | tail -n "${2:-8}"; }

say "baseline"
dnd; appstate; svcstate
echo "    hash at start   : $HASH_BEFORE"

say "step 1: start the pomodoro (work begins)"
timer Start
sleep 3
dnd; appstate; svcstate

say "step 2: pause"
timer Pause
sleep 3
dnd; appstate; svcstate

say "step 3: resume"
timer Resume
sleep 3
dnd; appstate; svcstate

say "step 4: stop"
timer Stop
sleep 3
dnd; appstate; svcstate

say "service log (this run)"
logsince "focus-dnd-service: started" 40

say "result"
HASH_AFTER=$(sha256sum "$REAL" | cut -d' ' -f1)
if [ "$HASH_BEFORE" = "$HASH_AFTER" ]; then
    echo "    the DND configuration was NOT modified (hash unchanged)"
else
    echo "    WARNING: the DND configuration changed"
    echo "    before: $HASH_BEFORE"
    echo "    after : $HASH_AFTER"
fi
