Title: The dispatch log
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: 03

## Question

"What a project hands to Baton" fixed half of the run record: consumed handover artifacts move
from `~/.baton/inbox/` to `~/.baton/archive/`, keyed by `<milestone>-<session>.json`. The other
half is Baton's dispatch log. Decide what it records, where it lives, and how it joins the archive.

- **Event kinds.** Which events are written, and with what fields: a dispatch (project, milestone,
  session id, name, model actually run and why it differed from the plan, worktree, time); a
  consumed handover (the archived file it points at); an escalation (what was escalated, by
  milestone name, and how it was resolved — an edit to the plan or a brief, then a re-read); a
  resume (an `asking` artifact answered); a rejection (the file in `~/.baton/rejected/` and its
  reason). The model-actually-run field is the first required one: grading a milestone's output
  against the house standard needs the model written down somewhere the grader does not look
  until after.
- **The session key.** The session id (`CLAUDE_CODE_SESSION_ID`, `sessionId` in
  `claude agents --json`) joins a log entry to its archived handover and to its transcript
  (`~/.claude/projects/*/<session>.jsonl`). Decide whether anything else needs a key.
- **The recovery test.** From the log and `claude agents --json` alone, a restarted Baton must
  reconstruct what is in flight, what is waiting on a person, and which handovers have been
  consumed — after a sleep, a restart, or a killed process. A design that fails this test is
  rejected.
- **Where it lives** and in what form (a JSONL file under `~/.baton/` is the obvious shape;
  say why or why not).

Hangs on "What stops a session, and what happens next" (which endings it records).

### Premises settled by "Relay or conductor" (2026-09-11)

The tick is the log's only writer, under the relay's lock: a launchd firing and a hand run (the
verbs `tick`, `answer` and `status`, the last being the reconcile with no side effects) are the
same script, so every append passes through one code path. Append-only JSONL under `~/.baton/`;
the Stop gate never writes it; the tick logs what it consumes, dispatches, resumes, rejects and
escalates. The log is the record, so a rejection needs no sidecar beside the file in
`~/.baton/rejected/`: its reason is a log event. No rotation until a size is felt. The tick
remembers nothing between runs, so the recovery test is idempotence — tick twice on the same log,
agents listing, inbox, plan file and git check, and the second run changes nothing — and every fact
the tick needs after a sleep or a kill (what is in flight, what waits on a ruling, what was
consumed, each timed wait and its end, which caffeinate holders to re-arm) must be derivable from
the log plus those inputs. Decide the events and fields accordingly.

### Premises settled by "What stops a session, and what happens next" (2026-09-11)

The tick's order is the spine: consume → reconcile rows → waits and resumes → dispatch; stall, crash and
the dispatch hold all assume the inbox was read first in the same tick. Every ending is a consumed
artifact — `complete`, `asking`, `stopped` with its reason, and `api-error` with its `error` — and the log
records each; a session now ends more than once (an `api-error`, a resume, then its real handover under
the same inbox name), so the archive name is `<milestone>-<session>-<consumed-at>.json`. Events the
rules need, because the tick remembers nothing else: dispatch (the attempt number is the count of dispatch
events for the milestone, stored nowhere else); resume, with its kind — continue, finish, or ruling — and
the resume count per attempt; each wait retry (a stop-then-resume every fifteen minutes; the ceilings and
the six-hour caffeinate bound are measured from the first `api-error` consume of the current wait, and a
successful resume ends the wait, so no "wait started" event exists); a crash's first sighting, so the
second consecutive tick can confirm it; a once-only notification per attempt and kind (limit at two hours,
transient at one, unrecoverable and `billing_error` at once, stall, six-hour long-running, prompt lost);
a `blocked_by` wait, once, so `status` shows what a parked lane waits for; a resume that started a copy
(the original stopped, the new id carrying the attempt); every escalation with its class and what it
carries. The ladder — one resume, one redispatch, then escalate — is computed from these events per
milestone, and any artifact the session wrote itself resets it. The dispatch hold (no dispatch on a model
with an active limit wait; every model once a second model is limited) is read from the same log.

### Premises settled by "Where an escalation goes" (2026-09-11)

The escalation record is an event of this log, and a second event resolves it. **The escalation
event** carries: project, milestone, session, class, **scope** (`lane` or `project`), what it
carries (an `asking` artifact's question and options; a permission prompt's command and its
`permission_suggestions[]`; otherwise the detail), the channel it went out on, and the time. **The
resolution event** names how — `ruling`, `answered in place`, or `edit` — and when; those are the
only three ways a parked lane unparks, and nothing times out. Scope is a property of what failed,
not a list of classes: a lane escalation parks its lane, and exactly three failures park all
dispatch for a project (the plan file cannot be read, main does not build after a merge, Baton
itself is unhealthy). `status` reads the open escalation events and shows, per parked lane, the
class, the one line the person read, and the verb.

Three further event kinds, and the keys their once-only rules need. **A widening**: the rule
written, the milestone that earned it, and the time, so the allowlist's provenance lives in the log
and the list cannot drift unnoticed — `baton allow` is its only writer besides a person's edit.
**A permission denial**: every `PermissionDenied` the injected hook records, with `tool_name`,
`tool_input` and `reason`; two new once-only notification keys read from them — three denials
sharing a command head within one attempt (per attempt and head), and the classifier failing rather
than judging, which the `reason` distinguishes (per attempt). **Baton's own gap**: the tick compares
the current time against the newest event in this log, and a gap far past the interval means Baton
was not running; it is reported only when a lane was in flight, waiting or parked during it, which
the log knows because it knows what was in flight. No "Baton started" event is needed — the newest
event of any kind is the clock. `status` prints the time of the last tick first, before anything
else.

The `answer` verb keys on the **milestone**, resolved against parked lanes across all projects, so
the log must make "which lanes are parked, in which projects" derivable at any moment; more than one
match refuses and prints `<project>/<milestone>` candidates, and a milestone that is not parked is
refused, so a ruling is never delivered into a working session. The session id stays in the log and
in the message as the unambiguous form.

### Premises settled by "Watching a dispatched session" (2026-09-11)

The log rests on these, all observed live; evidence in `.scratch/baton/prototype/obs/`.

