# Baton

Baton carries a build from one Claude Code session to the next: a relay, shell only, run by launchd
every sixty seconds on one Mac, that reads its inbox, its dispatch log, a target project's plan
file and one git check, then dispatches, resumes, waits and escalates by fixed rules. It embeds no
model call. It drives any project that implements `CONTRACT.md`; Baton implements it on itself,
and this file is that implementation. Planning documents are the source of truth; code follows
them. The vocabulary is `CONTEXT.md`.

## Start every session here

1. Read `CONTEXT.md`, then `CONTRACT.md`.
2. Read the active milestone brief in `docs/milestones/` in full.
3. Read the sections of `docs/SPEC.md` and `docs/ARCHITECTURE.md` the brief's §3 names, and the
   decisions it lists.
4. If the relay is installed, run `baton status`; read `docs/MILESTONES.md`'s table for what is
   `done`. There is no `docs/STATUS.md` (D-023): the plan file's `Status` column, the briefs'
   completion evidence and `baton status` are the state.
5. Inspect the working tree and the existing scripts before writing anything.
6. Implement only the active milestone. Do not start the next one.
7. Close out per the brief's prompt and "Handing over" below.

## Handing over at the end of a milestone

The method is `CONTRACT.md` clause 3, applied to this repository.

1. After the milestone's own checks, `/review-2` and `/address`: completion evidence into the
   brief under `## Completion evidence` using the `docs/MILESTONES.md` template, the
   `docs/DECISIONS.md` entries, the `docs/ARCHITECTURE.md` §10 row; commit on the branch.
2. Merge into `main`. If the merge fails, write a `stopped` artifact with reason `merge-failed`
   and go no further. Then run the standing check, `sh tests/run.sh`, on `main`; fix `main` if it
   fails, else write `stopped` with reason `main-broken`.
3. On `main`: refresh the copy-ready prompt only of a listed milestone with neither an open lane nor an open park (parts 1 and
   3–7; part 4 additively; part 2 stays the slot line). Establish open lanes and open parks
   by `baton status` and the dispatch-log check in `CONTRACT.md` clause 3(c); absence from status
   does not prove closure. Still name every eligible milestone with its correct disposition; write
   `done` in this milestone's `Status`
   cell in `docs/MILESTONES.md`; correct the plan file if this session learned it is wrong, with a
   decision entry; leave the session's worktree in place — its path is the one the
   dispatch printed, not a path derived from the milestone's name — so the session can be resumed
   later; commit. Then run `BATON_HOME=/Users/danny/.baton sh install.sh` from the canonical
   checkout, so the tick that consumes this handover and dispatches the next milestone runs the relay
   just merged (D-079); the home is named because a session inherits the background service's
   environment, which can carry another home's `BATON_HOME` (D-091). The
   script never replaces an installed launchd agent that differs from `launchd/com.baton.tick.plist`
   and never loads one: if it prints that the agent differs, quote the line in the completion
   evidence and the final message, because copying the agent and reloading it is a person's act.
4. Write `~/.baton/inbox/M<nn>-$CLAUDE_CODE_SESSION_ID.json` — `.tmp` first, then rename — per
   `CONTRACT.md` clause 4: `baton: 1`, `project` `/Users/danny/Documents/Apps/Baton` (the canonical
   checkout, never the worktree), `milestone`, `session`, `outcome`, `merged_as` (the merge commit
   on `main`), `written_at`, and `eligible[]` with one entry per milestone the plan now makes
   eligible, each with a disposition and its brief pointer. This plan has one lane, so that is one
   entry, or none after M08. A session that cannot finish writes `asking` or `stopped` instead,
   with the fields clause 5 names.
5. Print the file verbatim, last, in a fenced block whose info-string is `baton`. If anything
   lands after it, deal with that and print it again.

M01 is the one session started by hand, on `main`, with no worktree and no injected gate: the
contract in this file alone makes it write the artifact. From M02 on, every session is dispatched
by Baton into its milestone worktree on branch `m<nn>`, with the Stop gate injected. A new worktree
is created at `~/.baton/worktrees/Baton/M<nn>`; one the milestone already has is used where git has
it registered, which is what the dispatch's own `worktree` line names.

## What a kickoff prompt contains

Seven parts, in this order, one code block, copy-ready, no commentary inside it. It is run by a
session that remembers nothing of the one that wrote it.

1. **Identity and scope.** The milestone, `/Users/danny/Documents/Apps/Baton`, and the one line
   that never changes: Baton is a relay, a personal tool for one person on one Mac, on Claude Code
   2.1.270, that carries a build from one Claude Code session to the next; a launchd-run tick
   every sixty seconds; it embeds no model call.
2. **What else is in flight.** Exactly one paragraph, verbatim: `WHAT ELSE IS IN FLIGHT. Runs
   alone unless the dispatch says otherwise.` Baton replaces it whole at dispatch with the
   worktree, the branch, the canonical checkout, the other milestones in flight, the attempt
   sentence, the staging rule and the refusal. A person leaves it as written.
