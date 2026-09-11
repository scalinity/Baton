Title: How others already run this loop
Labels: wayfinder:research
Status: closed
Assignee: research-prior-art
Blocked by: —

## Question

Who already runs Claude Code (or a comparable coding agent) as a self-driving loop —
sessions that hand work to the next session without a person pasting prompts — and what
can Baton take from how they built it?

Start from the people and projects known to do this, then widen:

- Boris Cherny (Claude Code's creator) on how he works: many sessions at once, worktrees,
  Claude writing the prompts, no longer typing them himself. Find the primary sources —
  posts, threads, talks, interviews — not summaries of them.
- Anthropic's own engineering writing on long-running agents and harnesses: an initialiser
  session that sets up state, a coding session per unit of work, progress kept in files and
  git rather than context, and the failure modes they name (an agent declaring work done
  that is not, context running out mid-task, drift across sessions).
- Anthropic's "how our teams use Claude Code" material and the Claude Code best-practices
  guidance on agentic loops, Stop hooks and headless runs.
- Community orchestrators that chain or parallelise Claude Code sessions: tmux-based
  orchestrators, worktree managers (Claude Squad, Conductor, Crystal, Vibe Kanban and
  whatever else is current), autonomous "loop until done" techniques (the Ralph Wiggum
  loop and its descendants), Stop-hook loops that keep a session going until a condition
  holds, and Linear- or issue-driven agent loops from any vendor (OpenAI's Symphony if it
  is public, or similar).
- Jesse Vincent's Superpowers workflow (plans executed by subagents, one task per fresh
  context) for how it hands work between contexts.

For each source record: what it is; how the loop is closed — how "done" is detected, how
the next unit is chosen, how the next session is started and told what to do; how
interruptions are handled — usage limits, questions, permission prompts, crashes, a
session that stops early; how parallel work and merges are handled; what state lives
where; what it does *not* solve; the URL.

Then a synthesis: the patterns that recur across sources, the pitfalls they report from
real use, and specific ideas for Baton mapped to the open tickets by name — "Relay or
conductor", "What stops a session, and what happens next", "Where an escalation goes",
"Permissions for a session nobody is watching", "Dispatching more than one at once",
"Which model runs which milestone, machine-readably", "Watching a dispatched session".
Ideas that would need a third-party package or a hosted service are recorded but flagged,
because Baton runs on one Mac with nothing installed.

Sources are primary where they exist; cite the URL for every claim; mark anything inferred
or unverified as such. Do not start, stop, attach to or resume any Claude session. Never
use Python.

Deliver `.scratch/baton/research/prior-art.md`, and link it from this ticket's Comments.

## Comments

**2026-09-11** — Fourteen source families read, primary where one exists (Cherny's threads and
talk transcripts; Anthropic's harness, harness-design and C-compiler posts; the `/goal`,
scheduled-tasks, agent-teams and workflows docs; Huntley's Ralph and the official plugin's
stop hook; Gas Town; five tmux orchestrators; the worktree managers; Superpowers' skills and
blog; Symphony's SPEC.md; Osmani's loop-engineering post). The loop that works unattended is
always deterministic code around a fresh-context session that reads its state from files and
git, does one unit, and leaves a structured artefact; Claude-as-orchestrator is reported to
need nudges and to misreport. "Done" is never the worker's word alone (separate evaluator,
explicit signal plus heuristic, end-to-end check, tracker state). Interruptions are classified
first — transient (retry the same instruction), usage limit (wait), unrecoverable, question or
permission (never stall; park and escalate), stall, crash, ended-without-handover. Parallelism
needs disjoint file claims made live, not from a proposed list, and a serial merge step.
Findings, pitfalls and ticket-by-ticket ideas (third-party and hosted flagged):
[research/prior-art.md](../research/prior-art.md).
