#!/usr/bin/env bash
# Offline decision tests for the draft helper scripts.
#
# Safety: a stub "qdbus6" shadows the real one, so the DND toggle can never
# reach Plasma. The stub records every invocation and can simulate Plasma's
# config write (the value Plasma writes when DND is switched on).
# XDG_CONFIG_HOME / XDG_STATE_HOME are redirected into a scratch directory, so
# neither the real plasmanotifyrc nor the real state/log files are touched.
set -uo pipefail

DRAFT=/tmp/opencode/p1
WORK=/tmp/opencode/t-fix/decision
STUB=/tmp/opencode/t-fix/stub
rm -rf "$WORK"; mkdir -p "$WORK" "$STUB"

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

# run_case <label> <script> <record|-> <until> <inhibited> <until_after_toggle>
#            <expected_exit> <expected_outcome_substring> <expected_toggle:yes|no>
run_case() {
    local label="$1" script="$2" record="$3" until="$4" inhibited="$5" after="$6"
    local want_exit="$7" want_out="$8" want_toggle="$9"

    local case_dir="$WORK/case"
    rm -rf "$case_dir"; mkdir -p "$case_dir/config" "$case_dir/state"
    local cfg="$case_dir/config/plasmanotifyrc"
    { echo "[DoNotDisturb]"; echo "NotificationSoundsMuted=true"; echo "Until=$until"; } >"$cfg"
    mkdir -p "$case_dir/state/focus-dnd"
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

FUTURE='2027,10,21,16,59,0.101'      # the live value: unpadded seconds
FUTURE2='2027,10,21,16,59,30.500'     # padded seconds
PAST='2020,01,01,0,0,0'
PAST_PADDED='2020,01,01,10,00,30'   # parseable by the old parser too (all fields 2 digits)
BAD='not-a-timestamp'

echo "=== focus-dnd-off (draft) ==="
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
echo "=== focus-dnd-on (draft) ==="
run_case "manual=off -> toggle, then verify"       "$DRAFT/focus-dnd-on" "-"           "$PAST"    false "$FUTURE"  0 "enabled and recorded ownership"  yes
run_case "manual=on (user's) -> no action"          "$DRAFT/focus-dnd-on" "-"           "$FUTURE"  false "$PAST"    0 "already enabled by the user"      no
run_case "pre=manual-on -> decline (D1)"            "$DRAFT/focus-dnd-on" "pre=manual-on
owned=no"                 "$PAST"    false "$PAST"      0 "declined"                       no
run_case "flag unreadable -> refuse to toggle"      "$DRAFT/focus-dnd-on" "-"           "$BAD"     false "$PAST"    1 "refusing to toggle"              no
run_case "composite on, manual off -> refuse (D2)"  "$DRAFT/focus-dnd-on" "-"           "$PAST"    true  "$PAST"    1 "held by another source"          no
run_case "owned=yes, DND off -> release ownership"  "$DRAFT/focus-dnd-on" "pre=manual-off
owned=yes"                "$PAST"    false "$PAST"      0 "ownership released"              no

echo
echo "=== regression of the 16:59:00 incident (new parser vs installed parser) ==="
for variant in "draft:$DRAFT/focus-dnd-on" "installed:/home/haykay/.local/bin/focus-dnd-on"; do
    name="${variant%%:*}"; script="${variant#*:}"
    case_dir="$WORK/incident-$name"; rm -rf "$case_dir"; mkdir -p "$case_dir/config" "$case_dir/state"
    cfg="$case_dir/config/plasmanotifyrc"
    printf '[DoNotDisturb]\nNotificationSoundsMuted=true\nUntil=%s\n' "$PAST_PADDED" >"$cfg"
    out=$(PATH="$STUB:$PATH" XDG_CONFIG_HOME="$case_dir/config" XDG_STATE_HOME="$case_dir/state" \
          STUB_LOG="$case_dir/qdbus6.log" STUB_INHIBITED=false STUB_CONFIG="$cfg" \
          STUB_UNTIL_AFTER_TOGGLE="$FUTURE" bash "$script" 2>&1)
    rc=$?
    printf '  %-10s exit=%s | %s\n' "$name" "$rc" "$out"
done

echo
echo "=== summary: $((total - fails))/$total passed, $fails failed ==="
exit $((fails > 0))
