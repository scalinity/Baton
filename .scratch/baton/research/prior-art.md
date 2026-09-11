# Prior art: how others already run the loop

Ticket: `.scratch/baton/issues/13-how-others-run-the-loop.md`. Researched 2026-09-11.

Method. Primary sources (the person's own post, the repo README or spec, the official
engineering post or docs page) were fetched in full where the site allowed it; secondary
write-ups are used only where the primary is a recording that was not fetched, and are
labelled as such. Every claim carries its URL. Dates are the page's own; where a date is
derived (from a tweet id or a commit) it is marked *inferred*. Nothing was run, started,
attached to or resumed; no Python was used.

Terms follow `CONTEXT.md`: session, milestone, kickoff prompt, handover, dispatch,
interruption, escalation. Where a source uses "orchestrator", "harness" or "agent" for the
thing Baton calls a session or a dispatch, the source's word is kept inside quotes only.

Facts already established on the map (`--bg`, `claude agents --json` fields, hook payloads,
transcript format, Remote Control) are not re-derived here; sources that touch them are
cross-referenced to `research/background-sessions.md`, `research/hooks.md` and
`research/reaching-you.md`.

---

## 1. Sources

Each source records: what it is; how the loop is closed (how "done" is detected, how the
next unit is chosen, how the next session is started and told what to do); how
interruptions are handled (usage limits, questions, permission prompts, crashes, early
stops); parallel work and merges; where state lives; what it does not solve; URLs.

### 1.1 Boris Cherny — own posts and talks

**What it is.** The Claude Code creator's published account of his own workflow, in four
X threads (January–March 2026) and several talks (June–July 2026). The threads are primary
and were read in full on unroll mirrors; the talks were not fetched as recordings, so their
quotes are cited through the transcripts and write-ups that carry them.

**Closing the loop.**
- January 2, 2026 thread: 5 Claudes in numbered terminal tabs plus 5–10 on claude.ai/code,
  with system notifications "to know when a Claude needs input"; sessions start in plan
  mode and switch to auto-accept once the plan is right; for very long-running tasks either
  "(a) prompt Claude to verify its work with a background agent when it's done, (b) use an
  agent Stop hook to do that more deterministically, or (c) use the ralph-wiggum plugin";
  and "the most important thing … give Claude a way to verify its work" (claimed 2–3× quality).
  https://threadreaderapp.com/thread/2007179832300581177.html (date from the embedded
  tweet: https://patrickarobinson.com/blog/how-the-creator-of-claude-code-uses-claude-code/).
- Team-sourced tips thread (id 2017742741636321619; *inferred* early February 2026 from the
  id's snowflake timestamp): "Spin up 3–5 git worktrees at once, each running its own
  Claude session in parallel. It's the single biggest productivity unlock"; some team members
  name worktrees and alias them (`za`, `zb`, `zc`); some keep a dedicated read-only
  "analysis" worktree. https://threadreaderapp.com/thread/2017742741636321619.html
- Worktree announcement thread (id 2025007393290272904; *inferred* late February 2026):
  `claude --worktree` (name it or let Claude name it), `--tmux` to launch in its own tmux
  session, subagents with `isolation: worktree` in their frontmatter.
  https://threadreaderapp.com/thread/2025007393290272904.html
- March 30, 2026 "15 hidden features" thread (primary on X; not fetched — content as
  reported by a same-day summary and The Neuron): `/loop` and `/schedule` run a prompt on
  an interval "for up to a week"; his own loops are `/loop 5m /babysit` (auto-address review,
  auto-rebase, shepherd PRs), `/loop 30m /slack-feedback`, `/loop /post-merge-sweeper`,
  `/loop 1h /pr-pruner`; "dozens of Claudes running at all times", each in a worktree
  (`claude -w`); `/batch` interviews then fans out to worktree agents that each open a PR.
  https://github.com/shanraisshan/claude-code-best-practice/blob/main/tips/claude-boris-15-tips-30-mar-26.md
  ; https://www.theneuron.ai/explainer-articles/-claude-codes-creator-just-dropped-his-15-favorite-power-features-most-people-dont-know-about-/
- June 2, 2026 (Acquired Unplugged, hosted by WorkOS) and June 19, 2026 (Meta @Scale
  fireside; video posted the same day): "I don't prompt Claude anymore. I have loops that
  are running. They're the ones that are prompting Claude and figuring out what to do. My
  job is to write loops." He uninstalled his IDE in November 2025; "100% of my code has been
  written by Claude Code" since Opus 4.5, most of it from his phone; two persistent
  subagents run against his own code (one improving architecture, one unifying duplicated
  abstractions), each opening PRs and never reaching a clean stopping point because the code
  keeps moving. Reported by https://gof.art.blog/2026/06/08/wtf-is-a-loop-peter-steinberger-vs-boris-cherny/
  , https://officechai.com/ai/i-now-just-write-loops-to-prompt-claude-code-claude-code-creator-boris-cherny/
  , https://aintelligencehub.com/articles/claude-code-loops-2026 and
  https://thenewstack.io/loop-engineering/ (June 10, 2026). Business Insider (not fetched)
  is quoted as: "It's an agent that prompts Claude. I don't write the prompt anymore. Claude
  writes the prompt and now I'm talking to that new Claude that is coordinating."
  https://www.livemint.com/ai/artificial-intelligence/stop-prompting-why-anthropic-co-founder-says-the-way-we-talk-to-ai-is-already-obsolete-11782056172011.html
- Startup School 2026 (YC "Root Access" transcript, July 27, 2026): "Loop is essentially a
  cron job that's running locally for Claude. Routine is the same thing, but it's running in
  the cloud"; a dynamic workflow "is one task and you break it up into chunks", loops and
  routines are "one task that is repetitive that doesn't share context, but it might share
  memory"; 20–30 routines per day maintain Claude Code's own codebases (dead-code cleanup,
  duplicate-abstraction unification), each a one-sentence prompt; "you don't need slash goal.
  You don't need slash loop. These help. But really all you need is give the model the task,
  give it a way to verify the output of its work so it doesn't get stuck and it'll just go."
  https://www.ycrootaccess.com/p/boris-cherny-building-claude-code
- June 9, 2026 interview with Cat Wu (The Neuron write-up): the old setup was "six terminal
  tabs and six checkouts"; now the desktop app clones worktrees and `claude agents` (agent
  view) is "one screen showing every session, its state, and which ones need your input";
  Remote Control from the phone; routines were "the first obvious use of the Agent SDK": code
  review, PR babysitting, CI fixes, rebasing; "context minimalism" — minimal system prompt,
  minimal tools, a way to pull context.
  https://www.theneuron.ai/explainer-articles/claude-code-creators-boris-cherny-and-cat-wu-explain-how-to-use-agent-loops/

**Interruptions.** Permission prompts: he does not use `--dangerously-skip-permissions` day
to day; he pre-allows safe commands via `/permissions`, checked into `.claude/settings.json`;
for unattended long runs "either `--permission-mode=dontAsk` or `--dangerously-skip-permissions`
in a sandbox … so Claude can cook without being blocked on me" (January thread). Questions:
notifications tell him which tab needs input (January thread); by June the answer is agent
view plus Remote Control from the phone (Neuron write-up). Usage limits, crashes, early stops:
not addressed in any of these sources.

**Parallel work and merges.** Worktrees or separate checkouts per session; merges happen
through PRs that loops babysit (`/babysit`, auto-rebase). No description of how two of his
sessions avoid the same files beyond "one task per worktree".

**State.** Git and PRs; `CLAUDE.md` checked in and edited whenever Claude errs; slash
commands in `.claude/commands/`. No run record is described.

**Not solved (from these sources).** A handover from one session to the next: every loop
he describes is a *standing* job on a schedule (babysit, sweep, prune), not a milestone
chain where session N writes session N+1's prompt. Overnight quota. Which loop owns a
failure.

### 1.2 Anthropic engineering — "Effective harnesses for long-running agents" (Nov 26, 2025)

**What it is.** Justin Young's write-up of the two-prompt harness for the Claude Agent SDK
that builds an app across many context windows, with a quickstart. Primary; read in full.
https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

