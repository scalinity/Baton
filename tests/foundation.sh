#!/bin/sh
# Contract-2 behavior and fault tests. No provider process, build, or installed home is used.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/baton-foundation.XXXXXX")
T=$(cd "$T" && pwd -P)
trap 'test_status=$?; if [ "$test_status" -eq 0 ]; then rm -rf "$T"; else printf "Fixture preserved: %s\n" "$T" >&2; fi' EXIT
export BATON_HOME="$T/home" BATON_SHIM="$T/shim" BATON_TRANSCRIPTS="$T/transcripts" BATON_CLAUDE="$ROOT/tests/shim/claude" BATON_DATE=date BATON_DAEMON_LOG="$T/shim/daemon.log"
BATON=$ROOT/bin/baton
mkdir -p "$BATON_HOME/projects/Fixture" "$BATON_SHIM" "$BATON_TRANSCRIPTS"
printf '[]\n' > "$BATON_SHIM/rows.json"
: > "$BATON_SHIM/calls.log"
printf '%s\n' '{"models":{"opus":"opus","fable":"fable","sonnet":"sonnet","haiku":"haiku"},"cap":2,"claudeVersion":"2.1.268","trustedLocal":true}' > "$BATON_HOME/config.json"
cp -R "$ROOT/tests/project" "$T/Fixture"
sed 's/M02/M03/g' "$T/Fixture/docs/milestones/M02.md" > "$T/Fixture/docs/milestones/M03.md"
printf '#!/bin/sh\nexit 0\n' > "$T/Fixture/check.sh"
git -C "$T/Fixture" init -q -b main
git -C "$T/Fixture" add CLAUDE.md docs check.sh
git -C "$T/Fixture" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm fixture
jq -nc --arg p "$T/Fixture" '{path:$p,plan:"docs/MILESTONES.md",contract:2,check:["sh","check.sh"],checkReplaySafe:true}' > "$BATON_HOME/projects/Fixture/project.json"
printf '%s\n' '{"permissions":{"deny":["Bash(sudo:*)"]}}' > "$BATON_HOME/projects/Fixture/permissions.json"
. "$ROOT/tests/lib-load.sh"
count=0
ok() { count=$((count+1)); printf 'ok foundation %s\n' "$1"; }
expect_fail() { ef_label=$1; shift; if "$@" > "$T/failure.out" 2>&1; then echo "FAIL $ef_label unexpectedly succeeded" >&2; exit 1; fi; ok "$ef_label"; }
assert() { as_label=$1; shift; "$@" > "$T/assert.out" 2>&1 || { cat "$T/assert.out" >&2; echo "FAIL $as_label" >&2; exit 1; }; ok "$as_label"; }

base=$(git -C "$T/Fixture" rev-parse main)
sed 's/| M02 | The second | M01 | opus | high | | |/| M02 | The second | M01 | opus | high | | held |/' "$T/Fixture/docs/MILESTONES.md" > "$T/edited"
cp "$T/edited" "$T/Fixture/docs/MILESTONES.md"
plan=$(plan_of_project Fixture)
assert 'dispatch plan ignores uncommitted edits' sh -c 'printf "%s" "$1" | jq -e '\''.milestones[]|select(.id=="M02")|.status==""'\'' >/dev/null' sh "$plan"
git -C "$T/Fixture" restore docs/MILESTONES.md
sed 's/| M02 | The second | M01 |/| M02 | The second | M03 |/' "$T/Fixture/docs/MILESTONES.md" > "$T/cycle.md"
expect_fail 'cycles rejected' plan_tables "$T/cycle.md"
sed 's/| M02 | The second | M01 |/| M02 | The second | M999 |/' "$T/Fixture/docs/MILESTONES.md" > "$T/missing.md"
expect_fail 'missing dependencies rejected' plan_tables "$T/missing.md"
sed 's/| v0.1 ships | M04 |/| v0.1 ships | M404 |/' "$T/Fixture/docs/MILESTONES.md" > "$T/missing-gate.md"
expect_fail 'missing gate targets rejected' plan_tables "$T/missing-gate.md"
awk 'BEGIN {print "| ID | Depends on | Model | Effort | Remote | Status |\n|---|---|---|---|---|---|"; for(i=1;i<=32;i++) {d=(i==1?"–":(i==2?"M01":sprintf("M%02d, M%02d",i-1,i-2))); printf "| M%02d | %s | opus | | | |\n",i,d} print "\n| Gate | Holds | Cleared |\n|---|---|---|"}' > "$T/dag.md"
assert 'converging DAG validates without enumerating paths' plan_tables "$T/dag.md"
assert 'committed gate clearance alone is insufficient' sh -c 'printf "%s" "$1"|jq -e '\''.gates[]|select(.gate=="cleared gate")|.cleared==""'\'' >/dev/null' sh "$plan"
jq '.gateApprovals={"cleared gate":"D-003"}' "$BATON_HOME/projects/Fixture/project.json" > "$T/approved.json"
cp "$T/approved.json" "$BATON_HOME/projects/Fixture/project.json"
: > "$BATON_SHIM/agents.fail"
expect_fail 'provider failure is not an empty fleet' "$BATON" dispatch Fixture M02
"$BATON" status > "$T/status"
assert 'status exposes observation failure' grep -q unavailable "$T/status"
rm "$BATON_SHIM/agents.fail"
: > "$BATON_SHIM/agents.malformed"
expect_fail 'malformed fleet blocks dispatch' "$BATON" dispatch Fixture M02
rm "$BATON_SHIM/agents.malformed"
printf '%s\n' '[{"id":"live","sessionId":"live-session","pid":123,"name":"person"}]' > "$BATON_SHIM/rows.json"
expect_fail 'incomplete live row cannot bypass project exclusion' "$BATON" dispatch Fixture M02
printf '[]\n' > "$BATON_SHIM/rows.json"

