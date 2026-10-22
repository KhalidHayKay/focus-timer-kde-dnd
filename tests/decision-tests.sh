#!/usr/bin/env bash
# Offline decision tests for the helper scripts.
# Uses scripts from the repository; all paths are relative or temporary.
# No real DND toggles. Uses stubbed qdbus6.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRAFT="$REPO_ROOT/bin"
STUB="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$STUB"' EXIT

cat >"$STUB/qdbus6" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >>"${STUB_LOG:-/dev/null}"
case "$*" in
    *Inhibited*) printf '%s\n' "${STUB_INHIBITED:-false}"; exit 0;;
    *"toggle do not disturb"*)
        if [ -n "${STUB_CONFIG:-}" ]; then
            printf '[DoNotDisturb]\nNotificationSoundsMuted=true\nUntil=%s\n' \
                "${STUB_UNTIL_AFTER_TOGGLE:-2027,10,21,16,59,0.101}" >"$STUB_CONFIG"
        fi
        exit 0;;
    *) exit 0;;
esac
STUBEOF
chmod +x "$STUB/qdbus6"

fails=0; total=0

run_case() {
    local label="$1" script="$2" record="$3" until="$4" inhibited="$5" after="$6"
    local want_exit="$7" want_out="$8" want_toggle="$9"

    local case_dir="$WORK/case"
    rm -rf "$case_dir"; mkdir -p "$case_dir/config" "$case_dir/state/focus-dnd"
    local cfg="$case_dir/config/plasmanotifyrc"
    { echo "[DoNotDisturb]"; echo "NotificationSoundsMuted=true"; echo "Until=$until"; } >"$cfg"
    if [ "$record" != "-" ]; then
        printf '%s\n' "$record" >"$case_dir/state/focus-dnd/owner"
    fi

    local stub_log="$case_dir/qdbus6.log"
    : >"$stub_log"

    local out rc
    out=$(PATH="$STUB:$PATH" \
          XDG_CONFIG_HOME="$case_dir/config" \
          XDG_STATE_HOME="$case_dir/state" \
          STUB_LOG="$stub_log" \
          STUB_INHIBITED="$inhibited" \
          STUB_CONFIG="$cfg" \
          STUB_UNTIL_AFTER_TOGGLE="$after" \
          bash "$script" 2>&1)
    rc=$?

    local toggled=no
    grep -q "toggle do not disturb" "$stub_log" && toggled=yes

    total=$((total + 1))
    local problems=""
    [ "$rc" = "$want_exit" ] || problems="exit=$rc(want $want_exit)"
    case "$out" in *"$want_out"*) ;; *) problems="$problems; outcome mismatch";; esac
    [ "$toggled" = "$want_toggle" ] || problems="$problems; toggle=$toggled(want $want_toggle)"

    if [ -z "$problems" ]; then
        printf '  PASS  %-52s exit=%s toggle=%-3s | %s\n' "$label" "$rc" "$toggled" "$out"
    else
        printf '  FAIL  %-52s %s\n          got: %s\n' "$label" "$problems" "$out"
        fails=$((fails + 1))
    fi
}

FUTURE='2027,10,21,16,59,0.101'
PAST='2020,01,01,0,0,0'
BAD='not-a-timestamp'

echo "=== focus-dnd-off (repo) ==="
run_case "owned=yes, DND on -> toggle, verify, release" "$DRAFT/focus-dnd-off" "pre=manual-off
owned=yes"                "$FUTURE"  false "$PAST"      0 "disabled and released ownership" yes
run_case "owned=no, flag unreadable -> no-op (C)"   "$DRAFT/focus-dnd-off" "pre=manual-off
owned=no"                 "$BAD"     false "$PAST"      0 "nothing to restore"              no
run_case "owned=yes, flag unreadable -> refuse (C)" "$DRAFT/focus-dnd-off" "pre=manual-off
owned=yes"                "$BAD"     false "$PAST"      1 "refusing to toggle"              no
run_case "owned=no, DND on (user's) -> keep it"     "$DRAFT/focus-dnd-off" "pre=manual-off
owned=no"                 "$FUTURE"  false "$PAST"      0 "nothing to restore"              no
run_case "owned=yes, DND already off -> release"    "$DRAFT/focus-dnd-off" "pre=manual-off
owned=yes"                "$PAST"    false "$PAST"      0 "already disabled - ownership released" no
run_case "owned=no, DND already off -> no action"   "$DRAFT/focus-dnd-off" "pre=manual-off
owned=no"                 "$PAST"    false "$PAST"      0 "already disabled - no action"     no
run_case "no record at all, DND on -> keep it"      "$DRAFT/focus-dnd-off" "-"           "$FUTURE"  false "$PAST"      0 "nothing to restore"              no

echo
echo "=== focus-dnd-on (repo) ==="
run_case "manual=off -> toggle, then verify"       "$DRAFT/focus-dnd-on" "-"           "$PAST"    false "$FUTURE"  0 "enabled and recorded ownership"  yes
run_case "manual=on (user's) -> no action"          "$DRAFT/focus-dnd-on" "-"           "$FUTURE"  false "$PAST"    0 "already enabled by the user"      no
run_case "pre=manual-on -> decline (D1)"            "$DRAFT/focus-dnd-on" "pre=manual-on
owned=no"                 "$PAST"    false "$PAST"      0 "declined"                       no
run_case "flag unreadable -> refuse to toggle"      "$DRAFT/focus-dnd-on" "-"           "$BAD"     false "$PAST"    1 "refusing to toggle"              no
run_case "composite on, manual off -> refuse (D2)"  "$DRAFT/focus-dnd-on" "-"           "$PAST"    true  "$PAST"    1 "held by another source"          no
run_case "owned=yes, DND off -> release ownership"  "$DRAFT/focus-dnd-on" "pre=manual-off
owned=yes"                "$PAST"    false "$PAST"      0 "ownership released"              no

echo
echo "=== summary: $((total - fails))/$total passed, $fails failed ==="
exit $((fails > 0))
