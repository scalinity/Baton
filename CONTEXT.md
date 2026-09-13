# Baton

Baton carries a build from one Claude Code session to the next: it starts the session for
the next milestone with the prompt the last one left, and it deals with whatever stops a
session before that prompt exists. It exists because a person was the copy-and-paste step
between sessions.

## Language

**Baton**:
The tool, and this project. The metaphor is the thing passed between runners; what is
actually passed is the kickoff prompt.
_Avoid_: orchestrator, runner, harness

**Relay**:
What Baton is: code that runs once per tick, reads the inbox, the plan file and its own run
record, dispatches and escalates, and decides nothing a session or a person should. It embeds
no model call: judgement is dispatched as a session and returns as an artifact, never made
inline in the tick.
_Avoid_: orchestrator, conductor, daemon, supervisor

**Tick**:
One run of the relay, started on an interval or by hand, holding a lock, and remembering
nothing between runs but what the run record holds.
_Avoid_: loop iteration, poll, heartbeat

**Target project**:
A project whose milestones Baton drives. Reclaim is the first.
_Avoid_: client, workspace, repo (when the project is meant)

**Milestone**:
A unit of a target project's plan sized to one session, with a brief, dependencies and
acceptance criteria. The target project defines it; Baton only names it.
_Avoid_: task, ticket, story

**Session**:
One run of Claude Code with its own context, started by a dispatch and ended by a handover
or an interruption.
_Avoid_: agent, worker, chat, tab

**Kickoff prompt**:
The self-contained prompt that starts a milestone's session, in the target project's fixed
seven-part anatomy. It lives in the milestone's brief; its part 2 is the slot line.
_Avoid_: task, instruction, spec

**Recovery clause**:
The part of a kickoff prompt that lets a fresh session resume a part-done milestone from
the brief's completion evidence instead of starting over.

**Handover**:
What a session produces last: the milestone it worked, its outcome, and — when complete —
every eligible milestone with a disposition and a pointer to its brief. Its machine-readable
form is the *handover artifact*; its printed form is that artifact, verbatim.
_Avoid_: handoff (in Reclaim that is the completion-evidence write-up appended to a brief —
a different thing), output, result

**Eligible set**:
The milestones whose dependencies are all complete, by the plan file's graph. Baton computes
it; a handover lists it with a disposition per milestone.

**Conflict check**:
The judgement of which eligible milestones may run at once, made from each brief's expected
files — and, because those lists are proposed rather than exhaustive, from what the brief
says elsewhere.

**Lane**:
Milestones that must run one after another. Lanes run beside each other.

**In flight**:
A milestone whose session is running.

**Dispatch**:
Baton starting a session for a milestone: name, model and worktree chosen, the kickoff
prompt delivered.
_Avoid_: spawn, launch, kick off

**Allowlist**:
The tool patterns a target project's sessions may use without asking, together with the ones they
may never use. Baton holds one per target project and hands it over at dispatch; only a person
widens it.
_Avoid_: permissions, whitelist, policy

**Dispatch settings**:
What Baton hands a session at dispatch beside its prompt: the permission mode, the project's
allowlist, and the hooks Baton injects. The same thing is handed over again on every resume.
_Avoid_: config, profile, overrides

**Interruption**:
Anything that stops a session being productive before its handover exists: a usage limit, a
question, a permission prompt, a crash, or a turn that ended without a handover.
_Avoid_: error, failure, block

**Escalation**:
An interruption Baton hands to the person and stops acting on: the lane is parked until a
ruling or an edit resolves it. A notification is not one.
_Avoid_: alert, notification

**Notification**:
A message to the person that Baton keeps working past: the session runs on, or the retry
continues.
_Avoid_: alert

**Mac message**:
How an escalation or a notification reaches the person at the Mac: one banner under the sender
"Baton" with Claude's icon, whose click opens the session it is about in Claude.app. It is posted by
the *notifier applet*, `Baton.app`, which the install builds; Baton hands it each message through
the applet's spool, and the applet keeps the newest message's session as the *target* a click opens.
The spool is the applet's and holds nothing but messages; handover artifacts wait in the inbox.
_Avoid_: alert, toast, popup

**Ruling**:
A person's answer to an asking session, delivered verbatim as its next instruction and
labelled so the session treats it as decided.
_Avoid_: reply, feedback, hint

**Parked**:
What a lane is once an escalation belongs to it: Baton has stopped acting on it. A parked lane never
times out into a decision. Three things release it — a ruling, a prompt answered in place, or a
person's edit that the next tick re-reads — and nothing else.
_Avoid_: blocked, paused, stalled, on hold

**Takeover**:
A person typing into a dispatched session's own conversation, rather than answering through Baton.
Baton stops acting on that lane while one is in progress and never prompts over a person. Nothing
in the session marks one, so Baton recognises a takeover by the newest message in a session — typed
at a terminal, or sent from Claude.app or the phone through Remote Control — being one it did not
itself send. Not a park: a parked lane waits for a decision, a taken-over lane
waits for the person already making it.
_Avoid_: interrupt, override, manual intervention