# Kill the actual lock owner, then reacquire. The lock inode stays in place.
export TIMEOUT_LATE="$T/late-descendant"
cat > "$T/timeout-check.sh" <<'CHECK'
#!/bin/sh
sh -c 'sleep 4; touch "$TIMEOUT_LATE"' &
wait
CHECK
expect_fail 'bounded check terminates the whole process group' bounded_call 1 check sh "$T/timeout-check.sh"
sleep 3
assert 'timed-out descendant cannot write after the operation' test ! -e "$TIMEOUT_LATE"
cat > "$T/background-check.sh" <<'CHECK'
#!/bin/sh
sh -c 'sleep 4; touch "$TIMEOUT_LATE"' &
exit 0
CHECK
expect_fail 'successful parent cannot leave unchecked background work' bounded_call 5 check sh "$T/background-check.sh"
sleep 3
assert 'background check workers are terminated before verification' test ! -e "$TIMEOUT_LATE"
jq -nc --arg cwd "$T/Fixture/docs" '[{id:"hand",sessionId:"hand-session",pid:123,name:"hand",cwd:$cwd}]' > "$BATON_SHIM/rows.json"
expect_fail 'adoption rejects canonical subdirectories' "$BATON" adopt Fixture M02 hand-session
git -C "$T/Fixture" worktree add -q -b human-work "$T/unconventional" main
jq -nc --arg cwd "$T/unconventional" '[{id:"hand",sessionId:"hand-session",pid:123,name:"hand",cwd:$cwd}]' > "$BATON_SHIM/rows.json"
expect_fail 'live worktree identity is independent of its name' "$BATON" dispatch Fixture M02
printf '[]\n' > "$BATON_SHIM/rows.json"
sh -c '. "$1/lib/lock.sh"; lock_take; echo $$ > "$2/owner"; sleep 10 9>&-' sh "$ROOT" "$T" &
owner_wrapper=$!
while [ ! -f "$T/owner" ]; do sleep 0.01; done
expect_fail 'concurrent mutation refused' "$BATON" consume
assert 'status remains available during mutation' "$BATON" status
kill -KILL "$(cat "$T/owner")"
wait "$owner_wrapper" 2>/dev/null || true
assert 'dead lock owner does not strand the controller' "$BATON" consume
expect_fail 'journal refuses a caller without the mutation lock' log_event probe '' '' '' '' '{}'
( lock_take; log_event probe '' '' '' '' '{"event_id":"journal-replay"}'; log_event probe '' '' '' '' '{"event_id":"journal-replay"}' )
assert 'event replay has one durable identity' sh -c 'jq -se '\''[.[]|select(.event_id=="journal-replay")]|length==1'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
expect_fail 'conflicting event identity is rejected' sh -c 'ROOT=$1; . "$ROOT/tests/lib-load.sh"; lock_take; log_event probe "" "" "" "" '\''{"event_id":"journal-replay","different":true}'\''' sh "$ROOT"