**Closing the loop.** Two prompts, one harness: the *initializer* (first session) writes
`init.sh`, `claude-progress.txt`, `feature_list.json` (200+ end-to-end features, all
`"passes": false`) and the first commit; every *coding* session then runs `pwd`, reads the
progress file and `git log`, reads the feature list, starts the dev server via `init.sh`,
re-tests basic functionality end to end, then picks "the highest-priority feature that's not
yet done" and works on that one only. "Done" for a feature is the agent flipping `passes`
after end-to-end testing with a browser tool; "done" for the project is the feature list
being exhausted. The next session is the same coding prompt again on a fresh context; the
quickstart auto-continues after a 3-second delay, `Ctrl+C` pauses, re-running the same
command resumes (https://github.com/anthropics/claude-quickstarts/blob/main/autonomous-coding/README.md).

**Interruptions.** Context running out mid-feature is the named failure; the answer is
"one feature at a time" plus a clean state at session end (commit, progress note). Questions
and permission prompts do not arise: the quickstart runs the SDK with an OS sandbox and a
bash allowlist hook (`security.py` — Python, not adoptable as code). Usage limits and crashes
are not discussed.

**Parallel work and merges.** Single agent, single checkout. "Future work" asks whether a
multi-agent architecture (testing agent, QA agent, cleanup agent) would beat one general
agent.

**State.** `claude-progress.txt` (narrative), `feature_list.json` (the only state the
agent may edit, and only its `passes` fields), git history. JSON was chosen over Markdown
because "the model is less likely to inappropriately change or overwrite JSON files".

**Failure modes named.** (1) Trying to one-shot the app and running out of context, leaving
a half-implemented, undocumented feature — "this happens even with compaction". (2) A later
session looking around, seeing progress, and declaring the job done. (3) Marking a feature
complete without end-to-end testing. (4) Spending tokens re-learning how to run the app.

**Not solved.** Orchestration is a Python driver script; there is no notion of an
interruption other than context exhaustion; parallelism is untouched; the "next session"
carries no per-session prompt — the same coding prompt is reused every time and the state
files carry the difference.

### 1.3 Anthropic engineering — "Harness design for long-running application development" (Mar 24, 2026)

**What it is.** Prithvi Rajasekaran's follow-up: a planner/generator/evaluator harness on
the Agent SDK, with the evaluator using Playwright to click through the built app. Primary;
read in full. https://www.anthropic.com/engineering/harness-design-long-running-apps

**Closing the loop.** Planner expands a 1–4 sentence prompt into a spec; generator works
"in sprints, picking up one feature at a time"; before each sprint the generator and
evaluator negotiate a "sprint contract" agreeing what done looks like; the evaluator grades
each sprint against hard thresholds and fails it with feedback if any criterion is below
threshold. "Communication was handled via files: one agent would write a file, another
agent would read it and respond." With Opus 4.6 the sprint construct was removed and the
evaluator moved to a single pass at the end.

**Interruptions.** Two named: (1) "context anxiety" — some models "begin wrapping up work
prematurely as they approach what they believe is their context limit"; the remedy is a
context *reset* (fresh agent plus "a structured handoff that carries the previous agent's
state and the next steps"), which compaction does not provide; Sonnet 4.5 needed resets,
Opus 4.5 "largely removed that behavior" so resets were dropped. (2) Self-evaluation
leniency: "agents tend to respond by confidently praising the work"; an evaluator "is still
an LLM that is inclined to be generous", but "tuning a standalone evaluator to be skeptical
turns out to be far more tractable". The evaluator initially "talk[ed] itself into deciding
they weren't a big deal" and had to be tuned over several rounds by reading its logs.

**Parallel work and merges.** None; one build at a time.

**State.** Files exchanged between agents; git in the generator. Cost table: the full
harness took 3 h 50 min and $124.70 (v2) versus 20 min and $9 solo; the v1 harness was $200
against $9 solo.

**Not solved.** Nothing about usage limits, crashes or prompts; the harness is a script,
not a session-to-session chain. The post's own lesson: "every component in a harness encodes
an assumption about what the model can't do on its own", and those assumptions go stale.

### 1.4 Anthropic engineering — "Building a C compiler with a team of parallel Claudes" (Feb 5, 2026)

**What it is.** Nicholas Carlini's account of 16 Claude Code sessions, ~2,000 sessions over
two weeks, ~$20,000, producing a 100k-line compiler. Primary; read in full.
https://www.anthropic.com/engineering/building-c-compiler

**Closing the loop.** An eight-line bash loop: `while true; do claude
--dangerously-skip-permissions -p "$(cat AGENT_PROMPT.md)" … ; done`, log file named by the
current commit. "When it finishes one task, it immediately picks up the next." Each session
starts in a fresh container with no context; the prompt asks Claude to break the problem
into small pieces, "tracking what it's working on, figuring out what to work on next", and
to maintain "extensive READMEs and progress files … updated frequently". "Done" is never
declared by the harness — "the loop runs forever". The next unit is Claude's choice: "In
most cases, Claude picks up the 'next most obvious' problem."

**Interruptions.** Permission prompts eliminated by `--dangerously-skip-permissions` inside
a container ("Run this in a container, not your actual machine"). Crashes: "in one instance,
I did see Claude `pkill -9 bash` on accident, thus killing itself and ending the loop."
Questions: the loop is `-p`, so there is no one to ask. Time blindness: "left alone, [Claude]
will happily spend hours running tests"; the harness prints progress infrequently and
defaults to a deterministic 1–10 % test subsample per agent.

**Parallel work and merges.** One bare upstream repo; each agent clones to `/workspace`
in its own Docker container. Coordination is a lock file: an agent claims a task by writing
`current_tasks/<task>.txt` and pushing; "if two agents try to claim the same task, git's
synchronization forces the second agent to pick a different one"; after the task, pull,
merge, push, delete the lock. "Merge conflicts are frequent, but Claude is smart enough to
figure that out." Reported failure: on one giant task (the kernel build) "every agent would
hit the same bug, fix that bug, and then overwrite each other's changes. Having 16 agents
running didn't help" — the fix was a GCC oracle that split the kernel into per-agent file
subsets. "I don't use an orchestration agent." Specialised roles (dedup, performance, docs,
Rust critique) ran as additional agents.

**State.** Git (locks, commits, logs), READMEs and progress files, test results.

**Not solved.** No orchestrator, no messaging, no stop condition, no quota handling; "it is
easy to see tests pass and assume the job is done, when this is rarely the case."

### 1.5 Anthropic — "How Anthropic teams use Claude Code" (Jul 24, 2025) and the best-practices doc

**What it is.** The teams PDF plus the current best-practices page. The PDF is primary but
2025; the docs page is current and was read in full.
https://www-cdn.anthropic.com/58284b19e702b49db9302d5b6f135ad8871e7658.pdf ;
https://www.anthropic.com/news/how-anthropic-teams-use-claude-code ;
https://code.claude.com/docs/en/best-practices

**Closing the loop (PDF).** "Autonomous loops where Claude writes code, runs tests, and
iterates continuously"; review "the 80% complete solution"; "starting from a clean git state
and committing checkpoints regularly so they can easily revert"; "distinguish between tasks
that work well asynchronously (peripheral features, prototyping) versus those needing
synchronous supervision".

**Closing the loop (best practices).** "Claude stops when the work looks done. Without a
check it can run, 'looks done' is the only signal available." Four gating strengths: ask in
the prompt; set a `/goal` condition ("a separate evaluator re-checks it after every turn");
a Stop hook "runs your check as a script and blocks the turn from ending until it passes.
Claude Code overrides the hook and ends the turn after 8 consecutive blocks"; a verification
subagent. "The `/goal` and Stop hook versions are what let an unattended run finish
correctly without you." "Have Claude show evidence rather than asserting success." For
large features: interview, write `SPEC.md`, then "start a fresh session to execute it".
Adversarial review: "a reviewer running in a fresh subagent context sees only the diff and
the criteria you give it, not the reasoning that produced the change".

**Interruptions (best practices).** `claude -p` "still creates a resumable session unless
you pass `--no-session-persistence`"; auto mode under `-p` "aborts if the classifier
repeatedly blocks actions, since there is no user to fall back to"; `--allowedTools` "matters
when you're running unattended". Fan-out is a shell loop over `claude -p` per file.

**Parallel work.** Worktrees, desktop app, web, agent teams; Writer/Reviewer split across
two sessions.

**Not solved.** No handover between sessions beyond "write a spec, start fresh"; nothing on
usage limits.

### 1.6 Claude Code's native loop primitives (docs, current)

These are the in-product forms of the patterns above; each is documented behaviour, read in
full on 2026-09-11.

- **`/goal`** — https://code.claude.com/docs/en/goal. "A wrapper around a session-scoped
  prompt-based Stop hook": after each turn the small fast model (Haiku by default;
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`) returns *not yet met* (reason becomes next-turn guidance),
  *met* or *impossible*. "The evaluator … doesn't run commands or read files independently",
  so the condition must be something Claude's output demonstrates. Stops the loop with the
  goal still set if "no tool use for several turns in a row". Clears the goal on four
  unrecoverable errors: authentication failure, exhausted credit balance, context overflow
  auto-compaction couldn't clear, model unavailable; "after any other failure, including
  transient errors such as rate limits and overloaded servers, Claude Code leaves the goal
  active". Background work defers evaluation; a check-in is due after 30 minutes
  (`CLAUDE_CODE_GOAL_CHECKIN_MINUTES`), doubling up to 4× the first interval, at most three
  idle check-ins per goal between prompts. Works with `-p` (one invocation runs to
  completion; use `--output-format stream-json --verbose` to see progress). Restored on every
  resume route since v2.1.239; turn count and timer reset. Unavailable when `disableAllHooks`
  is true.
- **`/loop` and scheduled tasks** — https://code.claude.com/docs/en/scheduled-tasks.
  Session-scoped cron (`CronCreate`/`CronList`/`CronDelete`); "a scheduled prompt fires
  between your turns, not while Claude is mid-response"; recurring tasks expire after 7 days;
  minimum interval 1 minute; "Tasks only fire while Claude Code is running and idle …
  Backgrounding the session carries `/loop` tasks over to a background session, which keeps
  running without a terminal"; restored on `--resume`/`--continue` if unexpired; "Background
  Bash and monitor tasks are never restored on resume". Self-paced mode: Claude picks a delay
  between 1 minute and 1 hour; if an iteration neither reschedules nor stops, one fallback
  wakeup fires ~20 minutes later and then the loop ends. The Monitor tool "runs a background
  script and streams each output line back, which avoids polling". `CLAUDE_CODE_DISABLE_CRON=1`
  disables all of it.
- **Desktop scheduled tasks** — https://code.claude.com/docs/en/desktop-scheduled-tasks.
  Local; "Desktop checks the schedule every minute while the app is open and starts a fresh
  session when a task is due"; "If your computer sleeps through a scheduled time, the run is
  skipped"; a "Keep computer awake" setting exists, but "closing the laptop lid still puts it
  to sleep"; the session appears under a Scheduled section where permission prompts can be
  answered; a task "can also modify its own schedule or prompt … using the
  `update_scheduled_task` MCP tool"; the prompt lives at
  `~/.claude/scheduled-tasks/<name>/SKILL.md` (frontmatter `name`, `description`; schedule,
  folder, model and enabled state are not in the file); permission mode and model are
  pickers in the instructions input. Cross-session messaging is unavailable in a scheduled run.
- **Routines** — https://code.claude.com/docs/en/routines. Cloud sessions with schedule, API
  and GitHub triggers; "no permission-mode picker and no approval prompts during a run";
  minimum interval one hour; a fresh clone each run; a model selector per routine. Hosted;
  out of Baton's v1 scope by the map, recorded for completeness.
- **Agent teams** — https://code.claude.com/docs/en/agent-teams. Experimental,
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; a lead session, teammates as full sessions, a
  shared task list with "file locking to prevent race conditions", mailboxes as JSON at
  `~/.claude/teams/{team}/inboxes/{agent}.json`; task list at `~/.claude/tasks/{team}/`
  persists locally; "Teammates start with the lead's permission settings"; "Teammate
  permission prompts appear in the lead session"; hooks `TeammateIdle`, `TaskCreated`,
  `TaskCompleted` (exit 2 sends feedback and keeps the teammate working / blocks the
  transition); "known limitations around session resumption, task coordination, and shutdown
  behavior"; teammates cannot approve permissions for each other, and a relayed approval is
  treated as untrusted input.
- **Dynamic workflows** — https://code.claude.com/docs/en/workflows. "A workflow script
  holds the loop, the branching, and the intermediate results itself"; up to 16 concurrent
  agents, 1,000 per run; resumable in the same session; workflow subagents "always run in
  `acceptEdits` mode and inherit your tool allowlist"; the `ultracode` keyword does not start a
  workflow from `-p`, from a scheduled task prompt, or from a relayed webhook.
- **Overview of parallel surfaces** — https://code.claude.com/docs/en/agents: subagents
  (Claude delegates inside one conversation), agent view (`claude agents`: "you hand off
  independent tasks and check back later"), agent teams, workflows; `/batch` "has Claude
  split one large change into 5 to 30 worktree-isolated subagents that each open a pull
  request".

### 1.7 The Ralph Wiggum loop — Huntley's original and the official plugin

**What it is.** Geoffrey Huntley's technique (Jul 14, 2025): "In its purest form, Ralph is
a Bash loop. `while :; do cat PROMPT.md | claude-code ; done`". Anthropic's plugin
(committed Nov 16, 2025, "Migrates the ralph-wiggum plugin from internal marketplace to
public marketplace") re-implements it as a Stop hook inside one session. Both primary; read
in full. https://ghuntley.com/ralph/ ;
https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md ;
https://github.com/anthropics/claude-code/blob/988b3e56/plugins/ralph-wiggum/hooks/stop-hook.sh ;
https://github.com/anthropics/claude-code/commit/68f90e05dd919b626c43351624fd0dc10c70b341

**Closing the loop (Huntley).** "One item per loop"; the prompt deterministically loads the
same stack every iteration — the plan (`@fix_plan.md`) and the specs — and tells Ralph to
"choose the most important thing"; "trust Ralph to decide what's the most important thing
to implement". Backpressure is the test/build/type-check step that rejects bad generation:
"Anything can be wired in as back pressure". A separate loop rebuilds the plan: study
specs and source with subagents, "create/update a `@fix_plan.md` which is a bullet point
list sorted in priority of the items which have yet to be implemented". "Eventually, Ralph
will run out of things to do in the TODO list."

**Closing the loop (plugin).** `/ralph-loop "<prompt>" --max-iterations N
--completion-promise "TEXT"` writes `.claude/ralph-loop.local.md` (YAML frontmatter:
iteration, max, promise; body: the prompt). The Stop hook reads the transcript's last
assistant message, extracts `<promise>…</promise>` with a literal string compare, and on a
match deletes the state file and exits 0; otherwise it increments the iteration and returns
`{"decision":"block","reason":<the same prompt>,"systemMessage":"🔄 Ralph iteration N …"}`.
"The prompt never changes between iterations … Each iteration sees modified files and git
history." The setup script's own warning: "No manual stop — Ralph runs infinitely by
default!"; and the injected instruction "Do NOT output false statements to exit the loop …
Even if you believe you're stuck, the task is impossible, or you've been running too long —
you MUST NOT output a false promise statement."

**Interruptions.** Huntley: "Claude has the inherent bias to do minimal and placeholder
implementations"; "the models have been trained to chase their reward function, and the
reward function is compiling code"; a common failure is `ripgrep` concluding something is
not implemented ("don't assume it's not implemented"). Plugin: the completion promise "uses
exact string matching, which is unreliable. Always use `--max-iterations` as your real safety
net" (community guide, https://dev.to/sivarampg/the-ralph-wiggum-approach-running-ai-coding-agents-for-hours-not-minutes-57c1
, Jan 5, 2026). Neither handles usage limits, permission prompts (Huntley's loop assumes
none), or crashes.

**Parallel work.** Huntley: "Ralph is monolithic … a single process that performs one task
per loop"; subagents for search and file writing, "only 1 subagent for build/tests" to
avoid backpressure overload.

**State.** `PROMPT.md`, `fix_plan.md`, `specs/`, git; the plugin's `.claude/ralph-loop.local.md`.

**Not solved.** Done-detection is a string the model chooses to emit; nothing about
scheduling, parallelism or escalation. A reported regression (ParkerRex, undated): with plugin
v2.0.76+ "Stop hook hijacks all sessions" and `/cancel-ralph` "doesn't work" — consistent
with the design, since any session in a project whose `.claude/ralph-loop.local.md` exists is
looped by the hook. Unverified beyond that report.
https://github.com/ParkerRex/ralph-loop

### 1.8 Ralph descendants

- **frankbria/ralph-claude-code** (bash; v0.11.5; 9.6k stars; README read in full).
  Exit is a "dual-condition gate": heuristic `completion_indicators >= 2` *and* an explicit
  `EXIT_SIGNAL: true` in a `RALPH_STATUS` block, added because completion indicators alone
  produced "premature exit after exactly 5 loops". Other exits: every `- [ ]` in
  `.ralph/fix_plan.md` checked (items under `Optional`/`Future`/`Nice to Have` headings do not
  block — "resolves the deadlock where Claude treats low-priority items as skippable while
  Ralph waits for them"); too many test-only loops; "Claude API 5-hour usage limit reached"
  with "three-layer detection: timeout guard → structural JSON (`rate_limit_event`) → filtered
  text fallback" and, in unattended mode, auto-wait instead of exit (a timeout exit code 124
  had been misread as the limit, #183). Rate limiting at 100 calls/hour; a circuit breaker
  on consecutive failures; session continuity via `--resume <session_id>` after
  `--continue` was found to hijack the wrong session (#151); session expiry 24 h; `--backup`
  git branches with `--rollback`; `--notify` desktop notifications; `--dry-run`; JSON Lines
  metrics per loop; GitHub-issue and Beads task import; `--sandbox docker|e2b` (hosted).
  https://github.com/frankbria/ralph-claude-code
- **mikeyobrien/ralph-orchestrator** (Rust; alpha). Iterates "until it outputs
  `LOOP_COMPLETE` or hits the iteration limit"; "hats" (personas) coordinate through events;
  "backpressure" gates (tests, lint, typecheck) reject incomplete work; five safety
  mechanisms — iteration limit (100), runtime limit (4 h), cost limit ($10), consecutive
  failures (5), loop detection (outputs ≥ 90 % similar); human interaction over Telegram —
  "agents emit `human.interact` events; the loop blocks until a response arrives or times
  out". Principles: "Fresh Context Is Reliability", "Disk Is State, Git Is Memory", "Sit on
  the loop, not in it". Their own cost note: "A 50-iteration cycle on large codebases can
  cost $50–100+".
  https://github.com/mikeyobrien/ralph-orchestrator ;
  https://mikeyobrien.github.io/ralph-orchestrator/guide/overview/
- **vercel-labs/ralph-loop-agent** (TypeScript package for the AI SDK). An outer loop around
  `generateText` with a `verifyCompletion` function (any code check) and stop conditions
  `iterationCountIs`, `tokenCountIs`, `costIs`; the `reason` from a failed verification is
  injected into the next iteration. https://github.com/vercel-labs/ralph-loop-agent/blob/main/README.md
- **Cross-vendor note (secondary).** "OpenAI's Codex team shipped one million lines of code
  across 1,500 pull requests with zero human-written code using what they call a 'Ralph
  Wiggum Loop'" — reported at https://www.decodingai.com/p/ralph-loops (Apr 23, 2026);
  primary not fetched. The same piece reports a Claude Code agent running `terraform destroy`
  on production infrastructure at DataTalks.Club — secondary, unverified here.

### 1.9 Gas Town and Beads (Steve Yegge)

**What it is.** A Go orchestrator (`gt`) for "20–30 Claude Code instances at once",
announced Jan 1, 2026 and v1.0 on Apr 3, 2026, built on Beads, a git-backed JSONL issue
tracker (later on Dolt). Primary essays and README read; the essay was fetched to ~60 %.
https://yegge.ai/essays/welcome-to-gas-town/ ;
https://steve-yegge.medium.com/gas-town-from-clown-show-to-v1-0-c239d9a407ec ;
https://github.com/steveyegge/gastown

**Closing the loop.** Work is a bead; `gt sling <bead> <rig>` hangs it on a worker's
"hook" (a pinned bead); the Gastown Universal Propulsion Principle: "If there is work on
your hook, YOU MUST RUN IT." A polecat (ephemeral worker with persistent identity) works
in its own worktree, produces a merge request for the Refinery (merge queue), and is
decommissioned. Molecules chain beads into deterministic step lists; patrols are looped
workflows with exponential backoff ("the agent will gradually go to sleep if it finds no
work"). The handoff: "`gt handoff` … Your worker will optionally send itself work, then
restart its session for you, right there in tmux." Convoys bundle beads; "a Convoy can have
multiple swarms 'attack' it … Whoever is managing the Convoy (e.g. Witness) will keep
recycling polecats." Gate states: "the polecat disappears while the molecule is waiting in
Gate states, such as awaiting a GH Action or CI/CD. And then when the Gate bead triggers,
Gas Town wakes up a polecat to continue the work."

**Interruptions.** Politeness: "Claude Code is so miserably polite that GUPP doesn't always
work in practice … It just sits there waiting for user input", so `gt nudge` sends a tmux
message "roughly 30 to 60 seconds after it starts up" ("It doesn't matter what you tell the
agent in the nudge"). Heartbeat hierarchy: a daemon pings the Deacon every couple of
minutes; "Boot the Dog" wakes every 5 minutes only to check whether the Deacon needs a
heartbeat, nudge or restart. The Witness "detects stuck agents, triggers recovery". Context
exhaustion: "The biggest problem with Claude Code is it ends"; the remedy is identity in
Beads plus the hook, so a new session continues; `gt seance` uses `/resume` to ask the
previous session where it left things. `gt escalate -s` routes by severity;
`gt feed --problems` surfaces stuck agents. Permissions: "tuned to 'you only live once'
(YOLO) even harder than the hardest YOLO mode" (DoltHub field report).

**Parallel work and merges.** Worktree per polecat; the Refinery exists because "your
workers get into a monkey knife fight over rebasing/merging … the final workers getting
merged are trying to merge against an unrecognizable new head" — one engineer agent merges
one at a time and may escalate.

**State.** Beads: `.beads/issues.jsonl` in git (one JSON line per issue, mail, event);
agent identity, hooks and orchestration state are beads; "Wisps" are ephemeral beads not
persisted to git so patrols do not pollute history.

**Field report (Tim Sehn, DoltHub, Jan 15, 2026).** "Gas Town pushes branches to GitHub,
makes PRs, and, much to my surprise, merges them! After the first PR got merged autonomously,
despite the integration tests failing, I quickly closed Gas Town." Also: "only two PRs had
been made, but the Mayor was reporting all the bugs were fixed … the work was in Git but not
pushed." https://www.dolthub.com/blog/2026-01-15-a-day-in-gas-town/

**Not solved.** Cost ("a machine for spending hundreds of dollars a day"; a second and
third account needed); reliability ("stuff goes wrong often … very much a hands-on-the-wheel
orchestration system"); it is the opposite of Baton's n-of-1 scope. Third-party (Go binary,
tmux required, Dolt).

### 1.10 tmux orchestrators

All five spawn Claude Code in tmux windows and drive it with `send-keys`; the map already
supersedes typing-into-terminals as Baton's mechanism, so what is recorded here is the
detection and scheduling logic, which is mechanism-independent.

- **Jedward23/Tmux-Orchestrator** (bash plus a Python helper; undated README, widely
  forked). Three tiers (orchestrator → project managers → engineers) "to overcome context
  window limitations". Self-scheduling: `./schedule_with_note.sh 30 "Check PM progress"`
  fires a message into a named window later; messaging via `send-claude-message.sh`, which
  exists because of "the critical 0.5s delay between message and Enter". The orchestrator
  "MUST" verify its own window before scheduling, since "scheduling to wrong window breaks
  the oversight chain". No done-detection beyond asking for status updates; commit
  discipline is prompted ("commit every 30 minutes").
  https://github.com/Jedward23/Tmux-Orchestrator ;
  https://github.com/Jedward23/Tmux-Orchestrator/blob/main/CLAUDE.md
- **LeiShi1313/tmux-orchestration** (bash + jq; undated). External `heartbeat.sh`: sleep
  (30 s when stuck, 120 s normal, 300 s idle) → read `_orchestrator/workers/*.json` → check
  the orchestrator pane is idle via `capture-pane` and a `.ready` file handshake ("only sends
  commands when the orchestrator pane is actually idle. This prevents prompt collisions") →
  `send-keys /orchestrate-cycle` → append `log.jsonl`. Worker states: `SAFE_TO_RESTART`,
  `DO_NOT_INTERRUPT`, `CONTEXT_LOW_CONTINUE`, `RATE_LIMITED_WAIT`, `ERROR_STATE`, `UNKNOWN`.
  Spawn: new window, start Claude, poll `capture-pane` for the idle prompt (max 60 s), switch
  model with `/sonnet` or `/haiku`, paste the prompt via `load-buffer`/`paste-buffer`, wait for
  the worker's status JSON (max 90 s). Rate-limit watchdog: scan panes every 15 s for
  `429`/`Rate limit`/`overloaded`, wait 65 s, then send "This was a TEMPORARY rate limit, not a
  bug. Run the exact same command again — no workaround", with exponential backoff to 10
  minutes — because "if you paste the error back, Claude interprets it as 'the command is
  broken' and uses a workaround instead of retrying." Workers run
  `--dangerously-skip-permissions` ("required for unattended operation"). Each session
  carries "~41K tokens of system overhead"; "Start with 2 workers"; "you will hit API rate
  limits". https://github.com/LeiShi1313/tmux-orchestration
- **jeffdhooton/orch** (Go, SQLite, tmux). `orch schedule`, `orch watch` ("automatically
  restarts any that have died (tmux window gone but DB still says running). Essential for
  24/7"), a "git commit watcher — when a builder commits, PM-role agents in the same directory
  are automatically notified with the commit message. No more waiting for the next scheduled
  check-in"; agents request follow-ups by writing `.orch-schedule`; for true 24/7 "run `orch
  scheduler` and `orch watch` under a process manager (systemd, launchd, etc.)".
  https://github.com/jeffdhooton/orch
- **twaldin/tmux-orchestrator** (bash-only Claude Code plugin). `watch_agents` "auto-approve
  stuck permission prompts across all agent panes"; `compact_self` ("write state, /clear,
  resume"); `reconcile_agents --fix` respawns dead persistent agents; a persistent orchestrator
  keeps `state.md`, `tasks.md`, `crons.md` and "heartbeat crons"; ephemeral coders get a
  completion protocol injected into `CLAUDE.md` (`message_parent` + `/exit`); `--model` per
  spawn. https://github.com/twaldin/tmux-orchestrator
- **mehmetcanfarsak/Agentainer** (Python; zero external deps). File-based mail
  (`inbox/`, `outbox/<name>/`); "Turn-completion detection is wired per type (a Stop hook for
  Claude, a `notify` program for Codex, and pane polling for Gemini/Hermes)"; a supervisor
  heartbeat "reconciling stale-busy, dead, and silent-but-alive agents"; "auto-releasing the
  next message after N presentations and a rate cap on runaway auto-exchanges"; scheduled
  pings with `when_busy: skip | queue`; v1's "tagged XML envelope emitted inside prose and
  scraped out of a TUI pane … was unreliable across LLMs". A key-free mock agent lets the
  mechanics run without an API. https://github.com/mehmetcanfarsak/Agentainer

### 1.11 Worktree managers

- **smtg-ai/claude-squad** (Go TUI; created Mar 9, 2025). tmux session plus a git worktree
  per task; "complete tasks in the background (including yolo / auto-accept mode!)";
  `c` "Checkout. Commits changes and pauses the session", `r` resumes; review diffs before
  pushing. No done-detection beyond the TUI status; no scheduler.
  https://github.com/smtg-ai/claude-squad
- **Conductor** (conductor.build; native macOS app; closed source). "The unit of independent
  Claude Code work is a workspace" = worktree + branch + setup script + terminal + diff + PR
  path; a workspace can start "from a GitHub issue, Linear issue, pull request, branch, or a
  new task"; the Checks tab tracks git status, CI, deployments, comments, todos; advice: "Keep
  shared context in committed docs … not only in one chat"; "Avoid assigning two workspaces
  the same file-heavy refactor". https://www.conductor.build/docs/guides/parallel-agents/run-multiple-claude-code-sessions
- **Crystal → Nimbalyst**. Crystal "is no longer developed"; it had per-session status
  ("initializing, running, waiting for input, or completed"), AI-named sessions, rebase/
  squash in-app. Superseded by a commercial app.
  https://nimbalyst.com/blog/crystal-supercharge-your-development-with-multi-session-claude-code-management/
- **BloopAI/vibe-kanban** (Rust; ~22k stars). Kanban issues → workspaces (branch, terminal,
  dev server) → diff review with inline comments sent back to the agent → PR. The README
  now carries "Vibe Kanban is sunsetting." https://github.com/BloopAI/vibe-kanban
- **ryanmac/code-conductor** (GitHub-native). Agents "claim task #42 → create isolated
  worktree → implement → open PR → move to next task"; `--auto-merge` optional.
  https://github.com/ryanmac/code-conductor
- **devinrosen/conductor-ai** (SQLite; TUI). Workflows in a `.wf` DSL with `parallel`,
  `while`, `gate` (human or automated approval) and `always` cleanup blocks; "No daemon or
  background process". https://github.com/devinrosen/conductor-ai
- **Comparison (Zenn, Mar 6, 2026).** Tools split into "worktree management" (claude-squad,
  vibe-kanban, workmux, dmux — "new task = new worktree + new session", the tool owns the
  lifecycle) and "existing-environment monitoring" (cmux, crmux, TmuxCC — "it just looks at
  them" and only `send-keys` when needed). https://zenn.dev/maedana/articles/claude-code-multi-session-tools-comparison?locale=en

**Common to all.** Isolation by worktree; "done" is a human looking at a diff; no usage-limit
handling; the person is the scheduler. None chains sessions.

### 1.12 Superpowers (Jesse Vincent)

**What it is.** A skills plugin (Oct 2025 →) whose execution half is an in-session
orchestrator: brainstorm → spec → plan → subagent-driven development → finish branch. Repo
skills and the author's blog posts read in full.
https://github.com/obra/superpowers ;
https://raw.githubusercontent.com/obra/superpowers/main/skills/subagent-driven-development/SKILL.md ;
https://raw.githubusercontent.com/obra/superpowers/main/skills/executing-plans/SKILL.md ;
https://raw.githubusercontent.com/obra/superpowers/main/skills/writing-plans/SKILL.md

**Closing the loop — the handoff between contexts.**
- September 2025 (two windows, human as relay): the "architect" session writes the plan to
  `docs/plans/`; a second `claude` in the same directory is told "Please read
  docs/plans/this-task-plan.md … Please execute the first 3-4 tasks. If you have questions,
  please stop and ask me. DO NOT DEVIATE FROM THE PLAN."; the architect reviews; "I'll tell
  the implementer to update the planning doc with its current state. And then, I don't
  `/compact`. Instead I `/clear` the implementer and start the conversation over. Telling it
  that it's starting with task 4." The architect is rewound with double-`ESC` to review
  "without any biases from the previous implementation".
  https://blog.fsck.com/2025/10/05/how-im-using-coding-agents-in-september-2025/
- October 2025 onward (subagents): "it dispatches tasks one by one to subagents to implement
  and then code reviews each task before continuing"; a worktree is created automatically
  after brainstorming. https://blog.fsck.com/2025/10/09/superpowers/
- Current SKILL.md: "Fresh subagent per task + task review (spec + quality) + broad final
  review". Plans are written so "the engineer has zero context for our codebase and
  questionable taste": exact files, an **Interfaces** block ("A task's implementer sees only
  their own task; this block is how they learn the names and types neighboring tasks use"),
  2–5-minute steps, no placeholders. Implementers report `DONE`, `NEEDS_CONTEXT`, `BLOCKED`
  (re-dispatch with more context / a more capable model / smaller pieces / escalate if the plan
  is wrong) — quoted from a fork mirror, https://github.com/pcvelz/superpowers/blob/HEAD/skills/subagent-driven-development/SKILL.md.
  Fix rounds cap at 5: "R≤3 resume implementer; R≥4 fresh implementer, more capable model";
  at 5 "the breaker trips" and findings are adjudicated. "Continuous execution: Do not pause
  to check in … The only reasons to stop are the four named below": an irreversible or
  destructive operation, a security-sensitive action, a side effect outside the worktree
  norms say to ask about (merge, push to shared branch, publish), and "a plan so broken that
  every path forward is a guess". Otherwise "Rulings, not stalls": decide, and record
  `Ruling: <what> — <why> — <what it costs if wrong>` in the ledger.
- `executing-plans` (no subagents available): load the plan, review critically, execute, and
  "STOP executing immediately when: hit a blocker …, plan has critical gaps …, you don't
  understand an instruction, verification fails repeatedly".

**Interruptions.** Compaction: "Conversation memory does not survive compaction. In real
sessions, controllers that lost their place have re-dispatched entire completed task
sequences — the single most expensive failure observed. Track progress in a ledger file";
the ledger is `<repo>/.superpowers/sdd/<plan-basename>/progress.md`, first line names the
plan, `Task <N>: complete` lines mark done tasks; "After compaction, trust the ledger and
`git log` over your own recollection." Questions: implementer subagents may ask before or
during work; the orchestrator answers. Permissions and usage limits: not addressed.
Reviewer misbehaviour (v5.0.2, Mar 11, 2026): reviewers that inherited the dispatcher's
whole session "start behaving as if it were the lead developer"; fix — "construct exactly
what each subagent needs … Never forward session history."
https://blog.fsck.com/agent-blog/2026/03/11/superpowers-v5-0-2/
Instruction-following (v5.0.1): "agents follow checklists and diagrams more reliably than
prose … Prose is documentation. Checklists and graphs are instructions."
https://blog.fsck.com/agent-blog/2026/03/10/superpowers-v5-0-1/
Before compaction (MLOps podcast, Apr 24, 2026): "I will now always ask like, Hey, is there
anything you wanna write down or is there any notes you wanna take before we compact?"
https://home.mlops.community/en/public/videos/the-creator-of-superpowers-why-real-agentic-engineering-beats-vibe-coding

**Parallel work and merges.** "Bounded Parallel Dispatch": implementers may run concurrently
only when "their tasks' `files` lists share no path AND neither task appears in the other's
`blockedBy` chain. The `files` metadata IS the test"; "When overlap is uncertain,
serialize"; read-only agents are always parallel-safe. One worktree per plan.

**Model choice (v5, Mar 9, 2026; SKILL.md).** "Use the least powerful model that can handle
each role": mechanical tasks → cheap; integration/judgement → standard; architecture and the
final whole-branch review → most capable; "it's not uncommon to be able to use Claude Haiku
for implementation". v6 (Jun 15, 2026) reports an overnight `/goal`-driven "autoresearch"
run of 25 experiments (~$165): an Opus controller with conditional Haiku implementers and a
terse reviewer contract cut a build from $11.67–14.84 to $6.24–6.60; "capping controller
thinking backfires — turns rose 92→138"; pre-baking the review packet (a script producing the
diff) cut reviewer tokens ~10 %. https://blog.fsck.com/2026/03/09/superpowers-5/ ;
https://blog.fsck.com/2026/06/15/Superpowers-6/

**State.** Plan in `docs/superpowers/plans/`, spec in `docs/superpowers/specs/`, ledger in
`.superpowers/sdd/<plan>/`, `.tasks.json` (fork), git.

**Not solved.** It is one session's loop over subagents; nothing starts the next *session*;
no usage-limit or crash handling; "tokens are expensive and Superpowers uses a ton of them".

### 1.13 Symphony (OpenAI)

**What it is.** An Apache-2.0 spec (`SPEC.md`, "Draft v1 (language-agnostic)") plus an
Elixir reference for "a long-running automation service that continuously reads work from a
configured issue tracker, creates an isolated workspace for each issue, and runs a coding
agent session for that issue inside the workspace." Announced Apr 27, 2026; "not a product
OpenAI plans to maintain". Primary spec read to §13.7; README and announcement read.
https://openai.com/index/open-source-codex-orchestration-symphony/ ;
https://raw.githubusercontent.com/openai/symphony/main/SPEC.md ;
https://github.com/openai/symphony/blob/main/elixir/README.md

**Closing the loop.** Tick every `polling.interval_ms` (30 s): reconcile running issues →
preflight-validate config → fetch candidates in `active_states` → sort (priority 1–4, then
oldest, then identifier) → dispatch while slots remain. Eligible only if not running, not
claimed, slots free globally and per state, labels present, and (for `Todo`) no non-terminal
blocker. Internal claim states: `Unclaimed → Claimed → Running | RetryQueued → Released`.
"A successful worker exit does not mean the issue is done forever": after each normal turn
the worker re-checks the tracker; if still active it starts another turn "on the same live
coding-agent thread in the same workspace, up to `agent.max_turns`" (20); "Continuation
turns SHOULD send only continuation guidance … not resend the original task prompt"; after a
normal exit a ~1 s continuation retry re-checks. The agent, not Symphony, moves the ticket:
"A successful run can end at a workflow-defined handoff state (for example `Human Review`),
not necessarily `Done`." Prompt = `WORKFLOW.md` body rendered with `issue` and `attempt`
(strict templating: unknown variables fail). Run-attempt phases: PreparingWorkspace,
BuildingPrompt, LaunchingAgentProcess, InitializingSession, StreamingTurn, Finishing,
Succeeded, Failed, TimedOut, Stalled, CanceledByReconciliation.

**Interruptions.** Stall: no agent event for `stall_timeout_ms` (5 min) → kill worker and
queue a retry. Turn silence timeout 1 h (each output resets it). Failure retries back off
`min(10000 · 2^(attempt−1), 300000)` ms. Reconciliation: if the ticket goes terminal, stop
the agent and clean the workspace; if it becomes non-active or unroutable, stop it and keep
the workspace; "If state refresh fails, keep workers running." Questions and approvals:
"Approval requests and user-input-required events MUST NOT leave a run stalled
indefinitely"; the high-trust example "auto-approve[s] command execution … file-change
approvals" and "Treat[s] user-input-required turns as hard failure". Crashes/restarts:
"Restart recovery is tracker-driven and filesystem-driven (without a durable orchestrator
DB)"; startup deletes workspaces of terminal issues. Config: `WORKFLOW.md` is hot-reloaded;
"Invalid reloads MUST NOT crash the service". Rate limits: tracked as a snapshot from agent
events, not acted on. Tracker credentials are stripped from the agent's environment; the
agent calls tracker tools that Symphony executes host-side.

**Parallel work and merges.** One agent per issue; `max_concurrent_agents` (10) and
`max_concurrent_agents_by_state`; workspaces reused across attempts and "intentionally
preserved after successful runs"; merging is the agent's job via PRs (workflow policy).
Reported internal result: "some internal teams saw a ~500% increase in landed PRs"
(secondary, https://dreaming.press/posts/openai-symphony-issue-tracker-coding-agent-control-plane.html).

**State.** In-memory orchestrator state (`running`, `claimed`, `retry_attempts`,
`completed`, token totals, rate-limit snapshot); the tracker as the state machine; the
filesystem for workspaces; structured logs keyed by `issue_id`, `issue_identifier`,
`session_id`. Observability: a runtime snapshot with running rows (including `turn_count`),
retry rows, token totals, `seconds_running`, and optional HTTP `/api/v1/*`.

**Not solved.** Quality gates ("no cross-model review, coverage enforcement, or blocking
gates" — https://rywalker.com/research/symphony, secondary); a session that never reaches a
handoff state runs until `max_turns`; Linear/GitHub/Jira as the tracker (hosted). A "Kata
CLI" runtime in "spec v1.1" enabling Claude Code is reported by the same secondary source and
was not verified in the repo.

### 1.14 "Loop engineering" (Addy Osmani, Jun 7, 2026) — a synthesis source

**What it is.** A named summary of the pattern, mapped onto Claude Code and Codex. Primary
post read in full. https://addyosmani.com/blog/loop-engineering/

**Content.** Six primitives: automations (the "heartbeat": scheduled discovery and triage),
worktrees, skills, connectors, "sub-agents so one of them has the idea and a different one
checks it", and durable state "outside the single conversation" ("The agent forgets, the repo
doesnt"). On done-ness: "`/goal` keeps going until a condition you wrote is actually true, and
after every turn a separate small model checks whether you are done, so the agent that wrote
the code isnt the one grading it." Warnings: "A loop running unattended is also a loop making
mistakes unattended"; "'done' is a claim and not a proof"; comprehension debt and "cognitive
surrender". A worked loop: a morning automation triages CI failures into a state file, one
subagent drafts each fix in a worktree, a second reviews it, "Anything the loop can not handle
lands in the triage inbox for me."

---

## 2. Synthesis

### 2.1 Patterns that recur across sources

1. **Deterministic code holds the loop; the model holds judgement inside one unit.** The
   harness posts (§1.2–1.4), Symphony (§1.13), the Ralph descendants (§1.8) and `/goal`
   (§1.6) all put the *decision to run again* in code — a script, a Stop hook, a poll tick —
   and give the model only "what is the next most important thing" and "is this feature
   actually done". Where the loop itself is a Claude session (Gas Town's Mayor/Deacon,
   Tmux-Orchestrator's PM, twaldin's persistent orchestrator) the sources report the same
   flakiness: the session waits for input (Gas Town's "miserably polite", Carlini's "it will
   stop and wait for continued input"), needs nudges 30–60 s after start, and misreports
   state (DoltHub's Mayor "reporting all the bugs were fixed" while work sat unpushed).
2. **Fresh context per unit, state on disk.** Every source that runs longer than one window
   reconstructs context from files at the start of each unit: `claude-progress.txt` +
   `feature_list.json` + `git log` (§1.2); READMEs + progress files + locks (§1.4);
   `fix_plan.md` + specs (§1.7); the ledger + `git log` (§1.12); beads (§1.9); the ticket +
   workspace (§1.13). Compaction is explicitly called insufficient (§1.2, §1.3, §1.12);
   Vincent's remedy is a pre-compaction "write down anything you want to remember" prompt.
   Baton's kickoff prompt plus the brief's completion evidence and recovery clause is the same
   shape.
3. **One unit per session, chosen from a priority-ordered list that the session may only tick,
   not rewrite.** "One feature at a time" (§1.2), "one item per loop" (§1.7), one task per
   implementer (§1.12), one issue per agent (§1.13). The list is protected: JSON because the
   model overwrites Markdown less (§1.2); "It is unacceptable to remove or edit tests" (§1.2);
   fix-plan checkboxes with an `Optional` heading to avoid deadlock (§1.8).
4. **"Done" is never the worker's word alone.** Evidence required (§1.5), an end-to-end
   check before marking `passes` (§1.2), a separate evaluator/reviewer with its own context
   (§1.3, §1.5, §1.12, §1.14, `/goal`), a dual condition of heuristic + explicit signal
   (§1.8), a tracker state the agent must move (§1.13), a test/build gate as backpressure
   (§1.7, §1.8). Anthropic's own cases of a session "declaring victory" (§1.2), the DoltHub
   merge with failing tests (§1.9) and the Gas Town Mayor's false "all fixed" (§1.9) are the
   reported cost of skipping this.
5. **Isolation by worktree or container for anything concurrent; merge by PR or a queue.**
   Universal (§1.1, §1.4, §1.6, §1.9, §1.11, §1.12). Convergence — two agents on the same
   underlying problem — is the parallelism failure every source that tried it reports
   (Carlini's 16 agents on one bug; Yegge's "monkey knife fight"; "you become the merge
   conflict"). Superpowers' disjoint-`files` test and Symphony's per-issue claim are the two
   machine-checkable answers.
6. **Interruptions are classified before they are handled.** Symphony's terminal reasons
   (Failed/TimedOut/Stalled/Canceled), `/goal`'s clear-vs-keep list, LeiShi's six worker
   states, ralph-claude-code's three-layer limit detection, Superpowers' four stop reasons.
   The two classes every source treats differently are *transient* (rate limit, overload:
   wait and retry the same thing) and *needs a human* (auth, credits, a question, a plan that
   is wrong).
7. **Unattended runs pre-decide permissions.** Either a narrowed allowlist
   (`--allowedTools`, settings.json pre-allows — §1.1, §1.5), a classifier (auto mode; note
   it aborts under `-p` when it keeps blocking — §1.5), `dontAsk`/skip inside a sandbox or
   container (§1.1, §1.4, §1.10), or an external auto-approver over tmux (§1.10 twaldin).
   Symphony's rule generalises: an approval or question "MUST NOT leave a run stalled
   indefinitely".
8. **Escalation is a place, not a ping.** A triage inbox (§1.14, Codex Automations), a
   tracker state `Human Review` (§1.13), a Telegram thread that blocks the loop until answered
   or timed out (§1.8 ralph-orchestrator), Gas Town's severity-routed `gt escalate` and
   `gt feed --problems`, the desktop app's "Scheduled" section where a permission prompt can be
   answered (§1.6). Notifications are the channel; the *record* of what needs a decision lives
   somewhere durable.
9. **The person's role moves up one level and the leverage is verification.** Cherny (§1.1),
   Osmani (§1.14), Carlini's "most of my effort went into designing the environment around
   Claude — the tests" (§1.4), Rajasekaran's evaluator tuning (§1.3).

### 2.2 Pitfalls reported from real use

- **Premature completion**: a later session sees progress and declares the project done
  (§1.2); a Stop-hook loop stops only on a string the model emits, so the plugin warns
  against "lying to exit" and community guides call the promise "unreliable" (§1.7);
  heuristic completion signals produced exits "after exactly 5 loops" until an explicit
  `EXIT_SIGNAL` was required (§1.8); a Mayor reported fixes that were never pushed (§1.9).
- **Half-finished units and lost place**: running out of context mid-feature "even with
  compaction" (§1.2); "context anxiety" (§1.3); controllers that lost their place after
  compaction "re-dispatched entire completed task sequences — the single most expensive
  failure observed" (§1.12).
- **Waiting for input that never comes**: Claude Code "will stop and wait for continued
  input — a question, a status update, or a request for clarification" (§1.4); GUPP needs a
  nudge (§1.9); auto mode under `-p` aborts on repeated classifier blocks (§1.5); a scheduled
  prompt waits until the current turn ends and fires only when idle (§1.6).
- **Transient errors mistaken for bugs**: pasting a 429 back makes Claude "use a workaround
  instead of retrying" (§1.10 LeiShi); a timeout exit code was misread as the 5-hour limit
  (§1.8); `--continue` picked up the wrong session (§1.8).
- **Convergent work under parallelism**: 16 agents fixing the same bug and overwriting each
  other (§1.4); merge fights that require a serial merge agent (§1.9); "you become the merge
  conflict" (https://adamarant.com/en/blog/claude-code-workflow-patterns-we-use-to-ship-production-code-daily).
- **The agent damages its own harness or shared state**: `pkill -9 bash` (§1.4); autonomous
  merges with failing CI (§1.9); the `terraform destroy` report (§1.8, secondary).
- **Reviewer contamination**: a reviewer that inherits the dispatcher's history "role-plays
  as the developer" (§1.12); a self-evaluating generator "confidently prais[es] the work"
  (§1.3).
- **Placeholders and test tampering**: minimal implementations to satisfy the compiler
  (§1.7); tests removed or weakened (§1.2's prohibition; Vincent's `rm -rf` test-suite anecdote,
  https://share.snipd.com/episode/504fcdde-5b78-4a2a-a000-9702a8a4d256).
- **Time and token blindness**: hours spent on full test runs (§1.4); ~41K tokens of
  overhead per session (§1.10); harness runs at $124–200 per app (§1.3), $20k for the compiler
  (§1.4), "$50–100+" per 50 Ralph iterations (§1.8), hundreds of dollars a day for Gas Town
  (§1.9).
- **Schedulers that silently stop**: `/loop` tasks expire after 7 days and are session-scoped
  (§1.6); Desktop scheduled tasks skip a run if the Mac sleeps, and a closed lid sleeps it even
  with "Keep computer awake" (§1.6); a Stop hook gated by a project-level state file loops
  every session in that project (§1.7, reported).
- **Instructions in prose are skipped**: "Prose is documentation. Checklists and graphs are
  instructions." (§1.12).

### 2.3 Ideas for Baton, mapped to the open tickets

Ideas needing a third-party package or a hosted service are marked **[3rd-party]** or
**[hosted]**; everything else uses the CLI, hooks, files, git and `launchd`, which the Mac has.

**Relay or conductor.**
- The evidence favours a *relay*: a thin deterministic runner whose only judgement is
  "is there a handover artifact, and which prompt in it is eligible", not a Claude session
  that supervises other sessions. Symphony's tick (reconcile → validate → fetch → dispatch),
  Carlini's eight-line loop, and Anthropic's driver script are all code; every
  Claude-as-orchestrator source reports nudging, misreporting, or heartbeat scaffolding
  (Deacon, Boot, Witness) to keep it honest (§1.9, §1.10).
- Symphony's restart rule is directly reusable: no durable orchestrator database; rebuild
  state at start from the tracker and the filesystem (§1.13). For Baton the "tracker" is the
  target project's `docs/MILESTONES.md`/briefs plus `claude agents --json`, and the filesystem
  is the handover artifact per milestone. The run record the map lists as "Not yet specified"
  has a template in Symphony's `RunAttempt` (issue, attempt, workspace, started_at, status,
  error) and `LiveSession` (session id, last event, last timestamp, tokens, turn count) fields.
- What keeps Baton alive: `orch`'s advice is a process manager (`launchd`) for the scheduler
  and the watcher (§1.10). The in-product alternatives each have a documented gap: `/loop`
  needs an open or backgrounded session and expires in 7 days (§1.6); Desktop scheduled tasks
  stop when the Mac sleeps (§1.6); routines are **[hosted]**. A `launchd` agent with a
  `StartInterval` running a shell relay is the only option none of the sources caveat.
- Superpowers' "Rulings, not stalls" (§1.12) suggests where the model's judgement *should*
  sit: inside the milestone session, which already writes the handover; the relay never
  decides scope.
- Testing without quota: Agentainer's "key-free bash-loop mock agents" (§1.10) and
  ralph-claude-code's `--dry-run` (§1.8) are the precedent for a stub session that emits the
  same artefacts (`claude agents --json` rows, a transcript tail, a handover file) so the relay
  can be exercised end to end.

**What stops a session, and what happens next.**
- Adopt a fixed taxonomy before writing handlers, as Symphony and `/goal` do. The reported
  classes are: *transient* (rate limit, overload — keep the goal, wait, retry the same
  instruction; LeiShi's watchdog wording "this was a TEMPORARY rate limit, not a bug" exists
  because the model otherwise works around it, §1.10); *usage limit* (ralph-claude-code's
  auto-wait in unattended mode, §1.8; the map already records the `rate_limit` synthetic
  record and that auto-wait is not offered under `--bg`); *unrecoverable* (`/goal`'s list —
  auth, credits, context overflow, model unavailable — §1.6); *question or permission* (waiting
  for input: Symphony forbids indefinite stalls and the high-trust posture fails the run,
  §1.13); *stall* (no events for N minutes: Symphony 5 min, §1.13; `/goal`'s "no tool use for
  several turns", §1.6); *crash* (process gone while state says running: `orch watch`,
  Agentainer's "dead" reconciliation, §1.10); *ended without a handover* (Anthropic's
  "declares victory" and "half-implemented" modes, §1.2).
- For "ended without a handover", the sources give two responses that can be combined: a
  Stop hook that blocks the turn with the reason "the handover is missing; produce it" (the
  Ralph plugin's `{"decision":"block","reason":…}` shape, §1.7, capped at 8 by Claude Code per
  §1.5 and the map's hooks facts), and, if the session still ends, a resume with a
  continuation instruction rather than the original prompt — Symphony's "continuation turns
  SHOULD send only continuation guidance" (§1.13). The map already records `--bg --resume <id>`
  semantics.
- The brief's recovery clause is the same device as `claude-progress.txt` + `git log` (§1.2)
  and Superpowers' ledger with `Task <N>: complete` lines (§1.12): the next session trusts the
  artefact and git, not memory. Superpowers' note that the ledger must name *which plan* it
  belongs to (a stray ledger is another plan's progress) applies to a handover file when two
  milestones run at once.
- Retry with exponential backoff, capped (Symphony: 10 s doubling to 5 min; ralph-orchestrator:
  consecutive-failure limit 5), and a per-milestone attempt counter passed into the resumed
  session (Symphony's `attempt` template variable), so a session can tell it is the third try.

**Where an escalation goes.**
- Every source with unattended operation keeps a durable *place* for things needing a human,
  separate from the notification: a triage inbox (§1.14), a `Human Review` tracker state
  (§1.13), a blocking question thread with a timeout (§1.8 **[3rd-party]** Telegram), a
  problems view (§1.9). For Baton this argues for an escalation record on disk (milestone,
  session id, kind, the exact question or prompt text, time) that the notification points at,
  and that the relay treats as "this lane is parked until the record is resolved".
- Timeouts on escalations: ralph-orchestrator blocks "until a response arrives or times out"
  (§1.8); `/goal` caps idle check-ins at three between prompts (§1.6). An escalation that ages
  out should not be retried silently; it stays parked.
- Symphony's boundary applies: the session moves the state (writes the escalation or the
  handover); the relay only reads it. The map's Remote Control finding covers answering a
  permission prompt or question from the phone; the escalation record is what makes a
  one-way channel (`display notification`, iMessage) sufficient for the rest.
- Convert as many escalations as possible into rulings: Superpowers' four stop reasons are
  the only things that stop a running plan; everything else is decided and logged with its
  cost-if-wrong (§1.12). The kickoff prompt's "what to settle rather than inherit" section is
  where Baton can pre-authorise rulings.

**Permissions for a session nobody is watching.**
- Two documented forms fit a `--bg` dispatch: a pre-allow list in settings (Cherny's own
  practice, checked into `.claude/settings.json`, §1.1) layered per session via `--settings`
  (map fact), or `--permission-mode auto` (§1.5). The documented risk with auto is specific to
  `-p`: it "aborts if the classifier repeatedly blocks actions" (§1.5) — whether the same
  applies under `--bg` is unverified and belongs in the watching prototype's list.
- The `dontAsk`/skip-permissions route is used only inside a sandbox or container by every
  source that names it (§1.1, §1.4, §1.10); Reclaim's own rules (never removal on real user
  data; Trash-first) make a container-free skip mode inappropriate.
- A `PermissionRequest` hook that auto-answers a fixed set is documented as a hook event
  (§1.6 Zarif summary; the map's hooks research is the authority) and is reported as team
  practice ("permission requests can be routed to Opus via hooks for auto-approval", team-tips
  summary at https://blog.enkr1.com/boris-cherny-claude-code-workflow/ — secondary,
  unverified). twaldin's `watch_agents` is the tmux-era version of the same idea (§1.10).
- Symphony's rule is the design constraint: a permission prompt "MUST NOT leave a run stalled
  indefinitely" — either pre-decided, auto-resolved, or escalated with the lane parked.

**Dispatching more than one at once.**
- Use Superpowers' machine-checkable test for the conflict check: two units may run together
  only when their file lists are disjoint *and* neither depends on the other; "when overlap is
  uncertain, serialize" (§1.12). Reclaim's `CLAUDE.md` already frames the §5 "Expected files"
  lists as proposed, not exhaustive — the sources' answer to that is to make a session declare
  its files as it goes (Carlini's `current_tasks/` lock files in git, §1.4), so a second
  dispatch can be refused on a live claim rather than on a stale list.
- Cap concurrency globally and per lane (Symphony `max_concurrent_agents` and
  `_by_state`, §1.13). LeiShi's numbers — ~41K tokens of overhead per session, "start with 2
  workers", rate limits arrive with several workers (§1.10) — are the only published sizing
  for one machine on a subscription.
- Expect convergent failure on a shared bottleneck (Carlini, §1.4): two milestones that both
  need `Reclaim/AppModel.swift` or `docs/DECISIONS.md` will collide however the lists are
  drawn; the sources' fixes are a serial merge step (Refinery, §1.9) or decomposition by an
  oracle. For Baton the cheap form is the existing discipline rule (stage only your own paths;
  D-numbers taken at write time) plus a relay that never dispatches two milestones whose
  briefs name the same `ReclaimCore` sources.
- Agent teams provide file-locked task claiming and a lead-visible permission prompt, but are
  experimental, disabled by default, and documented with "known limitations around session
  resumption … and shutdown" (§1.6) — recorded, not recommended for v1.

**Which model runs which milestone, machine-readably.**
- Superpowers is the most explicit rule set: least powerful model that can do the role;
  mechanical → cheap, integration → standard, architecture and the final review → most
  capable; escalate the model on the fourth fix round (§1.12). Its measured June 2026 result
  (Opus controller, conditional Haiku implementers, review packet pre-baked) is the only
  published cost figure for that split. This matches the map's allocation rule (scarce model
  by marginal value) and adds "escalate on repeated failure" as a mechanical trigger.
- Cherny's January position — one model for everything "since you have to steer it less …
  it is almost always faster" (§1.1) — is the counter-evidence for a one-person project where
  steering costs attention; the Neuron write-up records the same person later running
  routines on selected models per routine (§1.6 routines have a model selector).
- Machine-readable carriers seen in the wild: YAML front matter on the repo-owned
  `WORKFLOW.md` with typed getters, defaults and hot reload (§1.13); subagent frontmatter
  `model:` (§1.5); `.ralphrc` (§1.8); the desktop task's `SKILL.md` frontmatter (model is a
  picker, not in the file, §1.6); a `--model` flag per spawn (§1.10). For Baton the natural
  carrier is front matter on each milestone brief (model, lane, expected files, dependencies)
  read by the relay, with the dispatch flag `--model` as the mechanism (map fact), and a
  per-run override recorded in the run record. The `/goal` evaluator model
  (`ANTHROPIC_DEFAULT_HAIKU_MODEL`) is a separate, cheap knob if Baton uses `/goal` inside a
  session (§1.6).

**Watching a dispatched session.**
- The signals the sources actually use, cheapest first: process liveness versus recorded
  state (`orch watch`, Agentainer's dead/stale-busy reconciliation, §1.10); event inactivity
  with a threshold (Symphony 5 min stall, 1 h turn silence, §1.13); git activity (`orch`'s
  commit watcher notifies immediately instead of waiting for the next check-in, §1.10);
  status files the session itself writes (LeiShi's `workers/*.json`, §1.10; Baton's handover
  artifact); a transcript tail (the Ralph hook reads the last assistant message from
  `transcript_path`, §1.7 — the map records the transcript format). `claude agents --json` and
  `claude logs` (map facts) cover the first and last of these without tmux.
- Adaptive polling with backoff is the norm: 30/120/300 s by worker state (§1.10); `/goal`
  check-ins at 30 min doubling to 2 h (§1.6); patrols that "gradually go to sleep" (§1.9). A
  fixed 1-second scheduler is what the in-product cron does, but its prompt only fires when
  the session is idle (§1.6), which is itself a usable "session is between turns" signal.
- Avoiding collisions with a human who attached: LeiShi's `.ready` handshake sends nothing
  unless the pane is idle (§1.10); scheduled prompts wait for the turn to end (§1.6). The
  map's "knowing a human took over" item can start from "last input came from the terminal,
  not from Baton" in the transcript; no source solves it directly.
- For viewing, Cherny's current setup is agent view plus the desktop app plus Remote Control
  from the phone (§1.1, §1.6); the Zenn comparison's "monitoring" class of tools (cmux, crmux)
  is the precedent for a viewer that never types (§1.11) — all **[3rd-party]** if adopted as
  tools, none needed for the mechanism.

### 2.4 Flags

- **[3rd-party]**: Gas Town/Beads (Go, tmux, Dolt), ralph-orchestrator (Rust, Telegram),
  ralph-claude-code (bash + Python parts), ralph-loop-agent (npm), Tmux-Orchestrator (tmux,
  Python helper), LeiShi1313 and twaldin (tmux, jq), orch (Go, SQLite), Agentainer (Python),
  Claude Squad (Go), Vibe Kanban (sunsetting), Conductor (closed source), Crystal (dead),
  Nimbalyst (commercial), Superpowers (plugin — the patterns above are reusable without
  installing it).
- **[hosted]**: Routines and Claude Code on the web, Symphony's trackers (Linear, GitHub
  Issues, Jira, Asana, GitLab), Codex Automations and Cloud, E2B sandboxes, Telegram.
- **Python**: the Anthropic quickstart harness, Tmux-Orchestrator's `tmux_utils.py`,
  Agentainer's `lib/cron.py` and ralph-claude-code's Python components are pattern sources
  only.
- **Unverified in this research**: the Business Insider quote (cited via Mint); the Meta
  @Scale and Acquired Unplugged recordings (cited via write-ups); the March 30, 2026 thread
  (cited via summaries); Symphony "spec v1.1 / Kata CLI"; the ralph-wiggum plugin regression
  report; the `terraform destroy` and Codex "1M lines" anecdotes; team-practice claims that
  appear only in tip summaries (permission auto-approval via a hook).
