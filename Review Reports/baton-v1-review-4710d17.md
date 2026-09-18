# Baton V1 — Merged Review Report

**Subject:** `/Users/danny/Documents/Apps/Baton` at `4710d17` · 6,038 lines · 246 scenarios
**Reviewers:** ten parallel, one per dimension, read-only
**Baseline:** `246 scenarios, 0 failed` — run at the commit, before that night's uncommitted work appeared
**Relay:** `com.baton.tick` stood down and confirmed absent from `launchctl list`. No lock stranded by the bootout.
**Tally:** 22 findings — 4 blocking, 11 serious, 7 minor. Ten verified by the orchestrator against code or live state rather than taken on report.

---

## VERDICT

**V1 is sound in its spine and leaky at its edges: every invariant that matters for correctness-of-record is enforced by a real mechanism — the filesystem rename, the atomic `mkdir`, the ancestry check — while the rail that protects the tick's own executable set has never actually been installed, and four independent paths can put two live sessions on one lane or silently lose one.**

---

# 🔴 BLOCKING

## B1. The deny rail in force is missing D-048's protection entirely — every session Baton has ever dispatched ran without it
*(Dimension 10 · independently verified in full)*

`install.sh:52` writes the permissions file only when absent:

```sh
if [ ! -f "$BATON_HOME/projects/$project/permissions.json" ]; then
```

The live file is **11 Sep 09:32, 37 deny rules**; `main` would write **43**. `settings_compose` copies `.permissions.deny` verbatim into each dispatch, so the six missing rules never reach a session:

```
Bash(*com.baton.tick*)
Bash(*.baton/notify*)
Edit(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)
Write(//Users/danny/Library/LaunchAgents/com.baton.tick.plist)
Edit(//Users/danny/.baton/notify/**)
Write(//Users/danny/.baton/notify/**)
```

**All eleven composed files under `~/.baton/settings/` carry 37 rules and zero plist rules** — `Baton-M02` through `Baton-M07-d`, `Baton-M09`, `Baton-M17`, and `wake.json` (41, also zero). Nothing has drifted the other way.

The plist is the one file deciding *which code* launchd runs every sixty seconds with Full Disk Access. D-048 exists precisely to fence it. This is the "reachable **and later executed**" category, not "reachable and inert."

- **Why the suite misses it:** the four install scenarios run against a fresh `BATON_HOME` where the file is absent, so every test takes the `if [ ! -f ]` true-branch exactly once. The upgrade path — the only path production has taken since 11 Sep — has no scenario.
- **Fix:** write-and-compare as the `wake.json` block twelve lines below already does (`.tmp` + `cmp -s`), instead of write-once.

## B2. A `pid: null` listing turns the crash rule's remedy into a copy fork with nothing left to stop the original
*(Dimension 9 · mechanism verified)*

`rows_read`'s entire schema check (`lib/rows.sh:22`):

```sh
jq -ce 'if type == "array" then . else empty end'
```

No field validation. If a CLI upgrade or restarting service yields rows without pids, every open lane falls into `no_row`, two sightings confirm a "crash", and `ladder_step` resumes. But `job_of_session` filters on the same field (`lib/stops.sh:99`):

```sh
map(select(.sessionId == $s and .pid != null)) | first | .id // empty
```

It returns empty, `resume_session` skips both `claude stop` and `stop_settle`, the flagless resume meets a live session and forks a copy — and the fork's compensating stop is gated on that same empty job id (`lib/stops.sh:293-294`):

```sh
# Now the original, which the first stop did not take. It must not run beside its copy.
[ -z "$rs_job" ] || "$BATON_CLAUDE" stop "$rs_job" > /dev/null 2>&1 || true
```

**Silent double dispatch, every open lane, within two ticks.**

- **Why the suite misses it:** `tests/shim/claude:59` picks fork-versus-wake by `.pid != null` in the scenario's own `rows.json` — the very field the crash rule reads as death — so `crash-two-ticks` gets the canned wake string and asserts `delivered` with no `claude stop` in `calls.log`.
- **Fix:** refuse the rung when no job id is in the listing; have the fork's second stop find the job by session name.

## B3. A `dispatch-failed` park has no route out, and its own message tells the person to do the thing that will not free it
*(Dimension 5)*