"$BATON" dispatch Fixture M02 > "$T/dispatch.out"
run=$(jq -r 'select(.kind=="dispatch_prepared")|.run' "$BATON_HOME/log.jsonl")
session=$(jq -r 'select(.kind=="dispatch")|.session' "$BATON_HOME/log.jsonl")
assert 'dispatch has durable intent and acknowledgement' sh -c 'jq -se '\''map(.kind)|index("dispatch_prepared") < index("launch_started") and index("launch_started") < index("dispatch")'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
expect_fail 'second project run refused' "$BATON" dispatch Fixture M07

message() {
  jq -nc --arg run "$run" --arg session "$session" --arg p "$T/Fixture" --arg rev "$base" --arg id "$1" --arg outcome "$2" \
    '{baton:2,run:$run,session:$session,project:$p,milestone:"M02",plan_revision:$rev,message_id:$id,written_at:"2026-09-12T10:00:00Z",outcome:$outcome,question:"Choose the interface",options:["small","large"],reason:"unfinished",detail:"more work",merged_as:$rev}'
}
message false-complete complete > "$T/message.json"
expect_fail 'old ancestor cannot stand in for an integration receipt' artifact_check "$T/message.json"
for forbidden in eligible wait_for model prompt; do
  message forbidden asking | jq --arg key "$forbidden" '.[$key]=[]' > "$T/forbidden.json"
  expect_fail "handover cannot introduce $forbidden scheduling authority" artifact_check "$T/forbidden.json"
done
message bad-session asking | jq '.session="someone-else"' > "$T/message.json"
expect_fail 'unrelated session rejected' artifact_check "$T/message.json"
message ask-1 asking > "$T/message.json"
"$BATON" publish < "$T/message.json"
"$BATON" publish < "$T/message.json"
"$BATON" consume > "$T/consume.out"
"$BATON" publish < "$T/message.json"
"$BATON" consume >> "$T/consume.out"
assert 'repeat publication applies once' sh -c 'jq -se '\''[.[]|select(.message_id=="ask-1" and .kind=="consumed")]|length==1'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
assert 'asking consumption never stops a session' sh -c '! grep -q "claude stop" "$1"' sh "$BATON_SHIM/calls.log"
"$BATON" status > "$T/question-status"
assert 'consumed questions remain visible' grep -q 'Choose the interface' "$T/question-status"
fence=$(printf '\140\140\140baton\n'; cat "$T/message.json"; printf '\140\140\140\n')
jq -nc --arg s "$session" --arg m "$fence" '{session_id:$s,last_assistant_message:$m,stop_hook_active:false}' | BATON_RUN="$run" "$ROOT/hooks/stop-gate"
"$BATON" consume > "$T/fallback-replay"
assert 'printed fallback preserves consumed identity' sh -c 'jq -se '\''[.[]|select(.message_id=="ask-1" and .kind=="consumed")]|length==1'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
message ask-1 asking | jq '.question="DIFFERENT"' | "$BATON" publish
"$BATON" consume > "$T/collision.out"
assert 'conflicting message identity quarantined' grep -q conflicting-message-id "$T/collision.out"

# Fault at the decision append: claimed bytes survive, and replay resumes acknowledgement.
message fault-before-event asking | "$BATON" publish
set +e
( set -e; lock_take; log_event() { : > "$T/fault-reached"; return 91; }; inbox_consume ) > "$T/fault.out" 2>&1
fault_status=$?
set -e
assert 'fault boundary reached' test -f "$T/fault-reached"
assert 'failed event stops consumption' test "$fault_status" -ne 0
assert 'failed append leaves a claimed message' sh -c 'test "$(find "$1/processing" -name "*.json" | wc -l | tr -d " ")" -eq 1' sh "$BATON_HOME"
"$BATON" consume > "$T/replay.out"
assert 'replay repairs interrupted consumption' test -f "$BATON_HOME/archive/fault-before-event.json"

