Title: Which model runs which milestone, machine-readably
Labels: wayfinder:grilling
Status: closed
Assignee:
Blocked by: 01

## Question

Where does the model per milestone live, so that Baton can pass `--model` at dispatch
without a human reading a page?

Candidates: a `Model` column in the target's `docs/MILESTONES.md`; an `orchestration.json`
beside `ORCHESTRATION.html`, which today holds the allocation only as HTML (4 Fable, 11 Opus
across Reclaim's remaining fifteen); or the handover artifact itself, the finishing session
choosing per the rack's rule — spend the scarce model by marginal value: no precedent to
copy, later work inheriting the decision, or a step that cannot be undone.

Decide also:

- What Baton does when the Fable limit is hit with a Fable milestone next: wait for the
  reset (the rack never downgrades a Fable milestone silently), or dispatch Opus and record
  that it did.
- That Baton records which model ran which milestone. The benchmark practice — grading a
  milestone's output against the house standard without being told which model wrote it —
  needs the answer written down somewhere the grader does not look until after. This is the
  run record's first required field (fogged: "State Baton keeps between events").
- Whether `--effort` is part of the routing.

`--model` accepts the aliases `fable`, `opus`, `sonnet`, `haiku`.

### Premises settled by "What a project hands to Baton" (2026-09-11)

The plan file exists; its shape is decided here. It is named by the project's `CLAUDE.md` and
holds every milestone, its dependencies, and the gates with each gate's cleared state; a gate is
cleared only by a person's edit committed with a decision entry; one source for the graph, never
two — so either `docs/MILESTONES.md`'s table is the plan file, or the table derives from it. The
handover artifact carries no model: the allocation lives with the plan, a finishing session that
learns the plan is wrong edits it at refresh time with its reason, and Baton's dispatch log
records what actually ran and why it differed. Decide here: the plan file's format and location;
whether model and effort ride along; how Baton knows a milestone is complete for milestones that
predate Baton (a status per milestone, or the brief's completion evidence); how a gate and its
cleared state are written; and what Baton does when the Fable limit is hit with a Fable milestone
next. The run-record field for the model actually run now belongs to "The dispatch log".

## Comments

### Merged — 2026-09-11

Folded into "Dispatching more than one at once" (`09-dispatching-more-than-one-at-once.md`), as
"The file" of its Question, by "Relay or conductor": the plan file's shape is the input the dispatch
reader consumes, and one conversation keeps the file from carrying fields the reader cannot use.
The one-source-for-the-graph crux and Symphony's `WORKFLOW.md` front matter as the precedent to read
first travelled with it. Nothing was decided here.