Four of five stages (`worktree`, `settings`, `launch`, `service`) park a lane with **no session**, so no ruling can reach it — `ruling_target` returns nothing (`lib/escalate.sh:215`), and `lib/answer.sh:78-79` refuses. The only edit route compares plan rows and the brief, neither of which the actual fix touches. The person is told:

> `2 dispatches in a row produced no session, the last at the worktree stage: … Bring main into the branch yourself: git -C "…/Baton-M20" merge main · fix what the worktree stage names; the next tick dispatches again`

They run exactly that `git merge`. `edit_reread_check` sees no difference, the park stands, the lane stays filtered out of candidates (`lib/candidates.sh:272-273`), and `status` re-asserts *"the next tick dispatches again"* on every read. Nothing prints; nothing changes; the line is byte-identical the next morning.

- **Evidence:** `lib/tick.sh:202` — `escalate "$dt_project" "$dt_id" "" "" dispatch-failed lane "$dt_carries"` (session and attempt empty); `lib/escalate.sh:303-305` for the message; `lib/escalate.sh:34` lists `dispatch-failed` in `class_unparks_by_edit`, so the design asserts an edit frees it.
- **Why the suite misses it:** `tick-dispatch-fails-twice` stops at the park. `edit-unparks-no-session` looks like the release test but seeds `"plan_rows_sha256":"0000…0"`, a sentinel no real reading equals. No scenario fixes a dispatch stage and ticks.
- **Fix:** write a `resolution` when the condition lapses — a later successful dispatch for the pair — as `omitted` and `disagreement` already do through `clears`; or accept `baton answer <M> "retry"` as a hand-back. Until one exists, the verb must not promise a dispatch the park forbids.

## B4. A park is released by a session's act that the contract *requires*, and the redispatch message asserts an edit that never happened
*(Dimension 5 · verified)*

`reread_hashes` hashes the brief's copy-ready prompt read from `main` (`lib/escalate.sh:91`):

```sh
if rrh_text=$(prompt_from_brief "$rrh_path" "docs/milestones/$2.md" "Copy-ready session prompt" 2>/dev/null); then
  rrh_brief=$(printf '%s' "$rrh_text" | shasum -a 256 | awk '{ print $1 }')
```

`CONTRACT.md` clause 3(c) **mandates that every close-out session change exactly that text**:

> `(c) on main: refresh the prompt of every brief the handover will list (parts 1 and 3–7; part 4 additively, by thread)`

The sequence: M20 parks `model_not_found`. A parked milestone has blank `Status`, so it stays plan-eligible and the next lane's `complete` handover lists it — obliging that session to refresh M20's prompt. The next tick re-reads `brief_sha256`, sees it changed, writes `resolution … how: "edit"`, and `person_acted` returns `edit`. The lane redispatches (`lib/stops.sh:512-514`):

```sh
case "$(person_acted "$1" "$srn_m" model_not_found)" in
  edit)
    redispatch … "the Model cell was edited after the model was refused, so attempt $((srn_a + 1)) runs on it"
```

**No cell was touched.** The new session requests the same refused model, which per D-056 writes no artifact — the row reads `state: failed` carrying a live pid, the lane holds a cap slot, nothing is heard for `stallMinutes`. **It recurs on every peer close-out.** The same path restarts a `ladder-end` park that three failure endings earned.

- **Why the suite misses it:** no scenario changes a brief on `main` by any hand but a person's; `edit-unparks`, `edit-unparks-no-session` and `omitted-edit-dispatches` all seed their hashes directly.
- **Fix:** hash only what a decision about *this* park changes — normalise parts 1 and 3–7 out of the brief reading, or require the plan rows to change too before a brief change counts.

**Clean negative that came with it:** `reread_hashes` is content-hash throughout — `shasum -a 256` over parsed rows and over `git show main:`, with **zero `mtime`/`stat` references in the file**. A `touch`, an autosave, a formatter, or a rebase restoring identical bytes **cannot** free a park, and a change-and-revert correctly registers as no decision. D-060 narrowed the plan hash for this reason and left the brief half whole.

---

# 🟡 SERIOUS

## S1. `redispatch` never stops the session it replaces, and the automatic path has no live-row refusal at all
*(Dimension 4 · verified)*

The hand-run verb refuses (`lib/dispatch.sh:336-338`):

```sh
if printf '%s' "$vd_rows" | jq -e --arg n "$vd_name" 'any(.[]; .name == $n and .pid != null)' > /dev/null; then
  echo "baton: a live session named \"$vd_name\" already exists; nothing dispatched" >&2
  exit 2
```

