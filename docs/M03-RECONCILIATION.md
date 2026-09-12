# M03 and foundation reconciliation

## Status and provenance

M03 is **in progress**, confirmed by the user and inspected read-only in
`/Users/danny/Documents/Apps/Baton-M03`, branch `m03`, on 2026-09-12. The inspected committed head
was `c93098386bd54b2f7324dca220e4bc156d6aea72`; it contained five commits after the shared M02 base
`131205d9e68165cc48215983e30aa8eb2c34c001`. Additional uncommitted changes existed in the installer,
dispatch/inbox integration, rows, tick, notifications and tests. This is a checkpoint, not a frozen
inventory: re-read HEAD and the working tree before integrating.

The foundation branch has contract-2 primitives and its own 31 historical regression / 61 foundation
check result. Its CLI does not yet expose a tick. M03 has tick/row/notification/launchd implementation
on the other branch. Neither fact means M03 has not started, nor that a combined contract-2 tick has
been verified. M03's Completion evidence section was empty at inspection; no test or live result is
inferred from that absence or from a decision's prose.

## Preserve and adapt

| M03 work observed | Preserve | Reconcile before combined acceptance |
|---|---|---|
| `lib/tick.sh`, `bin/baton` | Tick composition, per-project self-checks and bounded fault scope | Compose contract-2 observations, run reservations and immutable consumption. Factor/reuse **all** dispatch admission checks; do not call `dispatch_one` directly and bypass cap/ownership/repository checks. |
| `rows_read` in `lib/rows.sh` | Distinction between an unreadable listing and an empty fleet | Use the bounded/schema-validating adapter and explicit observation generation. Do not create a second raw provider-call path. |
| `inbox_holds`, `ended_on_disk`, inbox changes | Avoid calling an already-handled ending a crash | Replace session-filename globs and “archive implies handled” with message/run identity, processing/ack state and unresolved launches. Consumption has no stop path. |
| `takeover_check`, row stand-off | Conservative suppression of intervention when evidence is unreadable | Explicit owner and typed-record UUID boundary wins. Historical `derive_taken_over` hashes are not authorization. |
| `crash_check` and timing fixtures | Distinct observations, interruption guards and fixture-controlled mtimes | A successful presence or unavailable observation breaks a consecutive-absence sequence. Replay of one observation cannot count twice. Do not treat every historical consumed event as a permanent crash exemption after a later delivery. |
| `tick_dispatchable`, `dispatch_try` | Exclude already-open work and bound recovery | Remove archived `eligible[].disposition` scheduling. Reserve prepared/uncertain runs; failure is not proof that no launch happened. No cap-free pass-through until M06. |
| Self-check deduplication and project isolation | Avoid repetitive event floods; unaffected projects may continue safely | Record partial/incomplete tick status. Swallowing a project failure must not produce a global “fully completed” marker. |
| `marker_write`, `verb_tick` | Marker after successful work | Write the completion marker while still holding the kernel lock, with unique temp publication. Do not release the lock before updating it or advance it after an incomplete run. |
| `lib/notify.sh` and `BATON_OSASCRIPT` seam | Text escaping, class/field validation, one message composer and captured argv tests | Keep stable notification intent distinct from delivery result. Bound the transport; retain pending/failed delivery visibly. A swallowed transport error is not “every message reached the Mac”. |
| Caffeinate re-arming | Avoid one new long-lived holder per lane per tick; explicit host sleep limits | Detached children must close FD 9. Track/bound holder lifecycle so the kernel mutation lock cannot outlive the tick through a holder. |
| `install.sh`, launchd plist | M03's shell-signing observations and explicit live acceptance | Retain immutable release selection and isolated fixture destinations. Incorporate the signed-shell executable check before launchd activation; copying `/bin/sh` or `codesign --verify` alone is not the recorded proof. Do not install into the real LaunchAgents directory during fixture tests. |
| `lib/status.sh` changes | Last tick, stall/long-running information and host limitations | Preserve lock-free status, uncertain runs, ownership, questions and processing anomalies. Put any shared message rendering in a pure helper, not a second state reader/writer. |
| M03 scenarios, `mtimes`, test shims | Crash/sleep/stall/subagent/question/self-check/transport coverage | Port expectations to contract 2 and add combined fault tests. Do not overwrite foundation tests with the old 82-scenario runner. |
| M03 decisions D-038 onward | Original IDs and measured evidence | Foundation IDs are now FND-*. Do not overwrite either log based on numeric collision; preserve the provenance mapping. |

## Completion sequence for the active work

1. Continue in the existing `m03` worktree. Preserve its current changes and useful tests; do not
   restart M03 or create a second M03 session. The existing branch name is legitimate legacy work;
   do not rename/reset it merely to match the new branch-name default.
2. At a coherent checkpoint, record its head and dirty state. Prepare a combined candidate with the
   foundation changes and adapt the overlapping modules using the table above. A clean Git merge
   alone is not protocol compatibility. Do not replace one side wholesale.
3. Apply current governance/spec/contract together. If the M03 implementation revealed a better
   mechanism, record its evidence and amend the mechanism while preserving the P-/F- property.
   Bring useful signed-shell, cold-start and notification observations into the current docs with
   their limits, rather than discarding them as obsolete prototype material.
4. Run the combined candidate's standing suite and adapted M03 cases. Record output separately from
   the earlier foundation-only run. Check each requirement below. Do not reuse a passing result
   from one branch as evidence for the other.
5. Carry out only the live proofs actually authorized for M03. Existing authorization need not be
   requested again; a new action is not authorized merely by this checklist. Preserve observed
   results, and identify cold-start/host/runtime/release conditions still untested.
6. Mark M03 done only when the combined acceptance holds. M04 follows that acceptance, not merely
   existence of `tick.sh` or an old contract-1 handover. Activation is a separate compatibility and
   host-capability step under MIGRATION.md.

## Combined acceptance still required

- [ ] A healthy observation can prove absence; unavailable/incompatible data cannot advance crash
  state, release capacity or launch a replacement. Same-observation replay is not a second sighting.
- [ ] Prepared, uncertain, active and human-owned runs reserve capacity. The same admission checks
  protect manual and scheduled dispatch, including repository identity and the one-project limit.
- [ ] The tick consumes contract-2 messages and recovers processing/ack boundaries without any
  session-filename or historical-disposition authority.
- [ ] Human ownership is checked before every process action; new/unreadable typed records hold it.
- [ ] Every failure propagates to explicit per-project/global completion state. A completion marker
  is updated atomically under the lock only when its declared scope completed.
- [ ] No notification is marked delivered merely because intent was journaled. Failed/pending
  transport remains visible and replay cannot duplicate a decision.
- [ ] Detached caffeinate/transport/provider work cannot retain the controller's lock descriptor.
- [ ] Installer/plist integration retains immutable releases, pinned hooks and fixture isolation.
  Signed-shell execution and the required FDA/service-start cases have named evidence or remain
  explicitly unverified. A warm-service observation does not prove the cold-start case.
- [ ] Foundation tests plus M03's adapted fault/timing/transport scenarios pass on the **combined**
  candidate. The result is independently reviewed and remaining limitations are recorded.

This checklist documents unfinished reconciliation, not a claim that it has already been performed.
This documentation task does not edit M03's runtime, run its tests, change its session, merge/rebase
its branch, install a release, or load/unload its launchd job.