- **The log must hold every prompt Baton delivered, with its text and its time.** There is no field
  distinguishing the relay from the person: a line typed into an attached session and a line
  delivered by `--bg --resume` are both `origin: {"kind":"human"}, promptSource: "typed"`. Only
  hook-injected text differs (`origin: null`). Detecting a human takeover therefore *requires* the
  log to be able to say "this typed record is not one of mine", which makes the log the mechanism,
  not merely the record.
- **`claude logs <id>` is not a source.** 135,537 bytes, zero newlines, pure ANSI screen replay.
  The transcript (`~/.claude/projects/<slug>/<sessionId>.jsonl`) and the statusLine feed are.
- **The statusLine is a per-turn telemetry feed** and belongs in the run record: its stdin carries
  `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` (`resets_at` in epoch seconds),
  `context_window.used_percentage`, `cost`, `model`, `session_id` and `transcript_path`. None of it
  is in `claude agents --json`.
- **Row fields worth logging per tick**: `state`, `status`, `waitingFor`, `pid`. A crash reads
  `pid: null` while `state` still says `working`; a sleep changes nothing at all.
- **Write per-session files, not one shared file.** Concurrent hook appends from several sessions
  into a single file interleaved during this run.

## Comments

### Premises settled by "Dispatching more than one at once" (2026-09-11)

Events and fields the reader's rules need, beyond those already listed:

- **Dispatch** carries model and effort as dispatched (the plan's `Model` and `Effort` cells, the
  first required field), the worktree path and branch, whether the worktree was reused and the
  commit it stood at, the attempt number, the prompt text delivered (the slot line included), the
  settings file's path, and for `Remote: yes` the three steps (idle start, stop, resume) as one
  dispatch under one session id.
- **Plan overrode disposition**, both directions: a handover `held` on a gate the plan shows
  cleared (dispatched; the gate and the D-number that cleared it), and a handover `run` on a
  milestone the plan holds (not dispatched). Logged, never escalated; `status` shows the plan doing
  its job.
- **A distant `wait_for`**, once per handover and milestone: a `wait` whose target is neither in
  flight, eligible nor `done` notifies once, like a distant `blocked_by`.
- **Omitted**: a plan-eligible milestone no archived `complete` handover lists — a lane escalation
  by milestone name, resolved by an edit or a hand-written artifact.
- **`main-broken`**: a `stopped` reason, project scope; resolved like `merge-failed` by a ruling
  that resumes the session from step (c); several lanes may cascade into it and each is resumed in
  turn after the first fix.
- **Worktree pruned**: the tick removed a leftover worktree — milestone, path, the `merged_as` it
  verified.
- **Self-check failed**: the per-tick `cat` of the plan file or `git rev-parse HEAD` failed for a
  project — the "plan file cannot be read" project-scope escalation, carrying the path and the error.
- **Plan file unparseable**: which table, which row and which cell failed, so the person edits the
  right token.
- **`model_not_found`**: a lane escalation at once (no retry event); the next dispatch after a plan
  edit is a redispatch, attempt n+1, so the log shows attempt n's refused model and attempt n+1's.
- **`fableReserve` hold**, once per hold: the `seven_day.used_percentage` read and the status file it
  came from; lifted when the reading falls below the reserve.
- **Cap queue**: not an event. The order when the cap bites is derived (handover order, fewest in
  flight per project, row order) and needs no record.
- **The status feed** is one file per session at `~/.baton/status/<session_id>.json`, overwritten
  per turn by the statusLine command; the tick reads the freshest for `used_percentage` and
  `resets_at`. It is not part of the log and is not archived.
- **The project key** in every event is the basename of the canonical checkout; a renamed folder
  is a new key, and `status` says "no project at this path" for the old one rather than merging
  histories.

### Resolution — 2026-09-11

**Decided: one append-only JSONL at `~/.baton/log.jsonl`, eighteen event kinds over a five-field
envelope, prompt bodies in per-session sidecar files the events point at and hash, and every count
the rules need derived over `(project, milestone, attempt)` — never over the session id, which is
the join key and not the counting key.** The log is the mechanism as well as the record: because it
holds every prompt Baton delivered, it is the only thing that can say a typed line in a transcript
is not one of Baton's, which is the whole of takeover detection. Two things beside it are not the
log and are never rotated (the status feed, the archive), and a third — a one-line marker file — is
the tick's clock. §2 is the table, §5 the derivations, and §8 the example lines; those three are the
text `docs/ARCHITECTURE.md` carries.

Two premises this ticket inherited are **dropped because their mechanism is gone**, and the reason
is recorded rather than the requirement (§2, footer): the permission-denial event with its two
notification keys, and the `permission` escalation class. Both depend on a `--bg` session holding a
permission prompt, which `bypassPermissions` makes impossible.

#### 1. The envelope

Every event is one JSON object on one line, with `at` and `kind` always present.

| Field | Always? | Value |
|---|---|---|
| `at` | yes | ISO 8601 **with offset** (`2026-09-11T23:14:02+01:00`) |
| `kind` | yes | one of the eighteen in §2 |
| `project` | when the event has one | the basename of the canonical checkout ("Dispatching more than one at once" §1) |
| `milestone` | when the event has one | the plan file's `ID` cell |
| `session` | when the event has one | the `sessionId` — `CLAUDE_CODE_SESSION_ID`, the row's `sessionId`, the transcript's filename |
| `attempt` | when the event belongs to one | the integer §1's rule derives |

**A field the event does not have is absent, never null.** A rule keying on a null fails silently;
one keying on an absent field fails at `has()`, in the test. Three kinds carry no `session` at all
(`dispatch_failed`, `self_check_failed`, and a `hold` whose cause is `fableReserve`), and two carry
no `milestone` (`self_check_failed`, `hold`).

**`at` is Baton's own clock and nothing else.** Every timestamp Baton copies out of Claude Code —
an artifact's `written_at`, `rate_limits.*.resets_at` in epoch seconds, a transcript record's
`timestamp` in UTC with milliseconds — is carried in exactly the form it arrived, in a field named
for what it is. The schema converts between them nowhere. The offset is on Baton's own clock because
a person reads the log and because usage limits reset at wall-clock times.