3. **Startup order.** This file, `CONTEXT.md`, `CONTRACT.md`, the brief in full, the sections its
   §3 names, the previous brief's completion evidence; then the working tree. The recovery clause:
   if the brief's completion evidence is non-empty or the milestone's files exist, follow its
   Recovery procedure and resume only the unfinished part.
4. **What to settle rather than inherit.** The open questions the milestone owns, each carrying its
   evidence — the prototype file, the observed string, the requirement id — and the facts the
   session does not re-derive.
5. **Constraints.** Never Python; shell only (`/bin/sh` with `set -eu`, `jq -e`, `awk`, git); no
   packages; the standing check is `sh tests/run.sh`; never touch Reclaim; which sessions, if
   any, the milestone may start; a question for the person is asked in the session with
   `AskUserQuestion`, never as an `asking` artifact the milestone could have avoided; the log has
   one writer; every resume is flagless; stage by name,
   never `git add -A`; commit locally, neutral voice, no trailers; the next free D-number at the
   moment it is written.
6. **Verification.** Point at the brief's §8; an unrun check is never reported as passed.
7. **Close-out, numbered.** `/review-2` with a hand pass, `/address`, the handoff, the merge and
   the standing check on `main`, the refresh and `done`, the refusal to start the next milestone,
   the split rule, and last the handover artifact written and printed.

Second person, imperative, no preamble. Every instruction that is not self-evident carries its
reason.

## Hard rules

- **Never use Python** for anything in this project.
- **Shell only, no packages.** `/bin/sh` with `set -eu`, `jq`, `awk`, git and the claude binary at
  `/Users/danny/.local/bin/claude`. No build step. A structure `jq` cannot express, or a file past
  a few hundred lines, is the named moment for a Swift command-line tool (D-005), recorded as a
  decision first.
- **The tick embeds no model call** (ADR 0001, D-001). Judgement is dispatched as a session and
  returns as an artifact.
- **Never touch a target project's code.** Reclaim is read, never written; no session is dispatched
  into it before M16, which onboards it, and no Baton session edits it ever. A plan that does not
  parse is reported. `baton onboard` does not write a target repository either: a plan it cannot read
  strictly is adapted in the registration, never in the project's own document (D-156).
- **The deny list is the safety rail.** Dispatched sessions run under `bypassPermissions`; the two
  deny classes in `docs/SPEC.md` REQ-PERM-04 are what stops a session escalating privileges or
  rewriting Baton's own record. A session writes `~/.baton/inbox/` and nothing else under
  `~/.baton/`, except through `sh install.sh` at close-out, which writes the installed relay.
- **Ask in the session.** A question for the person is put with `AskUserQuestion` in the session
  itself: Remote Control pushes it to the phone, the tick parks the lane as `question` with the Mac
  message, and the answer given in Claude.app releases it with the session still running. An `asking`
  artifact is consumed by stopping the session, which archives it on claude.ai and leaves the question
  readable only in JSON, so it is only for a question asked as the turn ends (D-089).
- **The log has one writer**, one function, under the lock. Hooks write per-session files.
- **Every resume is flagless.** Any flag on `--bg --resume` forks a copy.
- **Never start, stop, attach to, respawn or resume a session** except the fixture-project sessions
  a brief names, and never one named `Baton · Reclaim · …`.
- **Builds and tests are shell fixtures.** `sh tests/run.sh` is authorised for every session; every
  check is reported as passed, failed or unrun with its output. `sh install.sh` is authorised at
  close-out, on `main`, once the standing check has passed there.
- Commits use the existing git identity; no authorship trailers; neutral technical voice; never
  address a person. Specs state the current design only; `docs/DECISIONS.md` holds the history.

## Documents

| File | Holds |
|---|---|
| `CONTRACT.md` | The six-clause project contract, once; the artifact by example |
| `CONTEXT.md` | The glossary every document uses |
| `docs/SPEC.md` | Requirements (REQ-*) by family, each citing its ticket; what Baton never does; invariants; verification; setup facts |
| `docs/ARCHITECTURE.md` | The files under `~/.baton/`, the tick's eight steps, the hooks, the verbs, the states, the log's events and derivations, the seams, interfaces by milestone |
| `docs/DECISIONS.md` | Dated decisions with rationale; the next free number |
| `docs/MILESTONES.md` | **The plan file**: the milestone table and the gates table `baton plan Baton` parses; the rules for every session; traceability; the split rule; the handoff template |
| `docs/milestones/M<nn>.md` | Per-milestone brief, `## Completion evidence`, `## Copy-ready session prompt` |
| `docs/adr/` | ADR 0001 |
| `launchd/` | `com.baton.tick.plist`, the one agent; `install.sh` copies it and a person loads it |
| `.scratch/baton/` | The wayfinder map, its tickets, the research and the prototype's evidence — read-only history |
