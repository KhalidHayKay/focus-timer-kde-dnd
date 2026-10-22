#!/usr/bin/env bash
# Offline regression for the tolerant Until-parser (Fix A).
# Uses scripts from the repository; no dependency on /tmp/opencode or /home/haykay.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRAFT_DIR="$REPO_ROOT/bin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0; total=0

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
    if [ "$got" = "want:$want" ]; then :; fi
    if [ "$got" = "$want" ]; then
        printf '  PASS  %-14s %-34s -> %s\n' "$(basename "$script")" "$label" "$got"
    else
        printf '  FAIL  %-14s %-34s -> %s (expected %s)\n' "$(basename "$script")" "$label" "$got" "$want"
        fails=$((fails + 1))
    fi
}

echo "=== A) Fix A: tolerant timestamp parser (repo scripts) ==="
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
echo "=== summary: $((total - fails))/$total passed, $fails failed ==="
exit $((fails > 0))