**Escalation record**:
What Baton keeps of an escalation: the milestone, the class, what was asked, and the verb that
resolves it. A notification points at it and `status` shows it; it is resolved, never deleted.
_Avoid_: ticket, alert, incident, inbox

**Escalation scope**:
How far an escalation parks. A *lane escalation* parks its own lane and the others carry on; a
*project escalation* parks every lane of that project. Scope is a property of what failed — one
milestone's session, or the ground under all of them — never of the class.
_Avoid_: severity, priority, level

**Project contract**:
The short list of things a target project's `CLAUDE.md` makes its sessions do so that Baton
can drive the project. Reclaim is the first implementer.
_Avoid_: protocol, API, integration, spec

**Handover artifact**:
The machine-readable handover a session writes last: the milestone it worked, its outcome,
and each eligible milestone with a disposition. One file per handover; the printed handover
is this file, verbatim.
_Avoid_: next.json, manifest, report

**Outcome**:
How a session ended, as its handover artifact states it: complete, asking, or stopped.
_Avoid_: status, result, exit reason

**Disposition**:
What a handover says about one eligible milestone: run, wait for a named milestone, or held
by a gate.
_Avoid_: state, verdict, decision

**Gate**:
A hold on the plan that only a person clears, such as a release gate. It lives in the plan
file; a handover mirrors it.
_Avoid_: freeze, lock, blocker

**Plan file**:
The target project's plan as Baton reads it: the milestone table a person edits, holding for
each milestone its dependencies, model, effort, whether it is remote, and its status, plus the
gates and each gate's cleared state. The project's `CLAUDE.md` names it. One source for the
graph, never two.
_Avoid_: manifest, roadmap, config, orchestration file

**Standing check**:
The build or test a target project's `CLAUDE.md` says every session runs. The close-out runs it
on `main` after the merge, for the combined tree.
_Avoid_: CI, pipeline, health check