# Fault after event but before archive: replay deduplicates the event and finishes the move.
message fault-after-event asking > "$BATON_HOME/processing/after.json"
set +e
( set -e; lock_take; mv() { case "$2" in "$BATON_HOME/archive/"*) return 92;; *) command mv "$@";; esac; }; consume_claim "$BATON_HOME/processing/after.json" ) > "$T/fault-after.out" 2>&1
fault_status=$?
set -e
assert 'archive boundary failed after durable acknowledgement' sh -c 'jq -se '\''any(.[];.message_id=="fault-after-event" and .kind=="consumed")'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
"$BATON" consume > "$T/replay-after.out"
assert 'processing replay preserves the original payload' test -f "$BATON_HOME/archive/fault-after-event.json"
message claim-race asking | jq '.question="validated original"' > "$T/race-original"
"$BATON" publish < "$T/race-original"
mv "$BATON_HOME/inbox/claim-race.json" "$BATON_HOME/processing/race-claim.json"
message claim-race asking | jq '.question="replacement"' | "$BATON" publish
"$BATON" consume > "$T/race-result"
assert 'producer replacement cannot change claimed bytes' jq -e '.question=="validated original"' "$BATON_HOME/archive/claim-race.json"

"$BATON" claim "$run" > "$T/claim.out"
expect_fail 'human ownership blocks integration' "$BATON" integrate "$run"
"$BATON" release "$run" > "$T/release.out"
transcript=$BATON_TRANSCRIPTS/fixture/$session.jsonl
jq '.uuid="new-human-record"' "$transcript" > "$T/human-record"
cat "$T/human-record" >> "$transcript"
expect_fail 'same text under a new UUID does not release ownership' "$BATON" integrate "$run"
assert 'ownership refusal identifies human intervention' grep -q 'human intervention' "$T/failure.out"
"$BATON" release "$run" > "$T/release-new-boundary.out"

# Candidate has work and its own close-out evidence, all on its isolated branch.
wt=$T/Fixture-M02
printf 'implemented\n' > "$wt/work.txt"
sed 's/| M02 | The second | M01 | opus | high | | |/| M02 | The second | M01 | opus | high | | done |/' "$wt/docs/MILESTONES.md" > "$T/done-plan"
cp "$T/done-plan" "$wt/docs/MILESTONES.md"
awk '{print} /^## Completion evidence/ {print "\nImplemented and checked the fixture.\n"}' "$wt/docs/milestones/M02.md" > "$T/evidence"
cp "$T/evidence" "$wt/docs/milestones/M02.md"
printf '#!/bin/sh\nexit 7\n' > "$wt/check.sh"
git -C "$wt" add work.txt check.sh docs/MILESTONES.md docs/milestones/M02.md
git -C "$wt" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm candidate
mkdir -p "$T/git-hooks"
printf '#!/bin/sh\ntouch "%s"\n' "$T/implicit-hook-ran" > "$T/git-hooks/post-merge"
chmod +x "$T/git-hooks/post-merge"
git -C "$T/Fixture" config core.hooksPath "$T/git-hooks"
expect_fail 'failed standing check prevents main promotion' "$BATON" integrate "$run"
assert 'failed integration preserves main' test "$(git -C "$T/Fixture" rev-parse main)" = "$base"
printf '#!/bin/sh\nexit 0\n' > "$wt/check.sh"
git -C "$wt" add check.sh
git -C "$wt" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm 'repair candidate'
# Interrupt after main promotion but before its acknowledgement.
sed 's/^log_event()/original_log_event()/' "$ROOT/lib/log.sh" > "$T/original-log.sh"
set +e
( set -e; . "$T/original-log.sh"; log_event() { if [ "$1" = integrated ]; then return 93; else original_log_event "$@"; fi; }; lock_take; verb_integrate "$run" --retry ) > "$T/promote-fault.out" 2>&1
promotion_status=$?
set -e
assert 'promotion interruption reached an unacknowledged checked commit' sh -c 'jq -se '\''any(.[];.kind=="integration_checked") and (any(.[];.kind=="integrated")|not)'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
assert 'promotion used the exact checked commit' test "$(git -C "$T/Fixture" rev-parse main)" = "$(jq -r 'select(.kind=="integration_checked")|.integrated_commit' "$BATON_HOME/log.jsonl")"
printf 'human change after promotion\n' > "$T/Fixture/human.txt"
git -C "$T/Fixture" add human.txt
git -C "$T/Fixture" -c core.hooksPath=/dev/null -c commit.gpgsign=false commit -qm 'human advanced main'
advanced_main=$(git -C "$T/Fixture" rev-parse main)
"$BATON" integrate "$run" > "$T/integrate.out"
receipt=$(jq -r 'select(.kind=="integrated")|.integrated_commit' "$BATON_HOME/log.jsonl")
assert 'lost acknowledgement recovers after main advances' git -C "$T/Fixture" merge-base --is-ancestor "$receipt" main
assert 'reconciliation preserves subsequent human commits' test "$(git -C "$T/Fixture" rev-parse main)" = "$advanced_main"
assert 'integration preserves worker worktree' test -d "$wt"
assert 'integration does not implicitly execute project hooks' test ! -e "$T/implicit-hook-ran"
"$BATON" integrate "$run" > "$T/integrate-again.out"
assert 'integration replay writes one receipt' sh -c 'jq -se '\''[.[]|select(.kind=="integrated")]|length==1'\'' "$1" >/dev/null' sh "$BATON_HOME/log.jsonl"
message complete-1 complete | jq --arg sha "$receipt" '.merged_as=$sha' | "$BATON" publish
"$BATON" consume > "$T/complete.out"
assert 'verified completion closes the run' sh -c 'ROOT=$1; . "$ROOT/tests/lib-load.sh"; run_get "$2" | jq -e '\''.state=="complete"'\'' >/dev/null' sh "$ROOT" "$run"

