Title: Where an escalation goes
Labels: wayfinder:grilling
Status: closed
Assignee: danny
Blocked by: 03, 05, 06

## Question

What may a session nobody is watching do on its own, and for everything else — a permission it
cannot take, a question it asks, a stop it cannot clear — where does it reach you, what can you do
from there, and how does your ruling get back? One policy, ordered from the permission mode to the
ruling's return.

1. **The permission mode** per target project, and whether it differs for a session in a
   worktree. Facts: `~/.claude/settings.json` sets `permissions.defaultMode: auto` today. Reclaim
   authorises builds and tests (D-030) but has no `.claude/settings.json` and no allowlist, so
   whether `xcodebuild`, `swift test` or `git commit` prompt depends on auto mode's judgement each
   time. `--permission-mode` offers acceptEdits, auto, bypassPermissions, manual, dontAsk, plan;
   `claude agents --allow-dangerously-skip-permissions` makes bypass *available* to dispatched
   sessions without defaulting to it; `--restricted` exists. The principle in the global
   CLAUDE.md is that safety must buy capability: cheap undo (git, a worktree per session,
   Trash-first removal) beats a prompt nobody is awake to answer.
2. **The allowlist**: a project allowlist of tool patterns, and whether Baton passes it with
   `--settings` at dispatch so the target repo is not touched (the same file that carries the
   Stop gate), or whether it belongs in the target's own `.claude/settings.json` as part of the
   project contract.
3. **What stays forbidden even unattended** — network egress, `sudo`, deletion outside the
   worktree — and how that is enforced (allowlist, deny list, or the target's hard rules, which
   for Reclaim already forbid removal on real user data).