**Inbox**:
Where handover artifacts wait for Baton. A handover leaves it when Baton acts on it.
_Avoid_: queue, spool (that is the notifier applet's, under Mac message), drop folder

**Slot line**:
The one fixed paragraph in a brief's prompt where "what else is in flight" goes: a label and
one sentence. Baton replaces it whole at dispatch; a person leaves it as written.
_Avoid_: placeholder, template variable

**Refresh**:
The finishing session's update of each successor brief's prompt, made on the main branch
after its own merge, so that the brief a handover points at is current.
_Avoid_: rewrite, regenerate

**Dispatch log**:
Baton's record of every dispatch it made and how each ended. With the archived handovers it
is the run record.
_Avoid_: history, audit log

**Event**:
One line of the dispatch log: something the tick did, or something it saw and acted on. The tick is
the only thing that writes one.
_Avoid_: entry, log line, record (that is the run record)

**Envelope**:
The fields every event shares: when it happened, what kind it is, and which project, milestone,
session and attempt it belongs to. A field an event has no value for is absent from it, never empty.
_Avoid_: header, metadata, schema

**Archive**:
Where a handover goes once Baton has acted on it. Half of the run record.
_Avoid_: done folder, history

**Repeat**:
A handover delivered to the inbox again after Baton acted on it: the same artifact, to the last
field, from the same session. It goes to the archive beside the first with a line saying so, and
nothing follows from it, because a handover is acted on once. A session's second, different artifact
is a second handover, not a repeat.
_Avoid_: duplicate, replay, retry

**Run record**:
Everything Baton knows about what ran: the archive and the dispatch log together.
_Avoid_: ledger, history

**Status feed**:
What a dispatched session reports about itself as it works: how much of each usage limit it has
spent and when that limit resets, how much of its context it has used, and what it has cost. One
per session. The fleet view carries none of it.
_Avoid_: telemetry, metrics, status line (that is the mechanism, not the thing)

**Rejected**:
A handover artifact Baton refused to act on. It keeps its reason and is escalated, never
skipped.
_Avoid_: invalid, failed

**Stop gate**:
The check Baton attaches to a session it dispatches so that the session cannot end a turn
without a handover artifact: it insists once, then records the stop itself.
_Avoid_: stop hook (that is the mechanism, not the thing), guard

**Attempt**:
One session's run at a milestone, numbered per milestone from the first dispatch. A redispatch
starts the next attempt; a resume continues the same one.
_Avoid_: retry, try, run

**Continuation**:
The instruction a resumed session receives from Baton: why it stopped and what to do next —
continue, or finish the close-out. A ruling is not a continuation.
_Avoid_: nudge, re-prompt

**Wait**:
Baton's timed pause before resuming a session stopped by a temporary API error. It spends no
attempt.
_Avoid_: backoff, sleep, retry loop

**Stall**:
A running session whose transcripts — its own and its subagents' — have not changed for longer
than the stall threshold.
_Avoid_: hang, timeout, freeze

**Failure ending**:
An ending Baton counts on the ladder: a turn ended without a handover artifact, a process gone, or
a session that cannot be resumed. A wait is not one; an artifact the session wrote itself is not
one.

**Ladder**:
The fixed sequence for consecutive failure endings on one milestone: resume, then redispatch, then
escalate.
_Avoid_: retry policy, backoff

**Cap**:
The most sessions Baton keeps in flight at once across every target project. A property of the
Mac, not of a project. A parked lane holding a live prompt counts; a stopped asking session does
not.
_Avoid_: concurrency limit, worker pool, slots

**Hold**:
Baton not dispatching on a model, or on every model, while a usage-limit wait is active. Not an
escalation; it lifts when the wait clears.
_Avoid_: pause, freeze, throttle

**Reserve**:
The share of the account's seven-day usage window Baton leaves for the person's own sessions: at
or above it, no new Fable milestone is dispatched. Opus lanes and sessions already in flight are
unaffected.
_Avoid_: budget, quota cap, rate limit

**Milestone worktree**:
The worktree Baton creates beside the canonical checkout for one milestone's session, on that
milestone's branch from `main`. Every milestone has one; a redispatch reuses it. It outlives the
milestone: the session merges from it and leaves it in place, because a session whose working
directory is gone cannot be resumed.
_Avoid_: sandbox, checkout (when the worktree is meant), isolation

**Remote Control**:
Claude Code's link between a session running on this Mac and claude.ai: it is what lists the session
in Claude.app and on the phone and lets a person read it and type into it there. Every dispatched
session has it, turned on by the settings file Baton composes; while it is connected, the transcript
is stored on Anthropic's servers. A milestone marked `Remote: yes` is one whose questions are
expected to be answered from the phone, so the tick does not read its row as a park.
_Avoid_: phone mode, mobile session, remote session (when a `Remote: yes` lane is meant)

**Finished session**:
The session of a milestone whose `complete` handover Baton has acted on. Its lane is closed and its
hooks stand down, but its conversation stays worth going back to. Its process is kept while it is one of
the few most recently active; an older one is taken offline once idle and woken on the person's word.
_Avoid_: dead session, old session, archived session (claude.ai's word for a state, not this)

**Wake session**:
The one always-on Remote Control session, `Baton · wake`, that a person messages from Claude.app or the
phone to reach a finished session that has gone offline; it runs `baton wake` with their words, and the
woken session answers in its own thread. The tick keeps it running once anything has gone offline.
_Avoid_: concierge, dispatcher, bot

**Self-check**:
The first thing a tick does for each target project: read the plan file and ask git for `main`'s
head. A failure parks the project.
_Avoid_: health check, preflight, probe

**Plan override**:
The tick dispatching, or not, against a handover's disposition because the plan's gates say
otherwise. Recorded, never escalated: a gate is a person's act and the newer word.
_Avoid_: conflict, disagreement (that term is reserved for the two cases that escalate)

**Verb**:
One of the things the `baton` script does when run by hand or by launchd: `tick`, `answer`,
`status`, `plan`, `dispatch`, `allow`, `wake`. Every verb runs under the same lock and writes the log
through the same code path.
_Avoid_: command, subcommand, mode

**Prompt sidecar**:
The file holding the exact text of one prompt Baton delivered, at `~/.baton/prompts/<session>/<n>.txt`,
pointed at and hashed by the event that delivered it. The log's own overflow, not a thing beside it.
_Avoid_: prompt log, prompt cache

**Copy fork**:
A resume that started a copy of a session under a new id instead of continuing it. The copy carries
the same attempt; the original is stopped; the log records both ids.
_Avoid_: duplicate session, clone

**Tick marker**:
The one-line file `~/.baton/last-tick`, written last and atomically by a tick that completed. The
tick's clock: the gap report and `status` read it, never the newest event.
_Avoid_: heartbeat, timestamp file

**Gap report**:
The notification that Baton was not running for a stretch during which a lane was in flight,
waiting or parked. Measured against the tick marker; a gap with nothing to do is not one.
_Avoid_: outage alert, downtime

**Fixture project**:
A throwaway git repository with a plan file, briefs and an inbox, built by a test so the tick can be
run against it and the directory diffed afterwards. Never a real target project.
_Avoid_: mock project, sandbox

**Installed relay**:
The copy of Baton's scripts under `~/.baton/bin/` that launchd runs and that dispatched sessions'
hooks call. A Baton milestone's close-out runs the install script on `main` once the standing check
has passed there, so a milestone can never break the tick that dispatched it, only the next one,
and only with a `main` the standing check passed.
_Avoid_: deployment, release

**Bootstrap**:
How Baton is built: M01 by hand, and every later milestone dispatched by the Baton that exists so
far, with a hand-run verb until the tick exists and by the tick after that. Each milestone needs
only what earlier ones built in order to be dispatched.
_Avoid_: dogfooding, self-hosting

**Project key**:
The word that names a target project everywhere in Baton: the basename of its canonical checkout,
never a session's `cwd`. It keys `~/.baton/projects/<project>/`, the session name, the log's
`project` field and the long form `baton answer <project>/<milestone>`.
_Avoid_: project id, slug