# An acknowledged provider effect lost before journal acknowledgement is adopted, never relaunched.
jq 'map(.pid=null)' "$BATON_SHIM/rows.json" > "$T/dead-rows"
cp "$T/dead-rows" "$BATON_SHIM/rows.json"
set +e
( set -e; lock_take; dispatch_ack() { return 94; }; verb_dispatch Fixture M03 ) > "$T/launch-fault.out" 2>&1
launch_status=$?
set -e
assert 'launch interruption reserves a run' sh -c 'ROOT=$1; . "$ROOT/tests/lib-load.sh"; run_open|jq -e '\''any(.[];.state=="uncertain")'\'' >/dev/null' sh "$ROOT"
launches_before=$(cat "$BATON_SHIM/bg.count")
"$BATON" reconcile > "$T/reconciled.out"
assert 'reconciliation does not repeat launch' test "$(cat "$BATON_SHIM/bg.count")" = "$launches_before"
assert 'reconciliation restores acknowledged run identity' sh -c 'ROOT=$1; . "$ROOT/tests/lib-load.sh"; run_open|jq -e '\''all(.[];.state=="active")'\'' >/dev/null' sh "$ROOT"

# Recovery budget spans attempts and only verified progress can reset it.
old_home=$BATON_HOME
BATON_HOME=$T/ladder; export BATON_HOME
mkdir -p "$BATON_HOME"
cat > "$BATON_HOME/log.jsonl" <<'EVENTS'
{"at":"2026-09-12T10:00:00Z","kind":"dispatch","project":"P","milestone":"M01","attempt":1}
{"at":"2026-09-12T10:01:00Z","kind":"consumed","project":"P","milestone":"M01","attempt":1,"reason":"no-handover"}
{"at":"2026-09-12T10:02:00Z","kind":"consumed","project":"P","milestone":"M01","attempt":1,"reason":"no-handover"}
{"at":"2026-09-12T10:03:00Z","kind":"dispatch","project":"P","milestone":"M01","attempt":2}
{"at":"2026-09-12T10:04:00Z","kind":"consumed","project":"P","milestone":"M01","attempt":2,"reason":"no-handover"}
EVENTS
derive_ladder P M01 2 > "$T/ladder-result"
assert 'redispatch does not reset recovery budget' jq -e '.next=="escalate"' "$T/ladder-result"
BATON_HOME=$old_home; export BATON_HOME

# Atomic install into a separate home: repeat selection, keep first release immutable.
BATON_HOME="$T/install" sh "$ROOT/install.sh" > "$T/install.out"
first_release=$(readlink "$T/install/current")
BATON_HOME="$T/install" sh "$ROOT/install.sh" >> "$T/install.out"
assert 'repeat install selects the same immutable release' test "$(readlink "$T/install/current")" = "$first_release"
assert 'new installation does not assume trusted execution consent' jq -e '.trustedLocal==false' "$T/install/config.json"
printf '%s foundation checks passed\n' "$count"