`dispatch_one` contains no pid test anywhere in its body. `redispatch` checks a project park and a model hold, then calls `dispatch_try` directly. **A person is stopped from dispatching over a live row; the relay is not.**

Cost: one 0.35–0.8 GB idle process held for good per redispatch (D-087's measurement, the exact cost that decision exists to bound), a duplicate identically-named row in Claude.app and `claude agents --json`, invisibility to `baton status` (which prints only open lanes), and a Stop gate armed forever — `hooks/stop-gate:23-26` stands down only on an archived `complete` naming *that* session.

- The reviewer **corrected its own framing under questioning**: the outgoing session is idle, not working, so this is not "two sessions burning quota." It marked the two-sessions-one-worktree git question **not established** rather than reasoning it out.
- **Why the suite misses it:** every scenario reaching a redispatch ships `rows.json` as `[]` — `invalid-request-redispatch`, `unfinished-once`, `unfinished-twice`, `invalid-request-twice`, `blocked-done-redispatch`, `no-handover-ladder`, `crash-redispatch-no-transcript`, `ladder-end-edit`, `model-not-found-edit`.
- **Fix:** before `dispatch_try`, `redispatch` asks the rows for a job carrying the attempt's current session and stops it — the `job_of_session` + `stop_settle` pair `resume_session` already uses. REQ-STOP-10 already requires this before the crash rule acts.

## S2. The gap report goes silent exactly when the outage killed the lane
*(Dimension 2 · verified live during the review)*

`derive_gap` tests "a lane was open during the gap" from derivation 1's `in_flight` half, which requires a row with a pid (`lib/derive.sh:495`, excluding `lib/derive.sh:179`). A session that died in the outage sits in `no_row` and counts for nothing.

**Demonstrated live:** the row reading *"Baton was not running for 1 h 6 m"* was **gone** at 1 h 26 m — a longer outage — because M17 had lost its pid. `derive_in_flight` returned `"in_flight":[]`, `"no_row":[{…M17…}]`.

Worse: the first completed tick advances the marker, so the window closes permanently.

- **Why the suite misses it:** `derive-gap`'s rowless case is carried entirely by M07's `consumed` after the marker; `tick-no-rows` has a marker 60 s old, below two intervals, so `had_lane` is never consulted. No fixture pairs a stale marker with a rowless open lane.
- **Fix:** count the gap's open lanes from `lanes_open` including `no_row`, not from `in_flight`.

## S3. A lock whose `at` is missing or unparseable can never be broken and is never reported — the relay dies silently, forever
*(Dimension 7 · verified)*

`lock_take` is three steps: `mkdir` the directory, write `pid`, write `at`. An untrapped SIGTERM between steps two and three leaves a lock both rescue functions refuse to touch:

```sh
lb_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null) || return 0    # lock_stale_break, lib/tick.sh:43
ls_at=$(cat "$BATON_HOME/lock/at" 2>/dev/null) || return 0    # lock_stale_report, lib/tick.sh:20
```

Every later tick exits 75. No escalation, no Mac message, no gap report, no marker advance. The same state arrives with no kill at all if `baton_now` fails, leaving `at` holding a bare newline `iso_epoch` will not parse.

**`launchctl bootout` — which D-101 records as the supported way to stand the relay down — sends an untrapped SIGTERM.** It landed cleanly in this instance (no lock present when checked), but the window is real.

- **Why the suite misses it:** `tests/run.sh` does `rm -rf "$tmp/got/home/lock"` before diffing, so **lock contents are asserted in none of the 246 scenarios**. `tick-stale-lock` supplies a complete lock.
- **Fix:** in both functions, fall back to the lock directory's own modification time (`stat -f %m`) when `at` is absent or unparseable. Both stay reads; the break stays the rename.

**Answers to the lock questions:** (a) `lock_stale_break`'s rename yields **exactly one winner** — the loser's `mv` fails on a missing source and takes `|| return 0`, never believing it broke anything. (b) Staleness is **both** age- and pid-based, and the pid test is decisive (`lib/tick.sh:48`). (c) A merely-slow tick **cannot** have its lock broken while still writing.

## S4. One English sentence, three implementations: a ruling's refused resume shortens the ladder
*(Dimension 3 · verified)*

`lib/derive.sh:398` and `lib/stops.sh:315` both count this as a failure ending:

```
| select((.kind == "consumed" and .reason == "no-handover")
         or (.kind == "crash_sighting" and .sighting == 2)
         or (.kind == "resume" and .outcome == "refused"))
```

`lib/escalate.sh:119` writes the same sentence with `and .resume_kind != "ruling"`, reasoned at `escalate.sh:113` — *"A ruling's own resume that the CLI refused is not an ending: the session did not end, Baton failed to reach it."*

Two refused ruling deliveries plus one genuine `no-handover` reads as three failures, so `ladder_step` escalates `ladder-end` instead of taking the resume rung the ending earned — two of the three "failures" being the person's own rulings not reaching the session.

- **Why the suite misses it:** `derive-ladder`'s only refused resume is `resume_kind: "continue"`. `answer-resume-refused` produces exactly the bad state — two refused ruling resumes in its expected log, one per idempotence run — and asserts only that `status` still prints the park.
- **Decision conflict:** REQ-STOP-04 and `CONTEXT.md` both say "a session that cannot be resumed," which reads as every refused resume; D-061 settled the same question the other way for `person_acted`. **The asymmetry is the defect whichever way it resolves.**

## S5. `artifact_ids` splits on the first hyphen, mis-parsing Baton's own milestone ids
*(Dimension 6 · verified with live archive evidence)*

```sh
ai_base=$(basename "$1" .json); ai_base=${ai_base%.json.tmp}; ai_base=${ai_base%.tmp}
ai_milestone=${ai_base%%-*}      # lib/inbox.sh:90-92
ai_session=${ai_base#*-}
```

`M07-d-1d50e71b-…json` yields milestone `M07`, session `d-1d50e71b-…`. **Four real artifacts in `~/.baton/archive/` have this shape** (`M07-b`, `M07-c`, `M07-d`), and `parse_id` admits `^M[0-9]+(-[a-z0-9]+)?$`.

Fires only on the name-fallback paths (`.milestone // $m`), which is where it hurts:
- **(a)** A half-written `.tmp` fails `jq`, so the fallback fires; `ic_sid` becomes `d-<uuid>`, the live-session guard matches nothing, and the file is moved to `rejected/` **while the session writing it is alive** — its own `mv` then fails. `lib/inbox.sh:360-368` calls that loss "unrecoverable" and builds the `rows_ok` guard against it; the guard is bypassed for hyphenated ids.
- **(b)** Any `unparseable` or `missing-field` rejection files the event and the lane escalation under milestone `M07` — a different, already-done milestone — with a session id that resolves to nothing, so `rj_project` stays empty and `derive_parked`'s `select($p == "" or .project == $p)` hides the park from every per-project reader.

- **Why the suite misses it:** all four fixtures forcing the name fallback (`reject-unparseable`, `reject-missing-field`, `reject-orphan-tmp`, `consume-live-tmp`) name the milestone `M02`, which has no hyphen. `find tests/scenarios -path '*/inbox/*' | grep -cE '/M[0-9]+-[a-z]-'` → 0.
- **Fix:** recover the milestone as the longest prefix `parse_id` accepts, and refuse rather than guess when both ids cannot be recovered.

## S6. `edit_reread_check` iterates the old reading's keys, so a brief absent at park time can never unpark the lane
*(Dimension 5 · verified — and fixed in the working tree during the review)*

The park exists *because* the brief was not on `main`; committing it, the named fix, frees nothing. Staged at 00:07 that night:

```diff
-      [ $was | keys[] | select(($now[.] // null) != null and $now[.] != $was[.]) ]')
+      [ $now | keys[] as $key
+        | select(($was | has($key) | not) or $now[$key] != $was[$key]) | $key ]')
```

with the comment rewritten to *"Absence is a distinct state: a brief first becoming readable on main is an edit."* Independent action confirms the finding.

## S7. A dispatch that started a session but could not record it leaks it
*(Dimension 9)*

```sh
bg_id=$(printf '%s\n' "$bg_stdout" | LC_ALL=en_US.UTF-8 awk '$1 == "backgrounded" && $3 ~ /^[0-9a-f]+$/ { print $3; exit }')   # lib/dispatch.sh:210
```

Positional. A `\r` redraw, an OSC 8 hyperlink or `ESC[?25l` empties it — `cli_plain` handles numeric CSI only (`lib/dispatch.sh:148`). `dispatch_one` then writes `dispatch_failed` and returns: no stop, no job id, no `dispatch` event, no `caffeinate_hold`. **The session runs untracked, unwatched, uncapped.** `do_detail=$bg_stderr` (`lib/dispatch.sh:286`) discards the stdout line proving it started. Same outcome if no row carries a pid within thirty seconds — there with the job id in hand and still no stop.

- **Why the suite misses it:** the shim prints `backgrounded · %s · %s` line-initial with `id=$(printf '0badc0d%d' "$n")`, and its `bg.color` knob wraps the id in exactly the two escapes `cli_plain` removes.
- **Fix:** quote the unparsed line in the detail; stop what was started before returning, by job id or by live row carrying `session_name`.

## S8. `install.sh` installs the tree it sits in; its success line names the canonical checkout regardless
*(Dimension 10)*

`here=$(cd "$(dirname "$0")" && pwd)` (`install.sh:8`) and every `cp` reads from it (`install.sh:15`), while only `canonical` resolves the main worktree — and only for the registration. A close-out session running it from `../Baton-M<nn>`, or before the merge, installs its unmerged branch tip as the running relay. `install.sh:158` prints `registered at /Users/danny/Documents/Apps/Baton` whichever tree supplied the bytes, so the line quoted as completion evidence confirms the wrong thing. D-079's guarantee is voided with no check failing.

- **Why the suite misses it:** all four install scenarios run `sh "$ROOT/install.sh"` from the repository root and assert file *names* and the resolved canonical path, never installed bytes against `main`.
- **Fix:** resolve `canonical` first and copy from it, or refuse when `here` is not the main worktree with `HEAD` on `main`.

## S9. INV-05's stated enforcement describes a check that does not exist
*(Dimension 1 + Dimension 8 + orchestrator · verified)*

SPEC §5 says *"the double-tick diff is empty on every scenario fixture."* `tests/run.sh:126` loops `for run in 1 2` against one `$tmp/home`, but `run.sh:141-142` snapshots the home **once, after run 2**:

```sh
mkdir "$tmp/got"
cp -R "$tmp/home" "$tmp/got/home"
```

The expectation absorbs the union of both runs. No scenario can assert the second tick changed no state; idempotence is enforced by whoever reads the frozen expectation at freeze time.

**Orchestrator's correction:** the claim goes further than reported. *"The double-tick diff is empty"* is not merely unimplemented but **unimplementable as worded**, because the design contains multi-tick counters — the two-strike dispatch rule, the ladder, `gap_check`. For `held-plan-dispatch-fails` (cited by D1 as a violation), run 1 writes two `dispatch_failed` and run 2 writes two more and parks: that is the two-strike ladder working correctly, and an empty second-tick diff would be the bug. The invariant's true content is what *is* true — the tick holds nothing in memory between runs; every fact is derived from the five inputs.

## S10. The stall and long-running keys do not re-arm where their clock resets
*(Dimension 2)*

`long_running_check` restarts its clock on a `resume` (`lib/rows.sh:322`) but the once-only key does not re-arm there (`lib/derive.sh:431`), so a resumed lane running six more hours says nothing. The same gap silences `stall`. This is the fail-closed shape: the relay goes quiet precisely when it should speak a second time.

## S11. The marker is written for a tick whose steps did not run — a third silence
*(Dimension 1 · verified)*

```sh
if ! tick_project "$tr_key" "$tr_plan" "$tr_rows" "$tr_now"; then
  echo "reconcile   $tr_key · the tick could not finish this project"
  continue                                    # lib/tick.sh:358 — status swallowed
...
[ "$vt_status" -ne 0 ] || marker_write         # lib/tick.sh:394 — so the marker writes
```

Every failure guard in `tick_run` swallows its status — the per-project failure `continue`s, the four cross-project passes are `… || echo …`. A project whose `tick_project` fails gets no crash, stall, takeover, waits, ladder or declared-stop handling, **every sixty seconds**, while `last-tick` advances each minute. `gap_check` is keyed on that marker, so it never fires and nothing reaches the Mac.

- **Why the suite misses it:** grepping all 246 expectation trees for `could not finish this project`, `the dispatch pass failed`, `the offline pass failed`, `the hold pass failed` and `the reserve pass failed` returns **zero hits**. The only non-zero tick status anywhere is `tick-no-rows → 3`.
- **Fix:** flag "a step did not run" in `tick_run` and return non-zero, as the rows case returns 3, so the marker is withheld and the gap fires against the last honest marker. D-049 is the precedent; its reasoning stops at the rows case.

This joins S2 and S3 as a **third independent way the relay goes quiet**, and is the worst of the three: the other two stop work visibly or stop it entirely, while this one keeps ticking and reports health.

---

# 🔵 MINOR

**M1.** `derive_gap` compares timestamps as text — `select(.at > $m)` (`lib/derive.sh:499`), the only lexical `at` comparison in `lib/`; after a UTC-offset change a later event sorts below the marker and the closed-lane half reads zero. Every fixture log carries a single offset. *(D3)*

**M2.** `lib/templates.sh:56` hardcodes `~/.baton/inbox/` — the single place in the relay not reading `$BATON_HOME`, against `hooks/stop-gate:28` which does. With a foreign home inherited from the background service (the D-091 shape; `claude_env_clean` drops only `CLAUDE*`, never `BATON_*`), the session writes its handover to one home while the gate watches another. The one covering scenario freezes the literal `~/.baton/...` instead of `@TMP@`. *(D6)*

**M3.** No Bash rule matches a write into `~/.baton/bin/lib/` — `cp lib/tick.sh ~/.baton/bin/lib/tick.sh` runs under `bypassPermissions` and lands directly in the tick's executable set, skipping merge, standing check and `main`. *(D10 — argues explicitly against D-026; see disagreements)*

**M4.** No version pin, fingerprint or canary anywhere; `claude --version` is never run. A prose-in-JSON match like `(.row.waitingFor // "") == "input needed"` (`lib/rows.sh:357`) silently costs the `question` park if its casing changes. *(D9)*

**M5.** The size cuts are measured on three different quantities: codepoints (`lib/inbox.sh:401`), raw bytes (`lib/dispatch.sh:237`), the JSON line (`lib/log.sh:31`). `log_event`'s 4 KB refusal is unchecked at ~14 of 20 call sites — `consumed`, `dispatch`, `resume`, `copy_fork`, `takeover`, `crash_sighting`, `wait_retry`, `repeated`, `rejected`, `self_check_failed`, `offline` — and for `consumed` the archive move has already happened. *(D3 — could not reach 4 KB with a credible artifact, so reported as a note, not a finding)*

**M6.** `lib/candidates.sh:59-70` increments `dif_read` for a file that exists but whose `jq` read fails, so `has_handover` stays true while its dispositions vanish — an older handover's word can take force, or the milestone escalates `omitted`. *(D3)*

**M7.** `baton allow --resume` refuses a parked lane but not a taken-over one. `vbl_park=$(derive_parked …)` is the whole test (`lib/answer.sh:373`); `stood_off` is never reached. A takeover is not a park (D-066), so `baton allow M05 '<rule>' --resume` stops a session someone is typing into and resumes it with the continue template. INV-04 is absolute and the tick honours it everywhere; this verb does not. No `allow-resume-takeover` scenario exists. *(D1)*

---

# The three most worth fixing before V1.1 is built on top

| # | Finding | Why it must precede V1.1 | Absorbing milestone |
|---|---|---|---|
| 1 | **B1 — the stale deny rail** | Live now, two commands, every V1.1 session inherits it. M13 multiplies exposure by dispatching concurrently. | **Pre-M17 repair** — no V1.1 milestone owns `install.sh`'s upgrade path |
| 2 | **B2 + S1 + S7 — the double-dispatch chain** | Three independent paths to two live sessions or one untracked one. M13 ("more than one at a time") makes lane-to-session identity load-bearing. | **M17** — *Dispatch preconditions before worktree creation* |
| 3 | **B4 — parks released by the contract's own close-out** | The others fail to speak; this one **acts wrongly** — un-parks work a person never released, on a model already refused, every close-out. The park is the human-in-the-loop valve, and M15 rebuilds the taxonomy on top of it. | **M15** — *The escalation taxonomy* |

The three silences (**S2, S3, S11**) rank fourth as a group and belong to **M15-b** (*Host-explained gaps and wake reconciliation*). This is a close call worth revisiting: B4 does bounded harm loudly-but-wrongly, while S11 does unbounded harm silently.

---

# Coverage: what the suite does and does not check

**Split of the 246 committed scenarios: 199 behaviour / 47 neither.** Method: `home/` and `expected/home/` both carry `@TMP@`, so they diff directly; per scenario, files created, files removed, `log.jsonl` line delta, non-log diffs, `calls.log` lines beyond the standing read, and exit status. Line-count-equal `log.jsonl` differences were excluded as the runner's own `prompt_sha256` rewrite.

Of the 47: **20** print a derivation's or classifier's computed answer as JSON (behaviour by the brief's definition), **20** assert a refusal or stand-down by absence, **7** are presentation-only in the strict sense — `status-full`, `status-quiet`, `plan-parses`, and the four `install*` scenarios (whose state goes to `$tmp/home2`, never captured by the snapshot).

**The overlap matters more than the split:** every scenario, including all 199, is a `diff -r` of a stored expectation, and all four stream files are part of that diff. Every behavioural assertion travels *through* frozen text.

### Invariants with no scenario at all (4)
- **INV-01** — no model call. Review-grep only; the shim's `*)` branch catches an unplayed `claude` call, nothing else.
- **INV-05** — idempotence. The double run exists; the comparison does not.
- **INV-11** — as stated ("a tick killed mid-run leaves the old marker"); nothing kills a process. The *other* half ("no marker when the tick did not complete") is pinned incidentally by `tick-no-rows`.
- **INV-12** — the plist's contents are never read by any scenario.

### Qualifications
- **INV-08** — named by no scenario; enforced incidentally because `expected/calls.log` freezes the full resume argv, so any added flag breaks the diff.
- **INV-09** — "no `ask` rule" genuinely discriminated (every fixture `permissions.json` carries one; the composed file has none). "Exactly three hooks" asserted by no count.

### The good result
**Of every invariant that has a scenario, none has a non-discriminating one** — each was checked by asking what the frozen expectation would lose if the behaviour were removed. **All fifteen derivations in `lib/derive.sh` are covered**, each by a scenario printing its computed JSON; none presentation-only.

### Starting states no fixture ever has
No scenario ships `home/prompts/`. None ships `home/bin/` except the eight `notify-*` (and those only `bin/Baton.app`). None runs `baton status` with a `status/` directory present. **None asserts lock contents** — `tests/run.sh` deletes the lock directory before diffing.

---

# Per-invariant verdict (Dimension 1)

| INV | Verdict |
|---|---|
| INV-01 | convention-only, as the spec says. `--print` appears once, as a matched error string (`lib/dispatch.sh:220`); the one model id in code is a hold predicate |
| INV-02 | **partially** — `log_event` refuses when no lock directory exists (`lib/log.sh:18`); "held by *me*" rests entirely on `lock_take`'s atomic `mkdir`. No caller that logs while another process holds the lock could be named |
| INV-03 | **enforced** — `merged_as_verify` (`lib/inbox.sh:33-49`): hex-only, ≥7 chars, resolve, prefix test, ancestry, all before `consume_one` acts |
| INV-04 | **enforced** in the tick via the stand-off list; **partially** on the verb side — see M7 |
| INV-05 | **partially** — behaviour holds on the fixtures read, but the stated mechanism does not exist. See S9 |
| INV-06 | **enforced by filesystem rename** — `archive_move`/`reject_move` precede every act and refuse an existing destination. The move and the act are inseparable in the "twice" direction |
| INV-07 | **enforced by derivation** — `attempt_of` counts `dispatch` events per `(project, milestone)`; the session id is only a join key |
| INV-08 | **enforced by construction** — exactly two resume call sites, both `--bg --resume <id> "<text>"` with nothing after |
| INV-09 | **enforced by `settings_compose`** — fixed jq template; only `allow` and `deny` copied, so `ask` can never reach it |
| INV-10 | **enforced by construction** — no `>>` anywhere in `hooks/`; all three write per-session `.tmp`-then-rename |
| INV-11 | **partially** — ordering enforced in `verb_tick`; the *meaning* is not. See S11 |
| INV-12 | convention-only plus one code guard — the plist names only `~/.baton/` paths, and `worktree_ensure` passes `-c core.hooksPath=/dev/null` (D-048) |

---

# Disagreements, left unresolved

1. **Orchestrator vs Dimension 1, on `held-plan-dispatch-fails`.** D1 cited it as a fixture already violating the double-tick rule; the orchestrator read the fixture and found it to be the two-strike ladder working correctly, and generalised the point (see S9). D1 replied **"Agreed."**

2. **Dimension 3 vs the spec, on what a failure ending is.** REQ-STOP-04 and `CONTEXT.md` both say "a session that cannot be resumed," which reads as every refused resume. D-061 settled the same question the other way for `person_acted`. D3 argues the ladder's rungs are remedies for endings the *session* produced. **The asymmetry is a defect whichever way it resolves — but which way is the owner's to settle.**

3. **Dimension 10 vs D-026, on `bin/`.** D-026 records the Bash exclusion as deliberate and asserts "the Edit and Write rules above already keep `bin/` out of reach." D10 argues the second claim is wrong — those rules bind two tools and the act is a shell `cp` — and that `bin/lib` is never *run* by a session, only sourced by `bin/baton` itself, so `Bash(*.baton/bin/lib*)` would separate run from write cleanly while refusing no legitimate command. **D10 declined to downgrade when invited to.** Flagged as contradicting a live decision rather than adopted.

---

# Clean negatives worth recording

- **No variable collision exists.** Every assignment in `lib/*.sh`, `bin/baton`, `hooks/*` and `install.sh` was machine-extracted (including `for` and `read` bindings) and attributed to its enclosing function. Exactly one name is written under two functions — `dt_project`/`dt_log` in `derive_taken_over` and `dispatch_try` — and it does not fire, because `dispatch_one`'s call tree never reaches `derive_taken_over`. **The D-030 prefix convention holds across 6,000 lines of `local`-less shell.**
- Also cleared against the same name-the-value bar: unquoted expansions (session ids pass `session_id_ok`, milestone ids pass `parse_id`), `set -f` (restored on all three `parse_depends` exits), `while read` subshells, mktemp leaks, BSD portability (`stat -f %m` correct; no `sed -i`, `sed -E`, `grep -P`, `readlink -f`), and PATH under launchd.
- **Parks cannot be freed by non-decisions.** `reread_hashes` is content-hash only — no `mtime`, no `stat`. A touch, autosave, formatter or content-restoring rebase cannot release a park.
- **The lock's rename yields exactly one winner**, staleness is pid-decisive, and a slow-but-alive tick cannot have its lock broken.
- **A malformed log line aborts rather than skips.** `log_json` slurps with `jq -sc`, so one bad line fails the whole read; the status propagates into every caller but three deliberate safe-side `return 0`s. The tick reconciles nothing and writes no marker — safe, but unalarmed, since `gap_check` reads the log too.
- **Archive-only state is handled.** A missing archived file makes the answer *absent*, not wrong (D-095/D-097).

---

# Notes on the review itself

**The subject tree moved mid-review.** 29 files staged between 00:07 and 00:12, including `lib/escalate.sh`, plus a 247th scenario and two rewritten expectations — separate sessions (`claude -n M16`, `claude -n M19`) working in the canonical checkout. `HEAD` never moved. Only one file under review changed; every affected citation was re-pinned to `4710d17` with `git show`. Dimension 8 caught this and flagged it rather than working around it.

**The suite is green and that is not the same as the code being covered.** 246 of 246 pass at the commit. Four invariants have no scenario; lock contents have none; every behavioural assertion travels through a frozen text diff, so a wrong *constant* — `M02` having no hyphen, `~/.baton` happening to be the production home, a fresh `BATON_HOME` having no permissions file — passes forever while only a *change* is caught.

**Two recurring shapes across all ten dimensions:**
1. **A value correct for the fixture rather than correct in general.** Every fixture takes the branch production takes once and never again.
2. **One English sentence implemented two or three times.** "A failure ending" (S4), "a lane was open during the gap" (S2), "the reading changed" (S6). Baton's derivations are unusually disciplined about deriving rather than remembering — which is why INV-05's spirit holds though its stated check does not exist — but a derivation expresses a *definition*, and when the same definition is written twice in different files, the divergence is invisible to every test exercising only one of them.

3. **The inverse of that shape, and the most interesting defect in the review: one implementation asked to carry two meanings (B4).** Nothing is wrong in any single file. `reread_hashes` correctly hashes the brief. `CONTRACT.md` clause 3(c) correctly requires close-out to refresh briefs. `person_acted` correctly reports that the hash changed. The defect lives in the **join** between a contract clause and a hash, where *"the brief changed"* was assumed to mean *"a person decided something about this lane."* Both shapes are invisible to any test that exercises one side, which is why an invariant that reads well in the spec can still be untrue of the system — and why B4 is a design-level finding rather than a bug, despite having a one-line fix.

**Nothing was written to the repository. No fix was applied.**