**`attempt` is stamped for the reader and derived for the rule.** The authority is the count of
`dispatch` events for the `(project, milestone)`; the tick computes that count before it dispatches,
so writing it onto the event costs nothing and makes "the events of attempt 3" a filter instead of a
replay of the file. If a stamp ever disagrees with the count, **the count wins** and the
disagreement is a bug the log itself makes visible. The resume count is the same shape: stamped on
the `resume` event as `resume`, derived as the count of that attempt's resumes. Neither number is
stored anywhere but here — no counter file, no field on an artifact, no state directory. This
confirms "What stops a session, and what happens next" §8 ("the attempt counter lives nowhere but
the dispatch log") rather than amending it.

**The counting key is `(project, milestone, attempt)`.** Every target project has an M01, and Baton
drives its own repository beside Reclaim from the milestone that lands the tick, so a count keyed on
the milestone alone merges two projects' attempts into one the first night both run. The envelope
already carries `project`; the derivations use it. `baton answer <milestone>` refusing on ambiguity
and printing `<project>/<milestone>` candidates ("Where an escalation goes" §7) is the person-facing
half of the same fact.

**After a copy fork the count is still right, and these are the events that make it so.** A copy
fork happens on a resume, not a dispatch: the tick issues a flagless `claude --bg --resume <uuid>
"<text>"`, the CLI prints a `note:` line naming a new id, and the original — which was supposed to
have been stopped — is stopped first ("What stops a session" §2c). Two events must exist:

1. the **`resume`** event, addressed to the original id, with `outcome: forked`; and
2. a **`copy_fork`** event carrying `from_session` (the original), `session` (the new id) and the
   `note` line verbatim.

The attempt count is unchanged because a fork writes no `dispatch` event, so the new id carries
attempt *n*. The resume count is right because resumes are counted per attempt whatever id they
named. And **the session currently carrying an attempt** is the newest of that attempt's
`dispatch.session` and every later `copy_fork.session` for the same `(project, milestone, attempt)`
— the one sentence every derivation that needs a live session id goes through.

#### 2. The event table

Eighteen kinds. Fields listed are those beyond the envelope.

| Kind | Fields | Which rule reads it | Once-only key |
|---|---|---|---|
| `dispatch` | `name`, `model`, `effort`, `remote`, `worktree`, `branch`, `worktree_reused`, `worktree_commit`, `settings`, `prompt_path`, `prompt_sha256` | the attempt count; the ladder's reset point; in flight; the long-running clock; the takeover candidate set; the cap; **the model actually run**, for grading after the fact | — |
| `dispatch_failed` | `stage` (`worktree`\|`settings`\|`prompt`\|`launch`\|`service`), `detail`; no `session` | the second consecutive for a `(project, milestone)` escalates, lane scope; `stage: service` escalates, project scope | — |
| `consumed` | `outcome`, `reason` or `error`, `written_by` (`session`\|`stop-gate`\|`stop-failure`), `merged_as`, `blocked_by`, `archive` | every ending's routing ("What stops a session" §8); the ladder's reset; the notification keys' reset; the terminal test for in flight; the wait's start before its first retry | — |
| `rejected` | `path` (under `~/.baton/rejected/`), `reason` | the lane escalation that follows a rejection (the log is the record, so no sidecar) | — |
| `resume` | `resume_kind` (`continue`\|`finish`\|`ruling`), `resume`, `class`, `outcome` (`delivered`\|`forked`\|`refused`), `prompt_path`, `prompt_sha256` | the resume count; the ladder (`refused` is a failure ending); the long-running clock; the takeover candidate set | — |
| `copy_fork` | `from_session`, `note` | the session currently carrying an attempt | — |
| `wait_retry` | `error`, `since`, `retry` | the dispatch hold; the 1 h and 2 h notification ceilings; the six-hour `caffeinate -i -t` bound; `status`'s next-retry line | — |
| `crash_sighting` | `pid` (null), `state`, `sighting` (1 or 2) | the two-tick confirmation before a crash is acted on | — |
| `takeover` | `first_unmatched_at`, `first_unmatched_uuid`, `typed_count` | stop acting on the lane; restart the long-running clock; reset the attempt's notification keys | per session |
| `escalation` | `class`, `scope` (`lane`\|`project`), `carries`, `channel` | the parked-lane derivation; `status`; `baton answer`'s resolution | — |
| `resolution` | `how` (`ruling`\|`answered in place`\|`edit`), `escalation_at` | the unpark | — |
| `notification` | `class`, `key`, and the class's own fields | the once-only rule | per `(project, milestone, attempt, class)`, with the class's extra term where it has one |
| `hold` | `model` (or `all`), `cause` (`rate_limit`\|`billing_error`\|`fableReserve`), `reading`, `status_file` | the dispatch hold; the `fableReserve` guard | per `model` and `cause` |
| `hold_lifted` | `model`, `cause` | closes the hold | — |
| `widening` | `rule`, `permissions_file` | `baton plan`'s provenance of allow rules | — |
| `plan_override` | `direction` (`dispatched_over_held`\|`withheld_over_run`), `gate`, `cleared_by` | `status` showing the plan doing its job; never an escalation | — |
| `worktree_pruned` | `worktree`, `merged_as` | — (the record of a destructive act) | — |
| `self_check_failed` | `stage` (`read`\|`parse`\|`git`), `path`, and for `parse` also `table`, `row`, `cell`; `detail` | the project-scope park, every tick, for each registered project | — |

**Escalation classes.** Lane: `asking`, `question`, `ladder-end`, `unfinished-twice`, `blocked`,
`merge-failed`, `other`, `disagreement`, `omitted`, `model_not_found`, `dispatch-failed`. Project:
`plan-unreadable`, `plan-unparseable`, `main-broken`, `baton-unhealthy`.

**Notification classes.** `rate_limit`, `billing_error`, `unrecoverable`, `transient`, `stall`,
`long-running`, `blocked_by`, `distant_wait_for`, `prompt-lost`, `gap`, `takeover-silent`. Three
carry an extra key term beyond `(project, milestone, attempt, class)`: `distant_wait_for` keys also
on the handover and the named milestone; `blocked_by` on the named blocker; `gap` on the marker
value the gap was measured against, so one outage reports once.

##### Footer: what is a derivation, what folded, and what is gone

- **The gap report is a derivation, not an event.** The gap is `now` minus `~/.baton/last-tick`
  (§3); whether it is *reported* is the log's question — only when a lane was in flight, waiting or
  parked during it, which the log knows because it knows what was in flight ("Where an escalation
  goes" §5). The report itself is a `notification` with class `gap`.
- **The cap queue is a derivation, not an event.** The order when the cap bites — the handover's
  `eligible[]` order within a project, then the project with fewest in flight, then plan row order
  ("Dispatching more than one at once" §3-7) — is computed from the plan, the archive and the rows,
  and needs no record.
- **A `blocked_by` wait needs no kind of its own.** The `consumed` event with `reason: blocked`
  already carries `blocked_by`, which is what `status` reads; the once-only notification is a class.
- **`main-broken` and `model_not_found` are not kinds.** Each arrives as a `consumed` event — the
  first a `stopped` reason, the second a StopFailure `error` — and each is followed by an
  `escalation` whose `class` names it. One ending, one event; the escalation is the second.
- **`omitted` and the plan-versus-advice disagreement are escalation classes**, not kinds: they are
  the exactly two things step 6 of the dispatch algorithm escalates, both by milestone name.
- **The permission-denial event is dropped, and this is why.** "Where an escalation goes" §4–5
  designed a `PermissionDenied` event carrying `tool_name`, `tool_input` and `reason`, and two
  once-only notification keys read from it: three denials sharing a command head within one attempt
  (per attempt and head), and the classifier failing rather than judging (per attempt). The hook is
  **auto-mode only**, and "Watching a dispatched session" measured that a `--bg` session cannot run
  in `auto` — `--permission-mode auto` is accepted and the session records `default`, established
  three ways — after which "Dispatching more than one at once" §4 chose `bypassPermissions` and
  dropped the hook from the `--settings` file. Under the mode Baton dispatches with, **nothing can
  ever write a denial event**, so the kind, both notification keys and `status`'s denials line are
  not in this schema. **Revival condition**: a dispatch that chooses `default` (which no plan-file
  field selects today), or `auto` becoming reachable in `--bg`. The `widening` event is unaffected —
  `baton allow <milestone> '<rule>'` still writes a rule and still logs its provenance; what it
  loses is the half that read `permission_suggestions[]` off a permission escalation, because there
  are none.
- **The `permission` escalation class is dropped for the same reason.** Under `bypassPermissions`
  nothing prompts, so a row can never read `waitingFor: "permission prompt"` and the class cannot
  occur. Same revival condition. **`question` stays** — `AskUserQuestion` is a tool waiting for
  input, not a permission, and a live row reading `waitingFor: "input needed"` was observed
  repeatedly in the prototype. **`prompt-lost` stays, for the question case only**, and it now means
  something narrower than it did: a row that went from `waiting` to stopped with no ruling delivered
  has lost its *resolution path* — the row transition that would have unparked the lane by an
  answer in place can no longer happen, so `baton answer` is the only route. It has **not** lost the
  call: "Watching a dispatched session" measured that a call parked at `AskUserQuestion` when the
  session stops receives `[Request interrupted by user for tool use]` and **can be answered on
  resume**. So the ruling that follows a `prompt-lost` notification **does not carry the
  dropped-call sentence** ("the pending call was dropped, repeat it if still needed"); that sentence
  was written for the permission case and is dropped with it.

#### 3. Where it lives

**One file: `~/.baton/log.jsonl`.** Append-only, one JSON object per line.

- **The tick is the only writer**, under the atomic `mkdir` lock, and a launchd firing and a hand run
  are the same script with different verbs, so every append passes through one code path with the
  lock held ("Relay or conductor" §4, §6).
- **The append is one `write(2)` of one line under 4 KB.** Prompt bodies are in sidecar files (§4),
  so no line approaches that bound. A single `O_APPEND` write of a short line to a local filesystem,
  with the lock already serialising `baton answer` against a tick, is why there is nothing to
  interleave.
- **Why the prototype's interleaving finding does not apply.** What was measured was *N unlocked
  hook processes*, one per live session, appending to one shared file. **Hooks never write the
  log**: the Stop gate writes an artifact to the inbox, StopFailure writes an artifact to the inbox,
  and the statusLine command writes `~/.baton/status/<session_id>.json` — all already per session,
  all keyed by session id. The finding is an argument for per-session *hook outputs*, which is the
  design, and says nothing about a single-writer file under a lock.
- **Not per project, and not per session.** `baton answer <milestone>` resolves against parked lanes
  across every project; the cap counts in flight across every project; the dispatch hold goes
  account-wide once a second model is limited. Each of those is one scan of one file, or a fan-out
  over N files and N clocks. A per-session log would additionally break the attempt count, the
  ladder and the holds, every one of which must see across sessions.
- **A renamed project keeps its old key.** The log is history: old entries keep the old basename and
  `status` says "no project at this path" rather than merging two histories ("Dispatching more than
  one at once" §1).

**Growth, said out loud.** A milestone that runs cleanly writes two events (`dispatch`, `consumed`).
One that waits out a five-hour limit writes about twenty-four (a `consumed` with `error: rate_limit`,
twenty `wait_retry`s, a `resume`, a real `consumed`). At the cap of two and a handful of milestones
a day, a busy month is a few thousand lines; at roughly 250 bytes a line that is well under a
megabyte, which `jq` reads in milliseconds. **No index, no rotation, no archiving of the log
itself.** *Reversal condition*, the same shape as the shell decision's: when a tick's scan is
measurably slow, split per project — and the three derivations that then have to fan out are
`answer`'s cross-project resolution, the cap, and the account-wide hold.

**`~/.baton/last-tick`** — one line, the `at` of the tick that wrote it, in the envelope's format.
Written **last and atomically** (`last-tick.tmp`, then rename), after the work and after the lock is
released, so its meaning is precisely *a tick completed*. A tick that dies halfway leaves the
previous value, which is the truth. A marker older than the interval while the launchd agent is
loaded is the signature of a script failing every minute — a different failure from an agent that
was never loaded, and `status` can tell them apart. This replaces "the newest event of any kind is
the clock" ("Where an escalation goes" §5): a tick that consumes nothing, reconciles nothing and
dispatches nothing writes no event, so on a quiet night the newest event is hours old while the tick
has fired three hundred times, and a gap report would name the age of the last event instead of the
length of the outage. The *rule* is unchanged; only its clock moved.

The rest of `~/.baton/` is as the closed tickets left it: `inbox/`, `archive/`, `rejected/`,
`status/<session_id>.json`, `projects/<project>/{project.json,permissions.json}`,
`settings/<project>-<milestone>.json`, `config.json`, `bin/`.

#### 4. Prompt bodies, and the takeover rule

**Prompt bodies live in `~/.baton/prompts/<session>/<n>.txt`**, `<n>` counting from 1 per session in
delivery order; the event carries `prompt_path` and `prompt_sha256`. This is the log's own overflow,
not a thing beside it: the file is meaningless without the event that points at it, and the event is
incomplete without the file.

Why not inline: a kickoff prompt is thousands of characters with a slot line that differs per
dispatch, so a `dispatch` line would be multi-kilobyte, the log would stop being readable by eye,
and growth would be dominated by prompt text rather than by events. Why not a hash alone: the hash
answers the takeover question and nothing else, and the exact text a session was given is what the
morning's "why did it do that" reads, and what grading a milestone's output against the house
standard needs beside the model.

##### The rule

For each in-flight lane, the tick locates the current session's transcript by **glob** —
`~/.claude/projects/*/<session>.jsonl`, never a path derived from the project, because a session
dispatched into a worktree is slugged by the worktree's path. If only an
`.orphaned-<ts>-<hash>.jsonl` sibling exists, a wake once misread the transcript and set it aside
(peer session, from the changelog: "the file is now set aside, never deleted"); that is not a
takeover and the lane escalates with the sibling's path rather than being scanned.

**Which records it compares.** `type == "user"` **and** `promptSource == "typed"` **and** `isMeta`
is not true **and** `isCompactSummary` is not true — the same filter the CLI's own reader applies.
Compaction **appends**; it never rewrites or truncates, so every typed record ever written is still
in the file (peer session, measured on a compacted transcript: 97 typed records survive a boundary
two hours later, with a `type: "system", subtype: "compact_boundary"` record marking where the
summary takes over). Hook-injected text is excluded by the same filter: the Stop gate's reason
arrives as a `user` record prefixed `Stop hook feedback:` with `origin: null` and `promptSource:
null`, as do tool results.

**Which log entries it compares them against.** Every `dispatch` and every `resume` for this
`(project, milestone)` — **not for this session alone**. A copy fork's transcript is a byte-for-byte
copy of its parent's with every record rewritten to the new `sessionId` (verified here:
`ea4b650c-…jsonl` contains the prompt Baton delivered to session `5b7ffe74` at 09:14:43, stamped
`sessionId: ea4b650c`), so a per-session match reports a false takeover across the whole inherited
history on every fork. A transcript only ever contains its own lineage, and a lineage is one
milestone, so the milestone is the right scope.

**How it compares.** The record's text is normalised and hashed the same way Baton normalised and
hashed what it wrote to the sidecar — **the same normalisation on both sides**. A trailing newline,
a `\r\n`, or a stripped leading blank line handled differently on the two sides makes every one of
Baton's own dispatches read as a takeover on the first night, so the normalisation is checked once,
offline, against the prototype's captured pair of a delivered prompt and the `user` record it
produced, before M01 relies on it (live item 45, §12).

**The condition, and why it is a comparison and not a scan.** *The lane is taken over exactly while
the transcript's newest typed record is one Baton did not send.* A set-membership test over every
typed record never empties — a person's line from Tuesday stays unmatched forever — so the hand-back
could not work. Against the newest record it self-releases: `baton answer <milestone> "continue"`
writes a `resume` event and delivers a prompt Baton *did* send, which becomes the newest typed
record, and the next tick finds the lane clear. The scan of all records survives only as what fills
the event's `typed_count`.

**What Baton does.** One `takeover` event per session, carrying the first unmatched record's
timestamp and uuid **in the transcript's own format** and the count of unmatched records at the
time of writing; one notification, on the Mac, class `takeover`. Then it **stops acting on that
lane**: no resume, no redispatch, no ruling delivery, no ladder step, and it never prompts over a
person. It still consumes an artifact that lands, and the lane still counts against the cap — it
holds a worktree and a process either way.

**A takeover is not a park.** Parked is what a lane is once an escalation belongs to it: Baton
stopped because it needs a decision. Taken over is Baton standing off because a person is *already
acting*. Different cause, different release, different `status` line, and "Where an escalation
goes" §6's "a parked lane unparks in exactly three ways" needs no fourth. `CONTEXT.md` already
separates the two terms.

**Release**, keeping "Watching a dispatched session"'s wording: the row goes idle **and** a handover
artifact for the milestone has been consumed since the unmatched record — or a `resume` makes
Baton's prompt the newest typed record. The artifact is the operative half (it is written last, at
the close-out, so the turn has ended by construction); the row condition is kept because that ticket
wrote it and it costs nothing.

**The abandoned lane.** A `takeover` event **restarts the long-running clock** — it is neither a
dispatch nor a resume, so resetting the once-only key alone would fire six hours from the old start,
possibly minutes later. Six hours of silence after a takeover notifies once, on the Mac: the person
was at the keyboard an hour ago, and a lane they walked away from is theirs to notice, not an
emergency. `status` prints the way out on the lane's own line — `taken over at <time>; hand back
with baton answer M19 "continue"` — so it is not a thing to be read in a document at 3 a.m.

#### 5. The recovery derivations

Each is one sentence over §2's table, because M01's tests are these sentences turned into fixtures.
A design that needed a field the table does not have would have failed here, and the field would
have gone in; two did — `written_by` on `consumed` and `outcome` on `resume` (§12).

1. **In flight, per project.** Every `dispatch` whose `(project, milestone, attempt)` has no later
   `consumed` with `outcome: complete` and no later `dispatch` for the same `(project, milestone)`,
   resolved through the fork chain to its current session (§1), **intersected with rows in
   `claude agents --json` that carry a `pid`**.
2. **Parked, and why.** Every `escalation` with no later `resolution` naming its `at`. Its `scope`
   says whether the lane or every lane of that project is held; its `class`, the first line of its
   `carries`, and the verb for that class are what `status` prints and what `baton answer` resolves
   against across projects.
3. **Taken over.** Every in-flight lane whose transcript's newest typed record is not one Baton sent
   (§4), which is a live read each tick; the `takeover` event is the record and the notification
   key, not the state.
4. **Which handovers were consumed.** **The archive is the answer, not the log.** Consumption is
   idempotent *by the move*: a file still in `~/.baton/inbox/` has not been acted on, and one in
   `~/.baton/archive/` has. The log records what each consumption *decided*. This is what makes the
   recovery test pass without a consumed-marker to keep in step with the filesystem. The join is by
   field, not by reconstruction: the `consumed` event's `archive` holds the archived filename
   **verbatim** (`<milestone>-<session>-<consumed-at>.json`), and the event's own `at` is that
   `<consumed-at>`; a reader joins on the field and never rebuilds the name from parts.
5. **Each active wait and its first-failure time.** The newest `consumed` with `reason: api-error`
   for a `(project, milestone, attempt)` that has no later `consumed` with `written_by: session` and
   no later `dispatch`. Its start is the `since` its `wait_retry` events carry — and **before the
   first retry exists, `since` is that `consumed` event's own `at`**, because the first retry is
   fifteen minutes after the consume and the tick must know the wait is active in between. The next
   retry is the newest `wait_retry`'s `at` plus `retryMinutes`, **read from the last retry rather
   than extrapolated from the first**, because a lid-close sleep stretches every interval.
6. **Each hold.** Every `hold` with no later `hold_lifted` for the same `model` and `cause`. A
   `rate_limit` or `billing_error` hold lifts when its wait clears; a `fableReserve` hold lifts when
   the freshest status file's `seven_day.used_percentage` falls below the reserve.
7. **Each caffeinate holder to re-arm.** For each in-flight lane, `caffeinate -i -w <pid>` against
   the pid in the **current row** — the log stores no pid, because a supervisor restart gives the
   session a new one and a logged pid would be re-armed against nothing. For each active wait,
   `caffeinate -i -t` for the remainder of `caffeinateMaxHours` measured from its `since`.
8. **The last tick.** `~/.baton/last-tick`, read as a file, not derived from the log (§3).
9. **The ladder's position.** For a `(project, milestone, attempt)`, the count of failure endings
   since the newest reset point, where a **failure ending** is a `consumed` with `reason:
   no-handover`, the second `crash_sighting` of a confirmed crash, or a `resume` with `outcome:
   refused`; and a **reset point** is a `consumed` with `written_by: session` or the attempt's own
   `dispatch`. One resume, then one redispatch, then escalate.
10. **The attempt number**: the count of `dispatch` events for the `(project, milestone)`. **The
    resume count for an attempt**: the count of its `resume` events with `outcome` `delivered` or
    `forked`.
11. **Whether a once-only key is spent.** A `notification` with that class and key exists at or
    after the attempt's newest reset point — **the same reset the ladder uses**, plus a `takeover`.
    One rule, stated once, tested once. An artifact the session wrote itself demonstrates it came
    back, so what it does next is new information; an `api-error` artifact is written by the hook and
    not by the session, so a fifteen-minute wait cycle never re-arms anything.
12. **The dispatch hold**: derivation 6. No dispatch on a model with an active `rate_limit` or
    `billing_error` hold; on every model once a second model is held.
13. **`baton answer <milestone>`**: derivation 2, filtered by milestone across every project. Exactly
    one match acts; more than one refuses and prints `<project>/<milestone>`; none refuses with
    "nothing is waiting on `<milestone>`".
14. **`baton plan`'s provenance of allow rules**: every `widening` for the project, newest first,
    each naming the rule and the milestone that earned it, so the permissions file cannot drift
    unnoticed.
15. **The gap**: `now` minus `~/.baton/last-tick`. Reported as a `notification` with class `gap`
    only when derivations 1, 2 or 5 show a lane was in flight, waiting or parked during it — a gap
    with nothing to do is not an outage. Keyed on the marker value it was measured against, so one
    outage reports once.

**The recovery test is idempotence** ("Relay or conductor" §4): tick twice against the same log,
agents listing, inbox, plan file and git check, and the second tick changes nothing. Every one of
the fifteen derivations above is a pure function of those inputs, which is what makes that true.

#### 6. `status`, and how far back it reads

**One view, no flags**, ordered by what needs the person first:

1. **the last tick**, from the marker file — the answer to "is it running?", and the one line that
   is printed before anything else ("Where an escalation goes" §5);
2. **project-scope parks** — all dispatch held for a project, with the class and the verb;
3. **parked lanes** — `<project>/<milestone> · <class> · <the one line the person read> · <the verb>`;
4. **taken-over lanes** — `taken over at <time>; hand back with baton answer <M> "continue"`;
5. **waits and holds** — the `error`, the elapsed time from `since`, the next retry, and each hold
   with its model and cause;
6. **in flight** — `<project>/<milestone>`, session, model, attempt, elapsed since the latest
   dispatch-or-resume event, and any live notification (`stalled`, `<n> h`);
7. **silent waits** — a `blocked_by` whose blocker is in flight or eligible, and a distant
   `wait_for`;
8. **an open gap**, if one was reported and nothing has cleared it.

**It reads the whole file, every time.** An escalation opened three weeks ago and never resolved must
still appear; a bounded window is precisely the thing that would drop it, and §3's size argument says
the whole file is cheap. There is **no denials line** — there are no denial events (§2 footer).

A second mode was weighed and dropped: with the cap at two the whole output is a dozen lines, and a
flag to remember is worse than a line to skim at 3 a.m.

#### 7. Three things beside the log, and what each holds that it does not

None is rotated or archived by the tick, and each joins the log by **session id**.

- **The status feed**, `~/.baton/status/<session_id>.json`, overwritten per turn by the injected
  `statusLine` command. It holds what neither the log nor `claude agents --json` carries:
  `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` (`resets_at` in epoch seconds),
  `context_window.used_percentage`, `cost`, `model`, `transcript_path` and `session_id`. It is
  **telemetry, not history** — only the newest value means anything, which is why it is overwritten
  and not appended. The tick reads the freshest for the `fableReserve` guard and for a wait's reset
  time; the log holds the tick's *decisions*, and a reading it acted on is copied onto the event
  that acted (`hold.reading` and `hold.status_file`).
- **The archive**, `~/.baton/archive/<milestone>-<session>-<consumed-at>.json`. It holds the
  sessions' **own words**, in full: a `complete` handover's `eligible[]` with a disposition and a
  brief pointer per milestone, an `asking` artifact's question, options, recommendation and context
  pointer, a `stopped` artifact's `detail`. The log holds what the tick decided *about* it —
  `outcome`, `reason`, `merged_as`, `written_by`, the archived filename — and deliberately not
  `eligible[]`, because step 6 of the dispatch algorithm opens the newest archived `complete`
  handover anyway and copying the dispositions into the log would make two sources for the one thing
  that must not drift.
- **The marker**, `~/.baton/last-tick`. One value, overwritten; not history at all.

`~/.baton/prompts/<session>/<n>.txt` is **not** in this list: it is the log's own overflow, pointed
at and hashed by the event that delivered it.

#### 8. Example lines

A dispatch, an escalation and its resolution, and a takeover — so M01 has a fixture to copy. Wrapped
here for reading; each is one line in the file.

```json
{"at":"2026-09-11T23:14:02+01:00","kind":"dispatch","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "name":"Baton · Reclaim · M19","model":"fable","remote":false,
 "worktree":"/Users/danny/Documents/Apps/Reclaim-M19","branch":"m19","worktree_reused":false,
 "settings":"/Users/danny/.baton/settings/Reclaim-M19.json",
 "prompt_path":"/Users/danny/.baton/prompts/7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9/1.txt",
 "prompt_sha256":"4f9a1c07b3e5d8206f1a4c9b7e02d35a8c6f1b490d2e7a3c5b8f0d1e6a4c9b72"}
```

```json
{"at":"2026-09-12T02:41:18+01:00","kind":"escalation","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "class":"asking","scope":"lane",
 "carries":{"question":"Should ReclaimCore expose FileSizeFormatter, or keep it internal and duplicate it in the app?",
            "options":["expose","internal"],"recommendation":"expose"},
 "channel":["notification"]}
```

```json
{"at":"2026-09-12T08:02:55+01:00","kind":"resolution","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "how":"ruling","escalation_at":"2026-09-12T02:41:18+01:00"}
{"at":"2026-09-12T08:02:56+01:00","kind":"resume","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "resume_kind":"ruling","resume":1,"outcome":"delivered",
 "prompt_path":"/Users/danny/.baton/prompts/7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9/2.txt",
 "prompt_sha256":"91b3e7c2a04f6d18b5e9c3a7f60d2b48e1c5a9037d6b2e8f4a0c1d7b39e5f8a26"}
```

```json
{"at":"2026-09-12T09:17:03+01:00","kind":"takeover","project":"Reclaim","milestone":"M19",
 "session":"7c2f1a4e-6b03-4d51-9a28-5f1c0e2b77d9","attempt":1,
 "first_unmatched_at":"2026-09-12T09:15:44.812Z",
 "first_unmatched_uuid":"b67d02df-c685-4a56-ada2-faa626f97905","typed_count":2}
```

Note the two clocks side by side in the last one: `at` is Baton's, with offset; `first_unmatched_at`
is the transcript record's own `timestamp`, carried exactly as it arrived.

#### 9. Every point, and where it landed

| Point | Outcome |
|---|---|
| The ticket's **Event kinds** bullet | **Decided**: §2, eighteen kinds; the dispatch, consumed, escalation, resume and rejection the bullet names are five of them, each with the fields it asks for. The model actually run is on `dispatch`, with `effort`, so a grader reads it after the fact. |
| The ticket's **session key** bullet | **Decided**: §1. The session id joins the log to the archive, the transcript, the status feed and the prompt sidecars. **Nothing else needs a key**, and the counting key is `(project, milestone, attempt)` — a separate thing from a join key, and the distinction is the one that survives a copy fork and a second project. |
| The ticket's **recovery test** bullet | **Decided**: §5, fifteen derivations, each a pure function of the five inputs; idempotence is the test. |
| The ticket's **where it lives** bullet | **Decided**: §3, one JSONL at `~/.baton/log.jsonl`, with the interleaving finding answered rather than waved at. |
| 1. The envelope | **Decided**: §1. `attempt` and the resume count derived, stamped for the reader, stored nowhere else — confirming "What stops a session" §8. The copy-fork events named. |
| 2. The event table | **Decided**: §2, with a footer separating derivations from events and recording the two dropped premises with their revival conditions. |
| 3. File layout and the atomic append | **Decided**: §3. |
| 4. Prompt bodies and the takeover rule | **Decided**: §4, sidecar plus hash; the rule written as a comparison against the newest typed record so it releases. |
| 5. The recovery test made executable | **Decided**: §5. |
| 6. `status` and the reads | **Decided**: §6, one view, whole file, no denials line. |
| 7. Two things the log is not | **Decided, and it is three**: §7 — the status feed, the archive, and the marker file §3 added. |
| The permission-denial event, its two notification keys, and the `permission` escalation class | **Dropped, with the reason and a revival condition** (§2 footer). Not deferred: there is no ticket that could take them while `bypassPermissions` is the dispatch mode. |
| Rotation | **Deferred until a size is felt**, as "Relay or conductor" required, with the growth estimate and the reversal condition stated (§3). |
| The hash normalisation, the `note:` line's parseability, a failed `claude --bg`'s output | **Left open as live proofs**, items 45–47 on "Watching a dispatched session" (§12). Each is a fact about the CLI, not a decision. |

#### 10. Evidence

- **Looked at this session**, read-only, under `~/.claude/projects/-Users-danny-Documents-Apps-Baton--scratch-trial-project/`: a `user` record carries `type`, `uuid`, `parentUuid`, `timestamp` (UTC, milliseconds, `Z`), `origin`, `promptSource`, `promptId`, `userType` and `message.content`. A prompt delivered by `claude --bg --resume` lands verbatim with `origin: {"kind":"human"}, promptSource: "typed", userType: "external"` (`ea4b650c`, the RULING line at 09:19:39); a line typed into an attached session is identical in those fields (`28926e91`, "noted carry on" at 09:08:46); Stop-gate feedback and tool results both carry `origin: null, promptSource: null`. **A forked copy's transcript is a full copy of its parent's rewritten to the new id**: `ea4b650c-…jsonl` holds the prompt delivered to `5b7ffe74` at 09:14:43 under `sessionId: ea4b650c`, and its first record is a `custom-title`. `promptId` is reused across two prompts in one session (`ea4b650c`) and fresh in another (`e303d36e`), so it is not a correlation key.
- `.scratch/baton/prototype/obs/statusline.jsonl` (68 records carrying `rate_limits`): the statusLine stdin's keys, `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` with `resets_at` in epoch seconds, `context_window.used_percentage`, `cost`, `model`, `session_id`, `transcript_path`, and in some records `prompt_id` and `prompt_cache`. `obs/row-watch.jsonl` and `obs/remote-watch.jsonl`: `{state, status, waitingFor}` per second, including `waitingFor: "input needed"` through an `AskUserQuestion` park. `obs/stop.jsonl`: the Stop gate's payload with `session_id`, `transcript_path`, `prompt_id`.
- `~/.claude/jobs/<id>/state.json` on this Mac: `state`, `detail`, `tempo`, `needs`, `output`, `children`, `template`, `respawnFlags` — no field recording who sent a prompt, consistent with "Where an escalation goes"' finding that no `answeredBy`-style field exists.
- Closed tickets: "Relay or conductor" §4 (the five inputs; idempotence as the recovery test; caffeinate), §6 (the tick as the log's only writer, append-only JSONL, a rejection's reason as a log event, no rotation until a size is felt), §7 (a ruling's delivery). "What stops a session, and what happens next" §0 (the tick's order), §1 (the two-bit table), §2a–2e (the `api-error` artifact, the archive suffix, the ladder, the fifteen-minute wait, the continuations), §3–§6 (stall, circling, prompts, crash), §8 (each `stopped` reason; the attempt counter's home), §9 (the dispatch hold). "Where an escalation goes" §4–§7 (the escalation and resolution events, the widening, the gap report, `answer`'s milestone key, scope). "What a project hands to Baton" §2–§4 (the artifact's fields; the inbox, archive and rejected directories; provenance). "Dispatching more than one at once" §3 (the eight steps this log serves), §4 (the three hooks that fire), §5 (worktree pruning), §6 (`config.json`'s numbers), §7 (`fableReserve`, `remote`, `model_not_found`). "Watching a dispatched session" (the takeover discriminator; per-session hook files; the statusLine as the watch substrate; `pid: null` as the crash tell; the flagless resume; `auto` unreachable in `--bg`; the `AskUserQuestion` interrupt marker).
- Peer session "Milestone Model Audit", 2026-09-11, tagged from the 2.1.268 binary [B], the cached docs and changelog [D] and local files [L]: **compaction appends and never rewrites** — the reader skips by flag (`if(_.type!=="user")continue;if(_.isMeta===!0||_.isCompactSummary===!0)continue`) and a `type: "system", subtype: "compact_boundary"` record marks the handover [B], with a local transcript keeping all 97 typed records across a boundary two hours earlier [L]; **`.orphaned-<ts>-<hash>.jsonl` is a set-aside copy from a wake whose transcript probe misread the file**, named `orphaned-${Date.now()}-${uuid.slice(0,8)}` [B], "the file is now set aside, never deleted" [D]; **`cleanupPeriodDays` defaults to 30 days** and sweeps `~/.claude/tasks/`, `shell-snapshots/`, `backups/` and job worktrees too [D], while this Mac sets `3650` [L]; `promptId` is assigned by the CLI from replaceable app state and cannot be set from outside [B].

#### 11. Unverified

- That the hash of a prompt Baton wrote to a sidecar equals the hash of the `user` record it
  produced, under whatever normalisation M01 chooses. Checked offline against the prototype's
  captured pair before the takeover rule is trusted (item 45).
- What `claude --bg --resume` prints when it forks a copy, byte for byte under `LC_ALL` — the
  `copy_fork` event's `session` is parsed from it, and the `·` separator is two bytes in a locale
  launchd does not set (item 46).
- What a failed `claude --bg` prints, and on which stream, so `dispatch_failed`'s `stage` and
  `detail` can be filled rather than guessed (item 47).
- Whether a compaction ever writes to a *different* file. Nothing observed or documented says so;
  the local evidence is one file (peer session, [U]).
- Whether the supervisor's ~1 h idle stop applies to a session waiting at `AskUserQuestion` —
  carried unchanged from "What stops a session"; it is the case the `prompt-lost` class now exists
  for.

#### 12. Deferred, and to which ticket

- The events' place in `docs/ARCHITECTURE.md`, `docs/SPEC.md` and `docs/DECISIONS.md`, and which
  milestone of Baton's must land the log: **"Baton's plan and its M01 prompt"**. `cleanupPeriodDays`
  joins the Full Disk Access grant and the `bypassPermissions` disclaimer as a setup fact that
  ticket's plan must name — a fresh Mac prunes transcripts at 30 days, and "a transcript exists" is
  the resume-versus-redispatch test.
- Two fields no closed ticket named, each recorded as a dated comment on the ticket that owns its
  rule: **`written_by` on `consumed`** and **`outcome` on `resume`** — "What stops a session, and
  what happens next", whose ladder reset ("any artifact the session wrote itself") and copy rule
  both need them. The `dispatch_failed` kind — "Dispatching more than one at once", which owns the
  dispatch algorithm. The dropped denial event and the gap report's new clock — "Where an escalation
  goes". The takeover rule's shape and the transcript facts under it — "Watching a dispatched
  session".
- Live proofs **45**, **46** and **47**: **"Watching a dispatched session"**.
- Rotation, an index, and any split of the log: **not deferred to a ticket** — they wait on a size
  being felt, with the reversal condition in §3.