4. **A prompt that is neither allowed nor denied**: it waits and escalates (per "What stops a
   session, and what happens next"), or it is refused and the session told why.
5. **Where each escalated class reaches you**, for each class "What stops a session, and what
   happens next" marks *escalate*: on the phone through Remote Control, answering in place
   ("Reaching you when you're not at the Mac" found it is the one channel where a phone both
   hears and acts, and that it needs an interactive session); a macOS notification, useful only
   at the machine; the `claude agents` view when you return, with the stuck session named for its
   milestone. Decide what the notification carries and what it points at.
6. **Pause semantics**: does one escalation stop all dispatch until you answer, or only the
   affected milestone's lane while the others carry on? (A Reclaim night has one lane until
   v0.3's fan-out; the answer matters more later.)
7. **The ruling's return.** An escalation never times out into a decision; the lane stays parked
   until a ruling arrives. Decide how the ruling reaches Baton's `answer` verb — typed at the Mac,
   sent from the phone, written to a file — and what the label on it reads.

### Premises settled by "Relay or conductor" (2026-09-11)

Baton embeds no model call: nothing here is answered by Baton, and the person answers by any means
they choose. On consuming an `asking` artifact the tick stops the session (`claude stop <id>`) so
that the later resume continues under the same id instead of forking a copy; `answer` resumes it
with the ruling verbatim as its next instruction, labelled as a ruling, the Stop gate re-injected.
The escalation record is a dispatch-log event, because the tick is the log's only writer. "Permissions
for a session nobody is watching" is folded in here as points 1–4: the prompt that is neither
allowed nor denied is the seam between the two halves, and it belongs to one decision.

### Premises settled by "What stops a session, and what happens next" (2026-09-11)

Two kinds of message, never confused: a **notification** is one Baton keeps working past (the session
runs on, or the retry continues); an **escalation** parks the lane until a ruling or an edit resolves it.
Every class carries a notify-now bit, and nothing times out into a decision or a denial. What escalates,
and what each carries: an `asking` artifact (question, options, recommendation, context; the session
stopped on consume, resumed by `answer` with the ruling); a live row with `waitingFor: "input needed"`
and no artifact, or `waitingFor: "permission prompt"` (row name, milestone, session; the process alive
and untouched — stopping it loses the pending call); the third failure ending on one milestone (the
ladder's end: the last artifact or the crash sighting); a second consecutive `unfinished` (both splits);
`blocked` whose `blocked_by` is neither in flight nor eligible, or names nothing (the detail);
`merge-failed` (the detail; resolved by `answer <session> "merge resolved; finish the close-out from
step (c)"`, which resumes the session to refresh the successor briefs and write the real artifact — the
plan-file edit is the fallback when the session is gone); `other` (the detail). What notifies: `rate_limit`
after two hours of waiting, `billing_error` and the unrecoverable set (`authentication_failed`,
`oauth_org_not_allowed`, `account_on_hold`, `cloud_credential_error`, `model_not_found`, `unknown`) at
once, transient after one hour — each with `error` and the error text verbatim, the only place a reset
time appears, and the retry continuing so a fix at the Mac (a `/login`, a plan edit) needs no `answer`;
a stall (row name, the row's `state`, and the matching verb: `done` means `answer` with the finish
template, `blocked` means the wait path by hand); six hours since the attempt's latest dispatch-or-resume
event; a `blocked_by` wait, once; "prompt lost" — a row gone from `waiting` to stopped with no ruling
delivered, after which `answer` carries the ruling as text ("the permission you asked for at <time> is
granted/denied; the pending call was dropped, repeat it if still needed"). Decide here the channel, the
record and the `answer` verb's inputs for each. Also decide the mechanism recorded so it is not
rediscovered: the row says only `waitingFor: "permission prompt"`, but the Notification hook's
`permission_prompt` type (fires after about six seconds; payload `message`, `title`,
`notification_type`, hooks.md §4.2) can be injected with the gate to write the prompt's text beside the
escalation, making it specific ("M29 wants to run xcodebuild …") and letting the allowlist be widened
by one line the next morning.

## Comments

### Resolution — 2026-09-11

**Decided: `auto` plus a per-project allowlist, both carried in the `--settings` file Baton composes
at dispatch; a prompt that is neither allowed nor denied parks its lane and reaches the phone as
three lines; a notification stays on the Mac; every ruling returns through `baton answer
<milestone>`.** One measurement inverted a premise of this ticket and reshaped the seam: the
`Notification` hook's `permission_prompt` message names the tool, not the command (§4).

#### 1. The permission mode

**`auto`, with a project allowlist, identical on main and in a worktree.** The allowlist keeps
builds, tests and git deterministic and widenable; the classifier absorbs the long tail no list
enumerates on night one. The two are not alternatives: allow rules are the original mechanism and
auto is a layer on top of them, so `Bash(xcodebuild:*)` runs without a prompt under auto, and `ask`
and `deny` rules bite there too.

- **`PermissionDenied` is injected with the other hooks**, so every classifier refusal is in the
  log with its `tool_name`, `tool_input` and `reason`. It fires in auto mode only, so the mode is
  what makes the long tail observable at all; under any other mode a refusal is invisible. Baton
  returns no `retry`.
- **A worktree changes nothing.** The worktree is the undo, not a permission boundary: git cannot
  undo a command that leaves the tree, and the deny list deliberately does not confine the file
  tools (§3). The mode is a property of the target project.

Rejected, each with the reason:

| Mode | Why not |
|---|---|
| `dontAsk` | Denies. The binary hands the model " has been denied because Claude Code is running in don't ask mode."; anything that would have prompted is refused and nobody sees a prompt — the failure this ticket exists to prevent, arriving instantly and silently. |
| `bypassPermissions` | Removes the seam entirely, and is gated: `--bg` with bypass "requires accepting the disclaimer first", and the binary refuses when the session is "not a contained no-internet environment", which this Mac is not. A target's hard rules are prose a model follows, not a thing this mode enforces. |
| `manual` | An alias for `default`; the binary accepts it as one. |
| `default`, `acceptEdits` | Both work with an allowlist, and `acceptEdits` is `default` plus auto-accepted edits. Rejected because an allowlist alone enumerates nothing it has not met, and night one has met nothing. |
| `--restricted` | Removes Bash and the other code-running tools unless `--tools` names them — unusable for a milestone that must build. |

**The circuit breaker is not a mid-night risk.** Its only occurrence in the binary is a startup
check for IDE sessions that falls through to `default` when set; it is not a mode change mid-run.
The real mid-session risk is different and documented: on a very long conversation the classifier's
own transcript exceeds its context window and "the same call will hit the same limit until the
conversation is shorter". That manifests as denials, not a silent mode switch; `PermissionDenied`
logs it, compaction clears it, and §5 gives it its own notification.

#### 2. The allowlist, and the dispatch settings

**In the `--settings` file Baton passes at dispatch. The target repository is not touched, and its
`.claude/settings.json` gains nothing.** Baton composes that file per dispatch from two parts:

- **The project's permissions** — Baton's own state at `~/.baton/projects/<project>/permissions.json`,
  holding `permissions.allow` and `permissions.deny` for that project and nothing else.
- **Baton's block** — `permissions.defaultMode: "auto"` and the `hooks` entries, whose commands
  carry the project and milestone baked in as arguments (the mechanism "What stops a session, and
  what happens next" §2a already fixed for the Stop gate and the StopFailure hook; one mechanism
  serves all four hooks).

Baton's code therefore never knows what `xcodebuild` is: the knowledge is state, keyed by project,
and a second target project adds a file rather than a branch. **The project contract gains no
clause; it stays at six.**

A person hand-starting a session gets identical permissions by passing the same file —
`claude --settings ~/.baton/projects/<project>/permissions.json` — because it is a real path, not a
value assembled in memory. That closes the one real cost of keeping the list out of the repository:
a session started by hand would otherwise behave differently from a dispatched one, and daytime
experience would stop predicting the night's.

**Merge-versus-replace never arises.** Whether `permissions.allow` arrays merge or replace across
settings levels is undocumented and could not be established (Unverified, below). With the allow and
deny arrays existing in exactly one file, and neither the user settings nor the target repository
holding any, the question has no bearing on the design. Recorded so it is not rediscovered.

#### 3. What stays forbidden even unattended

Two deny lines, and nothing else.

| Rule | Reason |
|---|---|
| `Bash(sudo:*)`, `Bash(su:*)`, `Bash(doas:*)`, `Bash(osascript * administrator privileges*)` | Privilege escalation. Plain `osascript` and `screencapture` stay: they are how a session looks at its own screen, and how Baton sends a notification. |
| Baton's own state by named path | A session writes `~/.baton/inbox/` and nothing else under `~/.baton/`. Prevents an accident — a session rewriting the dispatch log or the archive — not an adversary, and keeps the run record trustworthy as a record. |

- **Installs are not denied.** Auto reviews them and the target's own rules govern them. A
  `permissions.ask` rule is the instrument if a park is ever wanted, and ask rules are one of the
  three routes to a held prompt under auto (§4).
- **Not denied, deliberately: writes outside the working tree.** `--restricted` would confine the
  file tools but removes Bash; `blockReadsOutsideWorkingDirectories` and `Edit(<glob>)` denies were
  weighed and dropped, because they constrain the file tools while a Bash command walks past them,
  and a background session isolates into a worktree before its first edit in any case.
- **What enforcement actually covers, stated plainly.** The deny rules are real and apply inside
  compound commands and subshells. Everything else is the target's hard rules, which a relay cannot
  enforce: Reclaim's own (never removal on real user data; Trash-first; no root outside the
  `ReclaimHelper` target) are prose in `CLAUDE.md` and part 5 of every kickoff prompt, and a
  dispatched session obeys them because it reads them, not because Baton checks.
- The `osascript` rule is expressible as a mid-command wildcard, the form the binary warns about for
  `Bash(git * main)` because it also matches options inserted before the subcommand. Whether it bites
  when the phrase sits inside a quoted `-e` argument is unverified and is a prototype item; until it
  passes, the target's hard rules carry that line alone.

#### 4. The seam: a prompt that is neither allowed nor denied

It escalates at once, the process alive and untouched, never timing out into a denial or a decision
("What stops a session, and what happens next" §5). Decided here: the shape of the seam, and what
the person sees and does.

**Under `auto` the classifier answers allow or deny; it does not ask.** Three routes to a held
prompt remain: a `permissions.ask` rule; a hook's `ask` decision, which "now floors the decision at
a prompt"; and a classifier fallback when the classifier is unavailable — the binary's "was not
reviewed: the auto mode classifier transcript exceeded its context window, and no permission prompt
is raised for this tool" implies the tools that do have a prompt fallback take it. No string shows
the classifier itself returning "ask the person" (unverified, by absence).

**So the dominant unattended event is a refusal the model works around, not a park** — and it
converts into the escalation already designed. The denial message "names the rule that blocked the
action and asks Claude to try a safer method and finish unrelated work before stopping to ask you",
so a refusal that genuinely blocks the milestone arrives as an `asking` artifact at the end of the
turn, carried by the phone message and answered by `baton answer`. Nothing new is needed for the
common case. A park is the rarer one.

**Two records, two hooks.**

- **`PermissionRequest`** fires only when Claude Code would prompt, and carries `tool_name`,
  `tool_input` and `permission_suggestions[]` — the allow rules Claude Code itself would have
  offered at the prompt, which is a better record than the premise assumed. It is injected as a
  recorder, **behind a prototype gate**: its documentation says "if no hook returns a decision, it
  denies the tool call", and its decision schema offers only `allow` and `deny` — there is no way
  for it to say "ask" explicitly. If a record-only return denies inside a `--bg` session, it cannot
  be a recorder at all, and the fallback is the `Notification` hook's `permission_prompt` type,
  which has no decision control whatsoever and costs the command text and the suggested rule. The
  gate passes before the first unattended night.
- **`Notification`** with matcher `permission_prompt` is **not** the recorder. Its message is the
  literal "Claude needs your permission to use " followed by the tool name; the string ends there
  and the tool input is not interpolated, so it reads "Bash", never the command. This is the
  measurement this ticket was told to take rather than assume, and it inverts the premise recorded
  from "What stops a session, and what happens next": that hook cannot make an escalation specific,
  and the allowlist line cannot be written from it. It is kept only as the fallback recorder above.

**How a line reaches the allowlist: `baton allow <milestone>`.**

- With `permission_suggestions[]` in the escalation record: prints the command and the suggested
  rule, then writes it verbatim and logs it.
- Without one — the classifier-denial case, which `PermissionDenied` records with no suggestion —
  it refuses to write, and prints the command verbatim, a derived prefix rule **as a proposal**, the
  permissions file's path, and one line saying why: "classifier denial; no rule was offered". The
  two cases read alike; the only difference is whether the write happens.
- `baton allow <milestone> '<rule>'` writes exactly the rule given. The proposal is read, then typed
  back, or narrowed while it is in front of the person.
- **Baton never writes a rule it composed.** The head-of-command heuristic is a fine suggestion and
  a bad writer: a rule that matches nothing looks identical to a rule not yet needed, and a rule
  that matches too much is invisible until it approves something it should not have. Neither failure
  is visible to a relay.
- **Every widening is a log event** carrying the rule, the milestone that earned it and the time, so
  the allowlist's provenance is in `status` and in the log, and the list cannot drift unnoticed.
- `baton allow <milestone> --resume` writes the rule, stops the session and resumes it: the rule is
  in force for the resumed session because the resume passes `--settings` again, and the dropped
  call is repeated by the continuation's own interrupted-tool sentence. One path serves a live
  prompt and a lost one alike, and nothing new is built for either.
- Plain `baton allow` does not unpark the current prompt: the pending call still needs answering in
  place, and the line prevents the next one.

#### 5. The channel, per class

**An escalation reaches the phone; a notification stays on the Mac.** A wait is information; a park
is a request, and only a request earns the pocket — a channel that buzzes for what cannot be acted
on stops being read.

- **Escalation**: one iMessage to the self-chat through `osascript` (Messages in iCloud syncs it to
  the phone), and one `display notification`.
- **Notification**: `display notification` and a log event; read from `status`.
- **One exception to the phone**: Baton itself having been down (below).

**The message is three parts, identical for every class** — address, content, verb:

```
Reclaim M29 · asking
Should ReclaimCore expose FileSizeFormatter, or keep it
internal and duplicate it in the app?
  1 expose (recommended)   2 internal
baton answer M29 1
```

```
Reclaim M29 · permission
wants to run: xcodebuild -scheme Reclaim \
  -destination 'platform=macOS,arch=arm64' test
allow rule: Bash(xcodebuild:*)
baton allow M29
```

The address line is scannable when several arrive; the content line is the decision, and it is the
deterministic content itself — the question with its options and recommendation, or the command with
its suggested rule — never a pointer to something that must be opened. The verb waits at the bottom
for the Mac. The first two lines are what a lock screen shows, which is why the decision leads and
the verb does not: the phone's job is deciding, the keyboard's is acting.

**Remote Control: never automatically.** It reaches only a live prompt or in-tool question in a
session still holding the call — an `asking` artifact is stopped on consume, so nothing could reach
it from a phone in any case, and a `merge-failed`, a `blocked_by` and a ladder end are all answered
at the Mac. Under auto plus an allowlist a live prompt is rare, and each one is an allowlist line
that was going to be added. Standing Remote Control would store every milestone's transcript on
Anthropic's servers every night to shave hours off that rare event. Instead: **a per-dispatch flag,
default off** — a plan-file property, `remote: true` — for the milestones chosen in advance to be
answerable from the phone. Deterministic, no judgement, and a transcript leaves the Mac only by an
explicit choice. Revisit when the first real nights measure how often a live prompt happens; if it
is frequent, the fix is the allowlist, not the channel.

**Escalations — every class that parks a lane or a project.**

| Class | Scope | Message content | `status` shows | `answer` / verb |
|---|---|---|---|---|
| `asking` artifact | lane | the question verbatim, its options numbered, the recommendation marked | parked · asking · the question's first line · the verb | `baton answer <M> <n>` (the number expands to that option's text) or `baton answer <M> "<ruling>"` |
| live row `waitingFor: "permission prompt"` | lane | the command from `tool_input`, and `permission_suggestions[]` as `allow rule:` — or, under the fallback recorder, the tool name alone | parked · permission · the command · the verb | `baton allow <M>` / `baton allow <M> --resume`; or answer in place, attached or in the app |
| live row `waitingFor: "input needed"` | lane | the row's name and milestone only — no payload carries the question, because `agent_needs_input` fires only while agent view is open in a terminal | parked · question · the row name · the verb | `claude attach <id>` to read it, then answer in place; the lane unparks on the row transition |
| third failure ending (the ladder's end) | lane | the attempt count, and the last artifact's detail or the crash sighting | parked · ladder end · attempt `<n>` · the verb | an edit to the brief or the plan, re-read on the next tick; `baton answer` if a session remains resumable |
| second consecutive `unfinished` | lane | both proposed splits | parked · unfinished ×2 · the verb | an edit to the plan — a split is a plan edit, and plan edits are a person's |
| `blocked` whose `blocked_by` is neither in flight nor eligible, or names nothing | lane | the `blocked_by` value or its absence, and the detail | parked · blocked · what it waits for · the verb | an edit to the plan, or `baton answer <M> "<ruling>"` |
| `merge-failed` | lane | the detail | parked · merge-failed · the verb | `baton answer <M> "merge resolved; finish the close-out from step (c)"` |
| `other` | lane | the detail | parked · other · the detail's first line · the verb | `baton answer <M> "<ruling>"` |
| plan-versus-advice disagreement | lane, per milestone name | the milestone named, and which direction (the plan rejects a named milestone; the session omitted a plan-eligible one) | parked · disagreement · the milestone name | an edit to the plan or the brief, re-read on the next tick |
| plan file unreadable | **project** | the path and what failed to parse | all dispatch held · plan file · the path | fix the file; the next tick re-reads |
| main not building after a merge | **project** | detection deferred (below) | all dispatch held · main broken | a fix session, dispatched — never computed in the tick (ADR 0001) |
| Baton unhealthy — a stale lock | **project** | what was found and how long it held | printed first by `status`, before anything else | clear the lock; the next tick proceeds |

**Notifications — every class Baton keeps working past. Mac only, except the last.**

| Class | Message content | `status` shows | Verb |
|---|---|---|---|
| `rate_limit` after 2 h of waiting | `error` and the error text verbatim — the only place a reset time appears | waiting · `rate_limit` · elapsed · next retry | none; the retry continues |
| `billing_error`, and the unrecoverable set, at once | as above | waiting · the `error` value · elapsed | none; a fix at the Mac (`/login`, a plan edit) is picked up by the next retry |
| transient after 1 h | as above | waiting · the `error` value · elapsed | none |
| stall (30 min of unchanged transcripts) | the row's name and its `state`, and the matching verb | in flight · stalled · the row's `state` | `state: done` → `baton answer <M>` with the finish template; `state: blocked` → the wait path by hand |
| 6 h since the attempt's latest dispatch-or-resume event | the milestone and the elapsed time | in flight · `<n>` h | none; resolved by the session's own artifact |
| a `blocked_by` wait, once | the milestone and what it waits for | waiting · blocked by `<M>` | none; resolves itself |
| prompt lost | the time the prompt was asked | parked · prompt lost | `baton answer <M> "<ruling>"`, carrying the dropped-call sentence |
| **three denials sharing a command head in one attempt** | the command head, and the `baton allow` proposal line already composed | in flight · `<n>` denials on `<head>` | `baton allow <M> '<rule>'` in the morning |
| **the classifier failing rather than judging** — the `PermissionDenied` reason names it ("temporarily unavailable", or the context-window form) | the cause, and that compaction clears it | in flight · classifier unavailable | none; the session recovers when its conversation is shorter |
| **Baton was down** — *to the phone* | how long, and what was in flight during it | the last tick's time, printed first | none |

The denial rules deserve their reasons. Every `PermissionDenied` is a log event and nothing more:
five unrelated denials over a night is a session being told no about five different things and
carrying on, which is information. **Three denials sharing a command head within one attempt** is
the different signature — a model finding a lesser way round one thing, repeatedly — so that is
what the threshold keys on, not a raw count; it notifies once per attempt and head, on the Mac, and
names the command with the proposal so the morning's fix is already composed. **The classifier
failing** is not a policy gap at all but a session degrading wholesale, so it notifies once on its
own terms regardless of count. Neither reaches the phone, and neither parks a lane: if the denials
mattered, the milestone stalls or asks, and those escalate on their own.

**Baton reporting its own absence.** A tick compares the current time against the newest event in
its own log; a gap far past the interval means Baton was not running. It reports to the phone
**only when a lane was in flight, waiting or parked during the gap** — a gap with nothing to do (the
Mac asleep after the night's work finished, a weekend) is not an outage and reporting it trains the
message to be ignored. The log knows which, because it knows what was in flight. launchd is already
the watchdog for the common failure: a tick that crashes is re-run at the next interval, so the only
silent failure is the agent being unloaded or failing to load, which is exactly what the gap report
catches when it comes back — and that is when it could be learned in any case. A second watchdog
agent was weighed and rejected: nothing watches the watcher, and at one machine the regress ends in
two failed jobs instead of one. Separately and not a mechanism: **`baton status` prints the time of
the last tick first**, which is the answer to "is it running?" at the keyboard and costs one line.

**Three live proofs the Mac side needs**, because a channel that fails silently is worse than none:
whether `osascript` can drive Messages from a launchd context at all (Automation/TCC is granted once,
interactively, and a script that works in Terminal can fail silently under launchd); whether iOS
raises an alert for a message the same account sent itself from the Mac; and whether the fallback,
Mail through `osascript`, has a configured sending account on this Mac. All three are on "Watching a
dispatched session".

#### 6. The record and the pause

**The escalation record is a dispatch-log event**, because the tick is the log's only writer. Its
fields, required of "The dispatch log" by this ticket: project, milestone, session, class, **scope**
(`lane` or `project`), what it carries (the question and its options; the command and its suggested
rule; the detail), the channel it went out on, and the time. A second event resolves it, naming how
— `ruling`, `answered in place`, or `edit` — and when. Once only per attempt and kind, as the log's
premises already require. `status` reads both and shows the open ones; nothing else is stored.

**Scope is a property of what failed, not a list of classes.** A lane escalation parks that lane;
every other lane carries on. A project escalation parks all dispatch for that project. Exactly three
things earn project scope: the plan file cannot be read (nothing can be dispatched correctly), main
does not build after a merge (nothing should be dispatched from it), and Baton itself is unhealthy.
Every class the stops taxonomy enumerated is a lane escalation — **`merge-failed` included**, because
a failed merge lands nothing: main is exactly as it was and other lanes can keep building on it. Its
global cousin is the second project-scope member, a merge that *succeeded* and left main broken.
Stated as a rule rather than a list so a later session asks "did a lane fail, or the ground under all
of them?" instead of judging a class it has not met.

The two existing global holds are not escalations and do not become stops: the usage-limit dispatch
hold is per model ("What stops a session, and what happens next" §9), and plan-versus-advice
disagreement escalates per milestone name.

**A parked lane unparks in exactly three ways**, each a log event: `baton answer` delivers a ruling;
the row leaves `waiting` because a live prompt was answered in place; or the person edits the plan
file or a brief and the next tick re-reads it. Nothing else unparks a lane, and nothing times out.

A Reclaim night under this, with one lane, is indistinguishable from stopping the night — the rule
costs nothing now and is right when v0.3 fans out.

#### 7. The ruling's return

**`baton answer <milestone> <ruling | option number>`**, resolved against **parked lanes across all
projects**. Exactly one match acts. More than one refuses and prints the candidates as
`<project>/<milestone>`, which is also the accepted long form (`baton answer Reclaim/M29 2`). A
milestone that is not parked is refused too — "nothing is waiting on M29" — so a ruling is never
delivered into a working session. The milestone is what is known at 3 a.m. and what the message
says; the session id stays in the log and in the message for the unambiguous form. Baton never
guesses between candidates, the same rule the forked-copy case already follows.

An option number expands to that option's text verbatim from the `asking` artifact before delivery,
so the session receives a ruling and never a digit.

Delivery is the path "Relay or conductor" §7 fixed: `claude stop <id>`, then
`claude --bg --resume <uuid> --settings <the dispatch settings> "<the labelled ruling>"`. **`answer`
works against a parked lane whatever the row's state**; when the row is still `waiting` it stops
first and appends the dropped-call sentence — one mechanism for a live prompt, a lost prompt and a
ruling alike, rather than a refusal to be worked around.

**The label**, matching the two continuation templates so a session meets one voice from Baton
whatever the reason:

> Baton resumed this session to deliver a ruling. `<milestone>`, attempt `<n>`, resume `<r>`. You
> asked at `<time>`: `<question>`. The ruling below is decided: do not re-open it, do not ask again,
> and do not weigh alternatives against it.
>
> `<ruling verbatim>`
>
> Continue from where the last turn ended. The handover artifact is still owed.

One sentence is added when the ruling answers a prompt the idle stop dropped — not a fourth
template, but the continue template's own interrupted-tool line: "The pending call was dropped when
the session stopped; repeat it if it is still needed."

Why this shape: the question is quoted because a session may have compacted since it asked, and a
bare ruling can land on a question the model no longer holds — a ruling that names its question
cannot be applied to the wrong one. "From the person" is dropped: a ruling has no other source, and
the glossary already says so.

**A ruling given in place needs no second ruling.** When a live prompt is answered from the Claude
app in a `remote: true` session, or by attaching, the row stops being `waiting` and the tick unparks
the lane from `claude agents --json` alone — no second ruling typed, no transcript read. That
transition is the only signal available: no `answeredBy`-style field exists in the binary's strings
or in the job record's keys, and `timeline.jsonl` records only `{at, state, detail, text}` on an
interface the documentation calls unstable. An injected `PostToolUse` marker file was weighed as a
second signal and dropped — the row transition is free, and the marker would fire on every approved
tool call. The `asking` case has no ambiguity to resolve: the tick stopped the session on consume,
so nothing but `baton answer` can reach it.

#### Evidence

- **Measured this session**, read-only. `~/.claude/settings.json` sets `permissions.defaultMode:
  auto`, and now also `inputNeededNotifEnabled: true` and `agentPushNotifEnabled: true` — both
  recorded as absent in `research/reaching-you.md`'s machine-facts table earlier the same day, so
  the mobile-push half of Remote Control is already switched on and waits only on a connected
  session and a registered mobile. It also sets `autoContinueAtUsageLimit: false`, consistent with
  Baton owning the wait, and carries an `autoMode.environment` block — auto mode's judgement is
  context-fed, which is part of why it is not the deterministic half of the policy. Reclaim has no
  `.claude/` directory at all, so no project settings file exists to merge with.
- `claude --help` (2.1.268), read locally: `--permission-mode` choices `acceptEdits, auto,
  bypassPermissions, manual, dontAsk, plan`; `--allow-dangerously-skip-permissions` "Enable
  bypassing all permission checks as an option, without it being enabled by default. Recommended
  only for sandboxes with no internet access."; `--restricted` "removes the built-in tools that run
  commands or code (Bash, PowerShell, REPL and the other code-running tools) and WebFetch unless
  `--tools` names them, and ignores user, project and local settings files (managed settings and
  `--settings` still apply) … Also confines the file tools to the working directories … refuses
  bypassPermissions"; `--permission-prompts none` documented for `--print` only.
- `/Users/danny/Documents/Apps/Reclaim/docs/DECISIONS.md` D-030 (builds and tests authorised for
  every milestone session, superseding D-016) and `CLAUDE.md` "Hard rules" (never Python; never
  removal on real user data; Trash-first; protected paths enforced in the removal engine; root code
  only in the `ReclaimHelper` target; no added dependencies) — the prose a dispatched session obeys
  by reading, which §3 does not pretend to enforce.
- `.scratch/baton/research/hooks.md` §3 (the event table: `PermissionRequest` payload `tool_name`,
  `tool_input`, optional `permission_suggestions[]`, decision schema `{behavior: "allow" | "deny"}`,
  "Fires only when Claude Code would prompt (or would auto-deny a call that cannot prompt)", "if no
  hook returns a decision, it denies the tool call"; `PermissionDenied` payload `tool_name`,
  `tool_input`, `tool_use_id`, `reason`, `retry: true`, "Auto mode only"; `PreToolUse`
  `permissionDecision` precedence `deny > defer > ask > allow`; `Notification` "can't block or
  modify notifications"; `PostToolUse` payload), §4.2 (the twelve notification types;
  `permission_prompt` fires after about six seconds, each keystroke defers it; payload `message`,
  optional `title`, `notification_type`; `agent_needs_input` and `agent_completed` fire "only while
  agent view is open in a terminal", about background sessions rather than inside them), §4.5
  (hooks in `--bg`, established indirectly), §4.6 (`--settings` precedence: managed > command line >
  local > project > user; "can set any key your user settings file can set"; hooks merge rather
  than replace).
- `.scratch/baton/research/background-sessions.md` §3 (row fields; `waitingFor` values `permission
  prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open`; "Nothing about the
  last message is carried"; `~/.claude/jobs/<id>/state.json` "are not a stable interface"), §5
  (stop-then-resume as the only route for text into a session; the `note:` copy rule), §6 (what a
  human's typing leaves behind; no "attached" flag in the JSON), §9 (the supervisor's ~1 h idle
  stop; background sessions isolate into a worktree before their first edit; credentials come from
  the supervisor).
- `.scratch/baton/research/reaching-you.md` §1 (Remote Control needs an interactive session and a
  live process; permission prompts and `AskUserQuestion` stay open until answered; push via
  `inputNeededNotifEnabled`; "While Remote Control is connected, the session transcript … is stored
  on Anthropic servers"; combination with `--bg` undocumented), §2.1 (`display notification` takes
  only body, title, subtitle and sound — no actions, no reply, no return value), §3.1 (iMessage
  through `osascript`; Messages in iCloud syncs a self-chat message to the phone; a one-time
  Automation approval is required for the calling app), §3.3 (Mail through `osascript`; a
  configured sending account unverified on this Mac), §5 (the unverified list this resolution draws
  three prototype items from).
- `.scratch/baton/research/prior-art.md` §2.3, "Where an escalation goes" (every unattended source
  keeps a durable place for things needing a person, separate from the notification, which the relay
  treats as "this lane is parked until the record is resolved"; an escalation that ages out is never
  retried silently; convert as many escalations as possible into rulings) and "Permissions for a
  session nobody is watching" (the pre-allow list in settings layered per session via `--settings`;
  the skip-permissions route used only inside a sandbox by every source that names it; Symphony's
  constraint that a permission prompt must not leave a run stalled indefinitely).
- Closed tickets this builds on: "What a project hands to Baton" §5 (the six-clause contract, which
  gains nothing here) and its Baton-side note (the injected Stop gate; escalating plan-versus-advice
  disagreement in both directions by milestone name); "Relay or conductor" §7 (stop on consume, then
  `--bg --resume` with `--settings`, the ruling verbatim and labelled) and ADR 0001 (judgement is
  dispatched as a session, never computed in the tick — which is why a broken main is a dispatched
  fix, not a decision in the relay); "What stops a session, and what happens next" §1 (the two-bit
  table), §2e (the two continuation templates this label matches), §5 (permission prompts and
  in-tool questions escalate at once, process untouched; the prompt-lost rule), §8 (what each
  stopped reason makes Baton do), §9 (the per-model dispatch hold).
- Peer session "Milestone Model Audit", from the 2.1.268 binary's strings [B] and the cached
  changelog [D]: the `Notification` permission template is "Claude needs your permission to use "
  plus the tool name, with no command interpolation [B]; `dontAsk`'s denial text [B]; `manual` as an
  alias for `default` [B]; `--bg` with bypass requiring an interactively accepted disclaimer, and
  "bypassPermissions is not authorized by this session (… or not a contained no-internet
  environment)" [B]; allow rules pre-approving in the non-auto modes and applying under auto, with
  "Improved auto mode denials: the message Claude receives now names the rule that blocked the
  action" and the `permissions.ask`-in-compound-command fix [D]; `acceptEdits` prompting before
  writing build-tool config that grants code execution [D]; the classifier answering allow or deny
  with the three prompt routes [B, D]; "Added `PermissionDenied` hook that fires after auto mode
  classifier denials — return `{retry: true}` to tell the model it can retry" [D]; the circuit
  breaker as an IDE startup fallback [B]; the classifier-context-window denial [B] and the
  "temporarily unavailable" form on very large sessions [D]; `Bash(cmd:*)` and mid-command wildcard
  deny forms with no regex form evidenced [D]; `PermissionRequest` firing inside `--bg` (changelog
  2.1.248: a background session whose `PermissionRequest` or `PreToolUse` hook printed an invalid
  answer "names the hook and the schema error on its row") [D]; the absence of any
  `answeredBy`-style field in the strings, `state.json` or `timeline.jsonl` [B, L].

#### Every numbered point, and where it landed

| Point | Outcome |
|---|---|
| 1. The permission mode, and whether a worktree differs | **Decided**: `auto` plus the allowlist, `PermissionDenied` injected; identical in a worktree. |
| 2. The allowlist and where it lives | **Decided**: Baton's `--settings` file at dispatch, composed from `~/.baton/projects/<project>/permissions.json`; the contract gains no clause. |
| 3. What stays forbidden, and how enforced | **Decided**: two deny lines; installs left to auto and the target's rules; the rest is the target's hard rules, and the limit is stated rather than papered over. |
| 4. A prompt neither allowed nor denied | **Decided**: escalates at once as already settled; `PermissionRequest` records it behind a prototype gate, `Notification` is the fallback; `baton allow` proposes and never composes. |
| 5. Where each escalated class reaches the person | **Decided**: the two tables above; phone for escalations, Mac for notifications, Remote Control only on an explicit per-dispatch flag. |
| 6. Pause semantics | **Decided**: lane by default; three named failures park a project; scope is a property of what failed. |
| 7. The ruling's return | **Decided**: `baton answer <milestone>` resolved against parked lanes across all projects; the label above; a ruling given in place unparks on the row transition. |

#### Deferred, and to which ticket

- The escalation event's fields and its resolution event, the widening event, the denial events and
  the once-only notification keys (including the new denial-head and classifier-failure keys), and
  the gap computation that reports Baton's own absence: **"The dispatch log"**.
- The `--settings` file's composition at dispatch, `remote: true` as a plan-file property, and the
  detection of the second project-scope escalation — main not building after a merge, which needs a
  builder and is therefore a dispatched session rather than anything the tick computes:
  **"Dispatching more than one at once"**.
- Every live proof, numbered below: **"Watching a dispatched session"**.

#### Unverified

- Whether a `PermissionRequest` hook that returns no decision leaves the prompt open in a `--bg`
  session, or denies the call. The whole recorder design gates on it; the fallback is recorded.
- Whether `permissions.allow`/`deny`/`ask` arrays merge or replace across settings levels, and
  whether a lower level's `deny` survives a higher level's `allow`. Two indirect signs point to
  merge (the `allowManagedPermissionRulesOnly` fix; the hook-decision precedence `deny > defer > ask
  > allow`), neither decisive. Moot under this design, and recorded so it is not rediscovered.
- Whether `permissions.deny` survives `bypassPermissions`. Not established either way; moot, since
  bypass is not used.
- Whether `PermissionDenied` also fires on a `permissions.deny` rule match, or only on classifier
  denials. The changelog wording says classifier.
- Whether a mid-command wildcard deny rule matches a phrase inside a quoted `-e` argument. The
  matcher demonstrably sees quoted-argument content for one character (`#`); that is one data point.
- Whether the classifier returns "ask the person" at all. No string shows it; asserted by absence.
- What sets the auto-mode circuit breaker, and whether it is evaluated for CLI or `--bg` sessions at
  all — its only occurrence is an IDE startup check.
- Whether `osascript` reaches Messages from a launchd context, and whether iOS alerts for a
  self-sent message. The channel's floor depends on both.
- Whether Remote Control combines with `--bg` (carried from "Reaching you when you're not at the
  Mac" §5; only relevant now for a `remote: true` dispatch).

### Observed against by "Watching a dispatched session" (2026-09-11)

Not reopened. Four premises of this decision were measured false on live `--bg` sessions; what
changes is recorded here and the detail is in that ticket's resolution.

1. **`auto` is unreachable in a `--bg` session.** `--permission-mode auto` is accepted without
   error and the session records `permissionMode: "default"` — established with a settings file,
   without one, and against `acceptEdits`/`dontAsk`, which are honoured. So "`auto` plus a
   per-project allowlist, both in the `--settings` file" cannot be delivered: the allowlist half
   travels and bites, the mode half does not.
2. **`PermissionDenied` therefore never fires.** It is auto-mode-only; the hook produced no
   record across fifteen sessions. "Every classifier refusal is logged, and it fires in auto mode
   only, which is what makes the long tail observable" has no mechanism here. The unattended
   dominant event is not a refusal the model works around — under `default` it is a held prompt
   that parks the lane.
3. **The `Notification` fallback is emptier than recorded.** The `permission_prompt` message is
   exactly `"Claude needs your permission"`, with **no tool name** and `title: null` — not the
   tool name appended, as measured here previously.
4. **`permission_suggestions[]` is not always a rule.** Four shapes observed: absent (`[]`) for
   compound commands; one `addRules` whose `ruleContent` is the *literal command string*, not a
   glob; a rule for a *different tool* (`cat <path>` → `{toolName: "Read", ruleContent:
   "//Users/danny/.aws/**"}`); and `setMode`/`addDirectories` entries that are not rules at all.
   "`baton allow` proposes and never composes" survives only if it discriminates by shape.
5. **The escalation does not reach the phone.** A self-sent iMessage arrives in the thread on the
   iPhone but raises **no alert** there; only the Mac notifies. Mail has a configured iCloud
   sending account as a fallback, untested.

What holds: the two deny lines both bite, including
`Bash(osascript * administrator privileges*)` **with the phrase inside a quoted `-e` argument**,
so that line is not a silent no-op. Deny rules are enforced under `bypassPermissions` too. Item 26
passes — a record-only `PermissionRequest` leaves the prompt open — but it only matters for a
dispatch that chooses `default`.

The chosen unattended mode is now `bypassPermissions` plus the deny list, accepted once
interactively. It never parks and its hard rules are enforced; the price is that nothing prompts,
so `PermissionRequest` and `Notification` are both silent and the channel carries only endings.

### Follow-up the same day (2026-09-11): the phone channel that does work

Since a self-sent iMessage never alerts iOS, the phone half of the channel was re-tested through
Remote Control and **works, two-way**. A `--bg --remote-control` session parked on
`AskUserQuestion` pushed a notification to the Claude mobile app, and the question was answered from
the phone twice, clearing the row within a second. Dispatch is two steps — `--bg --remote-control`
starts idle and discards the prompt, so work arrives via `claude stop` then a flagless
`--bg --resume`, which restores `--remote-control` itself.

This does not overturn "Remote Control never automatically, only a per-dispatch `remote: true`" —
the reason for that (every transcript on Anthropic's servers nightly) is untouched. It does mean the
per-dispatch opt-in is the *only* route to the phone, rather than a nicety alongside iMessage, and
that a lane which can park is a lane worth dispatching with `remote: true`.

Caveat carried from the same run: a remote-controlled session's row read
`state: "working", status: "idle", waitingFor: null` throughout one of the two parks. The row is not
a reliable park detector for these sessions.

### Amended by "The dispatch log" (2026-09-11)

Not reopened. Two of this resolution's requirements had no mechanism left by the time the log came
to carry them, and the gap report's clock moved. **`docs/DECISIONS.md` is seeded from this
resolution, so read this block before copying §4, §5 or §6 into it.**

1. **The permission-denial event is dropped, and with it both notification keys §5 defined.** §1
   injects `PermissionDenied` "so every classifier refusal is in the log", and §5 builds two
   once-only notifications on it: three denials sharing a command head within one attempt, and the
   classifier failing rather than judging. The hook is **auto-mode only**. "Watching a dispatched
   session" then measured that a `--bg` session cannot run in `auto` — the flag is accepted and the
   session records `default`, established three ways across fifteen sessions — and "Dispatching more
   than one at once" §4 chose `bypassPermissions` and dropped the hook from the `--settings` file.
   Nothing can write a denial event, so the kind, both keys and `status`'s denials line are not in
   the log's schema. **Revival condition**: a dispatch that chooses `default` (no plan-file field
   selects a mode today), or `auto` becoming reachable in `--bg`.
2. **The `permission` escalation class goes with it**, for the same reason: under bypass nothing
   prompts, so a row can never read `waitingFor: "permission prompt"` and §5's permission row cannot
   occur. **`question` stays** — `AskUserQuestion` is a tool waiting for input, not a permission, and
   `waitingFor: "input needed"` was observed repeatedly. `prompt-lost` stays for that case alone, and
   now names a closed *resolution path* rather than a dropped call ("What stops a session, and what
   happens next", amendment 5).
3. **`baton allow` loses half its design and keeps the useful half.** §4's first bullet reads
   `permission_suggestions[]` off a permission escalation, and there are none. What remains is
   `baton allow <milestone> '<rule>'`, where the person types the rule — which is the path §4 already
   preferred ("Baton never writes a rule it composed"). The route to it is unchanged in substance: a
   deny-rule refusal under bypass hands the model a refusal, the model asks, and the `asking`
   artifact names what it needed. **The `widening` event is untouched**, and remains the allowlist's
   provenance in `status` and in `baton plan`.
4. **The gap report's clock is a marker file, not the newest event.** §5 says "the newest event of
   any kind is the clock" and that no "Baton started" event is needed. A tick that consumes nothing,
   reconciles nothing and dispatches nothing writes no event, so after a quiet stretch the newest
   event is hours old while the tick has fired hundreds of times — `status` would print a last-tick
   time that is a last-event time, and the report would name the age of the last event rather than
   the length of the outage. The tick now writes **`~/.baton/last-tick`** last and atomically, and
   the gap is `now` minus that. **The rule is unchanged**: the report still fires only when the log
   shows a lane was in flight, waiting or parked during the gap, and it is still keyed so one outage
   reports once. Its channel is the Mac, like every other notification — §5's "to the phone"
   exception has had no mechanism since "Watching a dispatched session" found that a self-sent
   iMessage raises no iOS alert.
5. **The escalation and resolution events took the fields §6 asked for**, unchanged: `class`,
   `scope`, `carries`, `channel` on the escalation; `how` ∈ `ruling` | `answered in place` | `edit`
   and `escalation_at` on the resolution. A parked lane is every `escalation` with no later
   `resolution` naming it, and §6's "exactly three ways" needs no fourth — a **takeover is not a
   park**, and has its own release.
