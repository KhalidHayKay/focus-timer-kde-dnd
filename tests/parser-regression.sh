#!/usr/bin/env bash
# Offline regression for the tolerant Until-parser (Fix A).
# The manual_state() function is extracted verbatim from the draft scripts and
# run against crafted config files. Nothing here touches the real system state:
# the config files live in a scratch directory and only one case reads the
# live file read-only.
set -uo pipefail

DRAFT_DIR=/tmp/opencode/p1
WORK=/tmp/opencode/t-fix/work
rm -rf "$WORK"; mkdir -p "$WORK"

fails=0; total=0

# expect <script> <until-value> <expected> <label>
expect() {
    local script="$1" until="$2" want="$3" label="$4"
    local cfg="$WORK/cfg" got
    rm -rf "$cfg"; mkdir -p "$cfg"
    if [ "$until" != "__NO_UNTIL_LINE__" ]; then
        {
            echo "[DoNotDisturb]"
            echo "NotificationSoundsMuted=true"
            echo "Until=$until"
        } >"$cfg/plasmanotifyrc"
    else
        printf '[DoNotDisturb]\nNotificationSoundsMuted=true\n' >"$cfg/plasmanotifyrc"
    fi
    total=$((total + 1))
    got=$(
        CONFIG="$cfg/plasmanotifyrc"
        eval "$(sed -n '/^# manual DND flag/,/^}/p' "$script")"
        manual_state
    )
    if [ "$got" = "$want" ]; then
        printf '  PASS  %-14s %-34s -> %s\n' "$(basename "$script")" "$label" "$got"
    else
        printf '  FAIL  %-14s %-34s -> %s (expected %s)\n' "$(basename "$script")" "$label" "$got" "$want"
        fails=$((fails + 1))
    fi
}

echo "=== A) Fix A: tolerant timestamp parser (both drafts) ==="
for s in "$DRAFT_DIR/focus-dnd-on" "$DRAFT_DIR/focus-dnd-off"; do
    expect "$s" '2027,10,21,16,59,0.101'      on  'live value (1-digit seconds)'
    expect "$s" '2027,10,21,16,59,00.101'     on  '2-digit seconds'
    expect "$s" '2027,10,21,16,55,36.456'     on  '2-digit seconds + millis'
    expect "$s" '2027,10,21,16,59,0'          on  '1-digit seconds, no millis'
    expect "$s" '2027,10,21,16,9,5.1'         on  '1-digit minute+second'
    expect "$s" '2027,10,21,6,7,8.9'          on  '1-digit hour+minute+second'
    expect "$s" '2027,10,21,16,59,59.999'     on  '2-digit seconds + millis'
    expect "$s" '2027,10,21,16,59,00.101,123' on  '7 fields (separate millis)'
    expect "$s" '@Invalid()'                  off 'invalid marker'
    expect "$s" '__NO_UNTIL_LINE__'           off 'no Until line'
    expect "$s" '2020,01,01,0,0,0'            off 'timestamp in the past'
    expect "$s" 'not-a-timestamp'             unknown 'malformed value'
    expect "$s" '2027,13,45,99,99,99'         unknown 'out-of-range fields'
    expect "$s" '2027,10,21,16,59,0.abc'      unknown 'malformed fraction'
    expect "$s" '2027,10,21,16,59'            unknown 'too few fields'
done

echo
echo "=== B) missing config file -> unknown ==="
for s in "$DRAFT_DIR/focus-dnd-on" "$DRAFT_DIR/focus-dnd-off"; do
    total=$((total + 1))
    got=$(
        CONFIG="$WORK/does-not-exist"
        eval "$(sed -n '/^# manual DND flag/,/^}/p' "$s")"
        manual_state
    )
    if [ "$got" = "unknown" ]; then
        printf '  PASS  %-14s %-34s -> %s\n' "$(basename "$s")" 'missing file' "$got"
    else
        printf '  FAIL  %-14s %-34s -> %s (expected unknown)\n' "$(basename "$s")" 'missing file' "$got"
        fails=$((fails + 1))
    fi
done

echo
echo "=== C) the LIVE ~/.config/plasmanotifyrc (read-only) ==="
for s in "$DRAFT_DIR/focus-dnd-on" "$DRAFT_DIR/focus-dnd-off"; do
    total=$((total + 1))
    got=$(
        CONFIG=/home/haykay/.config/plasmanotifyrc
        eval "$(sed -n '/^# manual DND flag/,/^}/p' "$s")"
        manual_state
    )
    if [ "$got" = "on" ]; then
        printf '  PASS  %-14s %-34s -> %s\n' "$(basename "$s")" 'live file' "$got"
    else
        printf '  FAIL  %-14s %-34s -> %s (expected on)\n' "$(basename "$s")" 'live file' "$got"
        fails=$((fails + 1))
    fi
done

echo
echo "=== D) the OLD (installed) parser on the same live value, for contrast ==="
old=$(printf '%s' '2027,10,21,16,59,0.101' | sed -E 's/^([0-9]{4}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2}),([0-9]{2})(\.[0-9]+)?$/\1-\2-\3 \4:\5:\6\7/')
date -d "$old" +%s >/dev/null 2>&1 && old="on" || old="unknown"
echo "  old parser -> $old (this is the 16:59:01 failure)"

echo
echo "=== summary: $((total - fails))/$total passed, $fails failed ==="
exit $((fails > 0))
