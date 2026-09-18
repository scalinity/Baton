# Baton V2 findings

Audit of the working tree at `f230a8037e4fd2aa341dac0d88dab1c671a28c99`, on `main`. The tree was clean before this document was written. This is an audit of the existing implementation, not a V2 specification. “Limitation” includes deliberate V1 boundaries when they prevent use in an unfamiliar project; it does not imply that every boundary was an implementation mistake.

Evidence references are repository-relative `path:start–end`, using one-based line numbers at the audited revision. **INFERRED** labels consequences derived from code or the plausibility of an absent capability. Statements attributed to milestone evidence or prototype research are historical repository records, not a fresh verification of Claude Code, macOS, or the installed relay.

## READ COVERAGE

The inventory contained **5,495 tracked files**, including **243 scenario directories**. All current source, configuration, scripts, tests, documentation, and tracked prototype history were read before this report was written.

| Directory / files | Read | Treatment |
|---|---|---|
| Root | `CLAUDE.md`, `CONTEXT.md`, `CONTRACT.md`, `install.sh` | Full text, including the foundation notice and installation recipe. |
| `bin/` | `baton` | Full verb table, environment setup, and module loading. |
| `lib/` | All 18 shell files | Full code and comments; handoff, dispatch, recovery, permissions, notification, and lifecycle call paths traced. |
| `hooks/` | All three hooks | Full code and comments. |
| `launchd/` | `com.baton.tick.plist` | Full configuration and comments. |
| `notify/` | `Baton.applescript` | Full posting, reopen, and click handlers. |
| `docs/`, `docs/adr/`, `docs/milestones/` | All 17 files | SPEC, ARCHITECTURE, DECISIONS, MILESTONES, the foundation handoff, ADR, and all 11 briefs including completion evidence and prompts. |
| `tests/` | All 5,398 files | Runner, loaders, five shims, hook payloads, base project, and all scenario commands, inputs, expected states, and output files. Exact repeated lines were read once; unique lines retained their representative file and original line number. Long repeated test strings were represented by their literal repeated unit and count. This was content review, not a claim that the suite passed during this audit. |
| `.scratch/baton/issues/`, `.scratch/baton/research/`, `.scratch/baton/prototype/`, `.scratch/baton/MAP.md` | All 52 tracked files | All issue discussions, four research documents, prototype scripts/settings/prompts, and 20 observation files. Repeated text already read elsewhere was collapsed. Observation JSON was read as a first record plus exact field deltas; unchanged polling spans were collapsed with line spans, counts, and timestamps. Historical proposals were distinguished from current code. |
| `.claude/worktrees/` | Directory inspected | Empty; no content to read. |

**Skipped:** `.git/` object storage, reflogs, index, and administrative files were not exhaustively read: they are repository history/metadata, not the current implementation. Git was used to establish revision, cleanliness, tracked inventory, branches, and ancestry. The referenced foundation commit `48cab089dbac1f6de9c9a29b01d1ddcea8ef853e` exists and is **not** an ancestor of HEAD; its alternative historical tree was not audited as the current implementation. No dependency, build-output, or binary directories existed in the working-tree inventory to skip; the `.icns` fixtures are text stand-ins.

**Outside the repository:** the installed `~/.baton/`, live `~/.claude/`, Reclaim, other worktrees, OS grants, applications, external skill definitions, and linked web pages were not inspected as current runtime evidence. Their references inside this repository were read. Those boundaries are reflected in UNKNOWNS.

**Verification performed:** read-only static tracing and isolated, in-memory calls to existing library functions. These demonstrated permissive graph parsing, shallow artifact validation, acceptance of the repository's first commit as `merged_as`, a wait remaining due after a delivered resume, crash suppression after a consumed ending, the ladder restarting across attempts, and timestamp-colliding park resolution. No session, service, notifier, installation, or build was run. The full test runner was not executed: its installation scenarios invoke the real installation recipe, including `osacompile` and `codesign` (`tests/scenarios/install/cmd:1–14`; `install.sh:101–147`). Historical test counts below are identified as recorded evidence.

## ARCHITECTURE MAP

### Entry points and boundaries

- **CLI:** `bin/baton` loads all libraries, establishes nine runtime seams, removes inherited `CLAUDE*` variables except `CLAUDE_CONFIG_DIR`, and dispatches seven verbs: `tick`, `plan`, `dispatch`, `status`, `answer`, `allow`, `wake`. Every operational verb takes the same filesystem lock; help does not. Evidence: `bin/baton:6–122`; `lib/dispatch.sh:167–183`.
- **Scheduler:** a GUI LaunchAgent invokes the installed shell and installed CLI with `tick` every 60 seconds. It sets UTF-8 locale, allows child process groups to survive the tick, and directs streams to fixed files. Evidence: `launchd/com.baton.tick.plist:21–45`.
- **Installer:** copies the CLI, libraries, and hooks; copies and signs a shell; creates state directories and initial config; registers its own repository; composes wake settings; compiles/signs a notifier; copies a missing LaunchAgent without loading it. Evidence: `install.sh:8–167`.
- **Session callbacks:** Stop gate, StopFailure, and statusLine are shell commands injected through a generated Claude settings file. They write per-session files; they do not append the dispatch log. Evidence: `lib/dispatch.sh:74–94`; `hooks/stop-gate:7–67`; `hooks/stop-failure:6–39`; `hooks/statusline:4–15`.
- **Native notification entry:** the applet's `run` posts pending messages or opens the newest target; `reopen` posts pending messages. Evidence: `notify/Baton.applescript:17–85`.
- **Test entry points:** `tests/run.sh` runs scenario commands twice against temporary fixture repositories and shims; `tests/consume-once.sh` exposes inbox consumption alone, with production-home defaults unless overridden. Evidence: `tests/run.sh:22–189`; `tests/consume-once.sh:7–34`.

The shell relay embeds no model inference call. It starts Claude sessions that perform the coding and judgment. The wake session is also a model-driven session: its prompt tells it how to translate a person's message into a CLI invocation. Evidence: `lib/dispatch.sh:188–198`; `lib/lifecycle.sh:137–155,232–263`; `docs/adr/0001-baton-never-calls-a-model.md:3–15`.

| Modules | Responsibility |
|---|---|
| `lock.sh`, `log.sh` | One shared lock, clock, log append/read, rows convenience reader, prompt sidecars and hashes. |
| `plan.sh`, `templates.sh` | Markdown-table parsing, eligibility, registration lookup, fixed session names and continuation/prompt text. |
| `inbox.sh` | Artifact checks, repeat comparison, archive/reject moves, consumed events and immediate escalation. |
| `derive.sh` | Open attempts, current session through forks, in-flight/no-row split, parks, takeovers, waits, holds, counters, archive joins, gap. |
| `rows.sh` | Strict fleet read, transcript activity, crash sightings, stalls, long-running notices, live questions, takeovers, gap notices. |
| `stops.sh`, `waits.sh`, `declared.sh` | Fixed error taxonomy, stop/resume, retry ladder, model holds, Fable reserve, unfinished/blocked handling, broken-main cascade. |
| `candidates.sh`, `dispatch.sh` | Historical dispositions intersected with plan, holds/order, worktree/settings/prompt creation, Claude dispatch. |
| `escalate.sh`, `answer.sh` | Park and resolution events, edit comparisons, message wording, rulings, hand-back, allowlist widening. |
| `lifecycle.sh` | Finished-session selection, idle stopping, wake verb and persistent wake session. |
| `notify.sh`, `status.sh`, `tick.sh` | Notification transport, human-readable view, complete scheduler call sequence. |

The module inventory matches the libraries loaded in `bin/baton:18–38`; responsibilities are from the full files, rather than the historical “Interfaces by milestone” table.

### Handoff control flow

1. **The coding session performs the close-out.** Its contract calls for checks/review, evidence and decision records, a branch commit, merge into `main`, the target's standing check on the combined tree, successor-prompt refresh, and a `done` plan cell. Baton does not perform or independently observe those checks. Evidence: `CONTRACT.md:28–40`; `CLAUDE.md:31–62`.
2. **The session writes JSON** to `~/.baton/inbox/<milestone>-<session>.json`, first under `.tmp`, then renames and prints the JSON last in a `baton` fence. Required envelope: `baton:1`, canonical project path, milestone, session, outcome, written_at. Complete adds merged_as and eligible entries; asking adds a question; stopped adds a fixed reason. Evidence: `CONTRACT.md:42–57,70–94`.
3. **Stop hook:** an archived complete artifact for this session/milestone disables the gate. Otherwise a nonempty background-task list or an existing inbox file permits the stop. A printed fence naming the session can become the file. With neither file nor fallback, the gate blocks once; on the next stop it writes `stopped/no-handover`. **StopFailure** writes `stopped/api-error` unless completion is archived or an inbox file already exists. Evidence: `hooks/stop-gate:16–66`; `hooks/stop-failure:15–38`.
4. **Tick consumption:** iterate inbox `*.json` in filename order. Compare the complete JSON value with retained archived copies before running validation. A repeat moves to archive and records `repeated`, without routing again. Otherwise validate envelope/outcome, transcript existence, registered project, commit ancestry for complete, and eligible-entry brief headings on main. Evidence: `lib/inbox.sh:103–195,271–377`.
5. **Accepted:** move to archive, stop a Baton-dispatched asking session if a live job is known, append `consumed`, and park asking/merge-failed/other/main-broken as appropriate. **Rejected:** move to rejected, record the rule, park the lane. Bad brief pointers drop/park the indicated successor while retaining the complete artifact. Orphan `.json.tmp` files are rejected when the listing has no live row for their writer. Evidence: `lib/inbox.sh:217–269,360–469`.
6. **Subsequent work:** the plan supplies dependency eligibility; archived complete handovers supply `run/wait/held` dispositions. The newest *consumed* handover mentioning a milestone wins. Gates can override a disposition. Omission and disagreement can park a candidate. Evidence: `lib/candidates.sh:33–163,208–279`.

### Kickoff and tick control flow

**Bootstrap:** a person registers the target and supplies a starting handover, or uses `dispatch <project> <milestone>` by hand. Registration alone does not cause the first automatic dispatch. Evidence: `install.sh:44–77`; `lib/candidates.sh:118–127`; `lib/dispatch.sh:305–324`; `docs/milestones/M08.md:35–46,59–80`.

**Scheduled tick:**

1. Flush notification spool; read the fleet once with the strict reader.
2. For each registration, read/parse the current plan file and run `git rev-parse HEAD`. A failed self-check parks that project. A failed fleet read prevents the remaining steps and suppresses the completion marker.
3. Consume the global inbox; derive account-wide holds and the Fable reserve.
4. For each project with a readable plan, resolve edit/question parks, detect takeover, inspect crashes/stalls/long runs/questions, route waits and endings, and maintain caffeinate holders.
5. Intersect plan eligibility with dispositions, excluding open lanes, parks and named live rows. Collect candidates across projects.
6. Stop sufficiently old idle finished sessions; maintain the wake session.
7. Apply holds, order candidates, and dispatch under the ordinary-dispatch cap.
8. Check for a gap; release the lock and write last-tick when tick_run returns zero.

Evidence: `lib/tick.sh:114–142,210–277,283–396`.

**One dispatch:** obtain model/effort/remote from the plan; count attempts; ensure sibling `<Project>-<Milestone>` worktree on the lowercased milestone branch, from `main`; compose settings; read `main:docs/milestones/<ID>.md` under `## Copy-ready session prompt`; replace its `WHAT ELSE IS IN FLIGHT.` paragraph; invoke `claude --bg` in the worktree with name/model/optional effort, bypassPermissions and settings; parse the short ID; poll for the row/pid; write the prompt sidecar/hash; start caffeinate; append dispatch. The sidecar and event are written **after** launch. Evidence: `lib/dispatch.sh:32–123,185–198,234–303`.

**Recovery and operator input:** API waits use stop-then-flagless-resume; no-handover/crash/refused-resume feed a failure ladder; unfinished and context errors have separate consecutive-ending counts. Rulings resolve one park, stop/resume its session, then record resolution if the CLI says delivered/forked. A takeover hand-back uses “continue.” Model changes in the plan affect new dispatches; resumes restore saved options. `allow` edits the project permission file and the stable dispatch-settings file. `wake` addresses the newest finished session for a milestone, following recorded wake copies. Evidence: `lib/stops.sh:33–71,218–298,307–568`; `lib/declared.sh:15–153`; `lib/answer.sh:67–222,257–398`; `lib/lifecycle.sh:24–38,272–361`.

### State and location

Let **H** be `BATON_HOME`, default `$HOME/.baton`. State is local files, not an in-memory service or database.

| State | Location and writers/readers |
|---|---|
| Installed executable code and shell | `H/bin/`, `H/bin/lib/`; installer writes; scheduler and hooks execute. `install.sh:11–34`. |
| Global numbers/model aliases | `H/config.json`; install creates if absent; helpers read with defaults. `install.sh:36–42`; `lib/derive.sh:15–18`. |
| Project registry and permission policy | `H/projects/<key>/{project.json,permissions.json}`; installer registers itself, other registrations are manual; `allow` changes allowlists. `lib/plan.sh:219–237`; `lib/answer.sh:286–344`. |
| Effective Baton dispatch settings | `H/settings/<project>-<milestone>.json`; recomposed at dispatch, widened in place; saved path used by resumes. Wake has `H/settings/wake.json`. `lib/dispatch.sh:74–94`; `install.sh:79–99`. |
| Exact prompts and rulings | `H/prompts/<session>/<n>.txt`; sidecar_write creates highest existing number + 1; log stores path/hash. `lib/log.sh:79–107`. |
| Pending/consumed/rejected handovers | `H/inbox/`, `H/archive/`, `H/rejected/`; sessions/hooks write inbox; relay moves files and derives dispositions from archives. `lib/inbox.sh:217–469`. |
| Dispatch/recovery history | `H/log.jsonl`; log_event is production's sole append function; readers load the full JSON stream. Events determine attempts, forks, waits, parks, resolutions, holds and lifecycle state. `lib/log.sh:11–77`; `lib/derive.sh:121–506`. |
| Latest session telemetry | `H/status/<session>.json`; statusline overwrites atomically; reserve reads seven-day usage. `hooks/statusline:7–12`; `lib/waits.sh:190–250`. |
| Lock and completion marker | `H/lock/{pid,at}`, possible `H/lock.stale.<pid>`; `H/last-tick`; lock/tick helpers write. `lib/lock.sh:6–21`; `lib/tick.sh:41–67,389–396`. |
| Notifications | `H/notify/spool/<epoch>-<pid>-<counter>`, dot-prefixed staging files, `H/notify/target`; relay spools, applet posts/deletes and records newest target. `lib/notify.sh:70–110`; `notify/Baton.applescript:42–85`. |
| Scheduler configuration and output | `$HOME/Library/LaunchAgents/com.baton.tick.plist`; shipped plist names `/Users/danny/.baton/launchd.out` and `launchd.err`. `install.sh:150–167`; `launchd/com.baton.tick.plist:25–43`. |
| Target plan, briefs, code and Git state | Registered canonical checkout; sibling milestone worktrees and lowercased branches. Baton reads the plan from disk and briefs from main; the coding session commits/merges/refreshes. `lib/tick.sh:121–141`; `lib/dispatch.sh:35–59,100–110`; `CONTRACT.md:28–40`. |
| Claude-owned state | `BATON_TRANSCRIPTS` (default `~/.claude/projects`), `BATON_JOBS` (default `~/.claude/jobs`), `BATON_DAEMON_LOG` (default `~/.claude/daemon.log`); CLI writes, relay reads. Fleet comes from `claude agents --json`. `bin/baton:6–16`; `lib/derive.sh:70–119`; `lib/notify.sh:47–60`. |
| Wake working directory | `${BATON_HOME}-wake`; created when a fresh wake session starts. `lib/lifecycle.sh:232–243`. |
| Transient files | `TMPDIR` or `/tmp` captures of CLI streams; adjacent `.tmp` files; `H/bin/.Baton-build` during installation. `lib/dispatch.sh:189–196`; `lib/stops.sh:240–250`; `install.sh:121–147`. |

### Environment assumptions

These are the assumptions observable in the implementation and its contract; the repository cannot establish whether a particular target satisfies them.

- **Host/tooling:** macOS launchd GUI domain, AppleScript/Foundation, open, osascript, caffeinate, codesign, osacompile, PlistBuddy, shell, jq, awk, Git, shasum and standard utilities are present and callable. The activity reader and test harness use BSD command forms. The scheduler has an applicable UTF-8 locale and the executable paths it names. Evidence: `launchd/com.baton.tick.plist:21–45`; `install.sh:19–34,101–147`; `lib/rows.sh:71–79`; `tests/run.sh:84–121`.
- **External setup:** a working authenticated Claude background service, bypass disclaimer, access to the target checkout from the service's process tree, usable hooks, long-lived transcripts, eligible Remote Control, mobile account/settings and Mac notification permission. FDA and hardware assumptions are explicitly documented; this audit did not verify them live. Evidence: `docs/SPEC.md:212–240`.
- **Git/project structure:** a usable canonical Git checkout, local main, readable committed briefs at fixed paths, writable sibling workspace locations, available lowercased milestone branches, and an existing directory at the expected worktree path representing the intended workspace. Evidence: `lib/dispatch.sh:35–59,100–110,254–264`; `lib/inbox.sh:33–58`.
- **Project protocol:** exact table vocabulary, M-number IDs, gate tokens, the seven-part kickoff anatomy and slot marker, session-side close-out discipline, and a starting handover or manual dispatch. Target setup/build/check/review knowledge lives in project instructions, not a Baton-executed setup stage. Evidence: `CONTRACT.md:9–57`; `lib/plan.sh:26–182`; `lib/candidates.sh:118–127`.
- **CLI compatibility:** output contains the recognised backgrounded/woke/copy phrases; short IDs, row IDs/pids/session IDs, transcript shapes, job-state bridge IDs, Stop/StopFailure and saved-options semantics continue to match the code. Evidence: `lib/dispatch.sh:13–29,146–164,188–210`; `lib/derive.sh:63–119,172–179`; `lib/notify.sh:47–60`.
- **Filesystem/identity:** one consistent H and matching Claude state roots; project keys and canonical paths remain stable; paths used inside generated shell commands have compatible spelling; rename and mkdir have local atomicity; retained archives and logs remain intact. Evidence: `lib/lock.sh:6–21`; `lib/inbox.sh:14–21,225–239,287–314`; `lib/dispatch.sh:78–88`.
- **Writers/concurrency:** operational verbs share the one lock; hooks and sessions obey the inbox protocol; other tools do not rewrite the log/archives or race session creation; coding sessions coordinate shared-main merges and respect the scope instructions themselves. Evidence: `lib/log.sh:16–36`; `CONTRACT.md:28–40`; `lib/templates.sh:22–34`.
- **Time and activity:** timestamps are usable, wall-clock movement is suitable for retry/age calculations, row liveness settles within the fixed windows, and transcript modification is a useful proxy for work. Evidence: `lib/derive.sh:20–57,305–339,484–505`; `lib/rows.sh:155–247,259–335`.
- **Human access:** notifications can be seen; the person can reach Claude.app or a terminal and distinguish a park from takeover/wait; the wake model follows its command-format instructions. Evidence: `lib/notify.sh:63–110`; `lib/answer.sh:160–222`; `lib/lifecycle.sh:137–155`.
- **Account/resource policy:** one global cap and shared model holds suit the host; seven-day status readings describe the account used by dispatch; Fable's reserve proxy and the fixed error taxonomy apply. Evidence: `lib/tick.sh:245–277`; `lib/waits.sh:117–266`; `lib/stops.sh:33–83`.

## LIMITATIONS — RANKED

Numbers below are the ranking, highest obstruction first. Criteria, in order: **(1)** whether a previously unseen project can enter the workflow at all without changing its conventions or environment; **(2)** whether the admitted project can be trusted to run the intended work without false completion, duplicate sessions, or interference; **(3)** whether an interruption can recover without undocumented intervention; **(4)** sustained operation, diagnosis and verification. Breadth breaks ties: a limitation affecting many ordinary projects ranks above an unusual edge case. Host/runtime exclusions are explicit even where V1 deliberately targeted this one Mac. This is a portability/operability ranking, not a security-severity score.

### 1. A target must first adopt Baton's document and handover contract

**Category:** cross-project portability. **What:** registration presupposes a migrated plan, conforming briefs, session close-out instructions, a permissions file, and a starting artifact. There is no automatic first run from an otherwise ordinary repository. M08 additionally asks a dispatched session to write registration paths its own deny rules prohibit.

**Evidence:** `CONTRACT.md:9–57`; `docs/milestones/M08.md:15–46,59–80,114–118`; `install.sh:44–77`; `lib/candidates.sh:118–127`.

**Prevents:** immediate handoff/kickoff in an unfamiliar project with its existing workflow. **User symptom:** M01's recorded Reclaim parse failed on the missing Model column (`docs/milestones/M01.md:311–317`). M08 records a required human settlement for registration writes, and its completion-evidence section is empty. Registration without a seed otherwise dispatches and escalates nothing (`docs/milestones/M06.md:238–239`).

### 2. The workspace and completion model require Git, main, and a sibling worktree convention

**Category:** cross-project portability. **What:** new worktrees originate from the literal local branch `main`, live beside the canonical checkout, and use lowercased milestone IDs as branches. Prompts and merge verification also name main literally.

**Evidence:** `lib/dispatch.sh:35–59,100–110`; `lib/inbox.sh:33–48`; `lib/templates.sh:22–34`; `CONTRACT.md:28–40`.

**Prevents:** unchanged use with another default branch, a repository without a local main, a non-Git directory, or a project that cannot write sibling workspaces. **User symptom (INFERRED):** worktree/prompt/merge-stage failures, or an instruction to merge into a branch inconsistent with the project's workflow. Project registration exposes no corresponding choices.

### 3. Validated brief pointers do not select the brief actually dispatched

**Category:** configuration. **What:** artifact validation accepts a brief path and heading and checks them on main, but dispatch always constructs `docs/milestones/<ID>.md` and `Copy-ready session prompt`. The in-force disposition drops the brief pointer. Recovery edit detection uses the same fixed location.

**Evidence:** `lib/inbox.sh:51–58,149–167`; `lib/candidates.sh:63–70`; `lib/dispatch.sh:254–264`; `lib/escalate.sh:90–93`.

**Prevents:** configuring a target's existing brief layout through the pointer the protocol carries. **User symptom (INFERRED):** a pointer passes consumption, then kickoff fails at another path or uses a different prompt; editing the referenced custom brief does not affect recovery.

### 4. A created worktree is treated as a ready coding environment

**Category:** environment and setup coupling. **What:** workspace preparation consists of Git worktree creation/reuse. New creation explicitly suppresses post-checkout hooks; dispatch then composes Baton settings and launches Claude. There is no transfer of ignored/local files or execution/check of a target setup routine on this path.

**Evidence:** `lib/dispatch.sh:35–59,235–266`; `lib/tick.sh:120–141`.

**Prevents:** assuming that a new workspace has the dependencies, local configuration, generated files, services or secrets available in the existing checkout. **User symptom (INFERRED):** the session starts successfully but cannot build/test/run the target, or spends the session discovering setup requirements. Projects relying on post-checkout initialization do not receive it from this worktree creation.

### 5. The dispatcher and recovery logic depend on one Claude Code protocol

**Category:** extensibility. **What:** Baton directly invokes `agents --json`, `--bg`, `stop` and flagless `--resume`; parses English output phrases; interprets Claude-specific row/transcript/job fields; and assumes the CLI supplies the generated hooks and saved-options behavior. Changing BATON_CLAUDE changes the executable, not this protocol.

**Evidence:** `lib/log.sh:72–76`; `lib/rows.sh:16–24`; `lib/dispatch.sh:13–29,137–164,188–210`; `lib/stops.sh:218–298`; `lib/derive.sh:70–119`.

**Prevents:** direct use with another coding runtime or a changed CLI protocol. **User symptom (INFERRED):** a real launch/resume may be classified as failure, or session liveness/ownership may be misread. The documented test history spans CLI 2.1.268–2.1.270, not an explicit supported-version range.

### 6. Installation is tied to macOS and Danny's paths

**Category:** environment and setup coupling. **What:** the shipped LaunchAgent hardcodes `/Users/danny/.baton/`; the CLI defaults to Danny's Claude executable; launchd-deny rules name Danny's Library path. Installation copies the plist unchanged even when BATON_HOME differs. Native notification/signing/sleep utilities and BSD stat are used directly.

**Evidence:** `bin/baton:6–14`; `launchd/com.baton.tick.plist:25–43`; `install.sh:19–34,73–75,115–147,156–166`; `lib/rows.sh:71–79`.

**Prevents:** a stock installation for another macOS user or home, and execution on an arbitrary OS. **User symptom (INFERRED):** installation reports one destination while the service still points elsewhere; native commands or executable paths fail. The exposed environment seams do not parameterize the shipped agent.

### 7. Target and user settings can change the session environment outside Baton's checks

**Category:** environment and setup coupling. **What:** Baton supplies a narrow settings object, without inspecting the effective combination of user/project/local/managed settings, plugins, MCP configuration, hooks or environment. It checks neither hook activation nor a session's ability to produce its first handover.

**Evidence:** `lib/dispatch.sh:74–94,188–198,274–292`; `lib/tick.sh:120–141`; repository research on settings inheritance and hook disabling: `.scratch/baton/research/background-sessions.md:424–452`, `.scratch/baton/research/hooks.md:241–263`.

**Prevents:** treating a successful dispatch into a previously unseen project as a verified Baton-controlled session. **User symptom (INFERRED):** project hooks, managed restrictions, disabled hooks, missing plugins or server consent can alter/block the run after admission. The current effective-settings behavior for any particular target remains unknown.

### 8. The runtime environment is not one coherent, relocatable profile

**Category:** environment and setup coupling. **What:** Baton's Claude-state defaults remain under HOME even when CLAUDE_CONFIG_DIR is preserved; other CLAUDE-prefixed authentication/configuration variables are removed wholesale. Hooks carry H explicitly, while the finish template and project contract direct session-authored artifacts to literal `~/.baton`. Non-CLAUDE variables remain inherited.

**Evidence:** `bin/baton:6–16,40–41`; `lib/dispatch.sh:78–88,167–183`; `lib/templates.sh:51–57`; `CONTRACT.md:42–44`; `docs/DECISIONS.md:103–103`.

**Prevents:** reliably selecting a separate state home, Claude configuration tree or credential profile with a single setting. **User symptom:** D-091 records an install reaching the probe home through inherited BATON_HOME. **INFERRED:** custom Claude roots require separate matching seams; a removed credential variable or a hardcoded handover path can break an otherwise valid session.

### 9. Project identity depends on names and exact path strings

**Category:** cross-project portability. **What:** installation uses the canonical checkout's basename as its key and does not revise an existing registration. Inbox lookup matches canonical paths by string equality. Keys also name settings, log history and operator targets.

**Evidence:** `install.sh:44–52`; `lib/inbox.sh:12–21`; `lib/plan.sh:219–237`; `CONTEXT.md:368–372`.

**Prevents:** seamless coexistence of same-basename projects, relocation, renaming, or alternate symlink spellings. **User symptom (INFERRED):** a second same-named install retains the first registration, an artifact naming an equivalent path is rejected as unregistered, or old history stays under a different identity. There is no identity migration in the CLI.

### 10. Generated shell commands assume unusually simple path/key spelling

**Category:** security and secrets. **What:** hook commands place H and project keys inside single quotes without escaping embedded apostrophes and leave the executable path unquoted. The wake prompt uses the same construction. Other path loops split command output on shell whitespace.

**Evidence:** `lib/dispatch.sh:78–88`; `lib/lifecycle.sh:140–152`; `hooks/stop-gate:23–25`; `hooks/stop-failure:19–21`.

**Prevents:** reliable use of homes/project keys containing spaces or apostrophes throughout the workflow. **User symptom (INFERRED):** hooks cannot execute, archived completion is missed, or generated commands parse differently from the intended argument values. At the command-construction boundary, shell metacharacters are an injection risk; no adversarial execution was performed.

### 11. The permission mechanism does not contain an unfamiliar project's session

**Category:** security and secrets. **What:** every dispatch runs with bypassPermissions. The guard checks only that deny has nonzero length, not that it contains the stated two classes or is a correctly shaped rule array. The installed rules intentionally omit Bash protection of bin and cannot cover indirect/relative access; writes outside the worktree and network access are not confined by Baton.

**Evidence:** `lib/dispatch.sh:77–88,188–192`; `install.sh:53–76`; `docs/DECISIONS.md:38–38,60–60`; `docs/SPEC.md:180–184`.

**Prevents:** interpreting “has deny rules” as a trustworthy safety boundary for arbitrary project instructions/tools. **User symptom (INFERRED):** a session can affect unrelated host or relay state while still satisfying Baton's admission check. This is a documented high-trust V1 choice; the report does not assume the existing user intended adversarial isolation.

### 12. Remote Control is compulsory, but remote reachability is not verified

**Category:** security and secrets. **What:** every generated dispatch setting enables Remote Control, including rows whose Remote cell is blank. That cell only changes question/stall interpretation. Baton has no separate notification transport to the phone, and neither successful connection nor phone delivery is an admission requirement.

**Evidence:** `lib/dispatch.sh:74–88,239–241,284–292`; `lib/rows.sh:277–290,345–357`; `docs/SPEC.md:143–145,218–225,343–356`.

**Prevents:** an explicit Baton setting for local-only sessions, and a guarantee that a remote operator can hear/answer a park. **User symptom (INFERRED):** Remote blank does not disable connection; an ineligible/offline connection leaves the expected UI/channel unavailable. The repository documents transcript storage on Anthropic's servers while connected; current external retention terms were not verified.

### 13. Completion verification proves ancestry, not the milestone's work

**Category:** session lifecycle. **What:** merged_as verification establishes that a hexadecimal value resolves to a commit ancestral to main. It does not bind that commit to the milestone's dispatch baseline, branch changes, standing-check result or acceptance evidence. The session supplies the other claims.

**Evidence:** `lib/inbox.sh:33–48,139–145`; `CONTRACT.md:28–40`; `docs/SPEC.md:173–174`.

**Prevents:** independently distinguishing a completed milestone from a plausible but false completion artifact. **User symptom (INFERRED):** successors may start with missing or unverified work. **Observed helper check:** the repository's first commit, `fae3016d7595a6bae93fd733d6230672df0b414c`, passes merged_as_verify at this HEAD. This is narrower than proving a false full handover was dispatched live.

### 14. Plan decisions and kickoff instructions are read from different snapshots

**Category:** state and persistence. **What:** eligibility, gates and model cells are read from the canonical working file; the prompt is read from committed main. No graph revision binds a handover or dispatch to either read. A Cleared token is checked for D-number syntax, not a committed decision or its author.

**Evidence:** `lib/tick.sh:120–141,303–315,354–365`; `lib/plan.sh:131–182,226–237`; `lib/dispatch.sh:100–110,254–264`; `CONTRACT.md:23–26`.

**Prevents:** one reproducible, committed definition of what was authorized and what context accompanied it. **User symptom (INFERRED):** an uncommitted gate/model edit changes scheduling while an uncommitted brief edit does not; a session or person can edit the plan between the tick's read and dispatch.

### 15. Artifact provenance is not bound to the current project/session attempt

**Category:** security and secrets. **What:** any matching transcript under the transcript tree and an independently registered project path satisfy the provenance checks. The file need not match a logged current dispatch, its workspace, or the hook caller. Authorship is inferred from reason, and older attempts' artifacts are still consumed.

**Evidence:** `lib/inbox.sh:103–138,184–194,206–214,383–391`; `lib/derive.sh:70–77`; `docs/DECISIONS.md:45–45`.

**Prevents:** establishing that an accepted message actually comes from the session authorized to speak for that lane now. **User symptom (INFERRED):** a mistaken or forged combination of a real transcript ID and registered project can enter the wrong history; a late older attempt can affect current dispositions/parks. The intended hand-started bootstrap explains why absence of a dispatch is accepted.

### 16. Sessions start before there is a durable dispatch record

**Category:** error handling and recovery. **What:** Claude launch and row discovery precede sidecar creation and the dispatch event. Resume delivery similarly precedes its sidecar/event; fork mapping is a further write. A timeout, process death or write failure in those windows can leave work running without the corresponding record.

**Evidence:** `lib/dispatch.sh:266–292`; `lib/stops.sh:240–294`; `lib/lifecycle.sh:337–353`.

**Prevents:** reconstructing every actual launch/delivery solely from recorded attempts. **User symptom (INFERRED):** a session may be visible in Claude but absent from Baton's lane tracking, a ruling may be delivered twice after retry, or an unresolved copy may coexist with the original. A named live row can suppress some duplicate dispatches but does not reconstruct ownership or the missing event.

### 17. Moving a handover and recording/acting on it are separate operations

**Category:** state and persistence. **What:** consume/reject moves the file before the event and remaining effects. Recovery computes unrecorded archives, but the tick has no reconciliation of those files into lost consumed events or parks. A 4 KB log refusal or I/O failure can also interrupt the sequence after the move.

**Evidence:** `lib/inbox.sh:242–268,394–453`; `lib/log.sh:16–36`; `lib/derive.sh:250–298`; `lib/tick.sh:326–378`.

**Prevents:** atomic handover acceptance and recoverable delivery of all consequences. **User symptom (INFERRED):** an artifact has left the inbox, yet its lane remains open or its stopped asking session has no park to answer. Bound/truncated fields reduce some errors but do not make the move, event, stop and escalation a transaction.

### 18. The mailbox has one mutable slot per session ending

**Category:** state and persistence. **What:** a session's successive endings and its hooks reuse `<milestone>-<session>.json` and the same temporary name. An existing file is enough for both hooks to stand down; the consumer checks then moves a path, without holding a lock shared with the writers.

**Evidence:** `CONTRACT.md:42–44`; `hooks/stop-gate:28–45,61–66`; `hooks/stop-failure:24–38`; `lib/inbox.sh:338–375,383–408`.

**Prevents:** distinguishing every ending through concurrent writing, replacement, validation and consumption. **User symptom (INFERRED):** an earlier queued file can suppress a later hook ending, two writers can contend for the same temporary file, or the bytes moved can differ from those checked. A hook still writing after its row loses its pid can also meet the immediate orphan sweep.

### 19. A late different handover can put older scheduling advice back in force

**Category:** state and persistence. **What:** dispositions rank by first-consumption order, not the ordering of work or refreshes that produced different handovers. Filename order determines which queued files are consumed first in one pass.

**Evidence:** `lib/inbox.sh:337–359`; `lib/candidates.sh:33–75`; `docs/DECISIONS.md:108–108`; `docs/milestones/M07-d.md:209–212`.

**Prevents:** reliable ordering of independent parallel close-outs. **User symptom (INFERRED, explicitly documented):** lane A merges before B but finishes its checks later; A's subsequently consumed advice supersedes B's advice for a shared successor. The repeat guard does not cover two different handovers. Plan gates and dependency checks constrain, but do not remove, this case.

### 20. Repeat protection depends on complete value equality and retained archive copies

**Category:** state and persistence. **What:** every field, including written_at, participates in equality. With no archived copy remaining, the same handover is accepted as new. Existing duplicate consumed events are not rewritten by the guard.

**Evidence:** `lib/inbox.sh:271–314`; `tests/scenarios/consume-repeat-archive-gone/cmd:1–2`; `tests/scenarios/consume-repeat-new-written-at/expected/home/log.jsonl:1–4`; `docs/milestones/M07-d.md:213–216`.

**Prevents:** identifying a logical handover across resubmission with changed metadata or archive loss. **User symptom (INFERRED):** reissued JSON can reapply a park, ending or disposition when a field changes, and archive cleanup changes whether replay is suppressed. The equality rule also deliberately preserves truly different endings; it is not a blanket duplicate-message guarantee.

### 21. Existing workspace reuse does not establish repository or branch identity

**Category:** cross-project portability. **What:** if the expected sibling directory exists, worktree_ensure only asks Git for HEAD. It does not establish that the directory is a linked worktree of the registered repository, that it is the top-level workspace, or that the checked-out branch is the requested milestone branch.

**Evidence:** `lib/dispatch.sh:35–59,246–250`; `tests/scenarios/dispatch-worktree-stage/cmd:1–2`.

**Prevents:** safe reuse in a directory layout Baton has not previously controlled. **User symptom (INFERRED):** an unrelated Git directory or a worktree switched to another branch can receive the session, while the slot line names Baton's computed branch. The existing refusal fixture covers a non-Git directory, not these valid-Git mismatches.

### 22. Admission conditions differ between dispatch paths

**Category:** session lifecycle. **What:** redispatch checks that a plan row still exists, the project is not parked, and the model is not held. It does not require blank Status, completed dependencies, cleared gates, or the ordinary dispatch verb's live-name guard. It then calls dispatch_try directly. Manual dispatch checks plan eligibility and live name but does not check the ordinary scheduler's parks, model holds or existing open-lane exclusions.

**Evidence:** `lib/stops.sh:331–357`; `lib/declared.sh:86–116`; compare `lib/dispatch.sh:307–324` and `lib/candidates.sh:262–276`.

**Prevents:** treating plan and relay admission state as consistent controls on all new sessions. **User symptom (INFERRED):** a failure-driven replacement can start a milestone the plan no longer admits, or start alongside the old process when it still has a pid. The broad project park and model-hold guards do not cover these conditions.

### 23. The cap does not bound all sessions Baton starts or keeps alive

**Category:** session lifecycle. **What:** the cap is applied to ordinary candidate dispatch. Redispatch, resumes, manual dispatch and wake take other paths; finished sessions and the wake session are outside its in-flight count. Step 4 can create new attempts before step 7 counts against the original fleet snapshot.

**Evidence:** `lib/tick.sh:231–277,296–301,354–375`; `lib/stops.sh:338–357`; `lib/dispatch.sh:307–324`; `lib/lifecycle.sh:59–109,165–263,272–361`; `docs/DECISIONS.md:84–84`.

**Prevents:** interpreting cap as a host-wide resource bound. **User symptom (INFERRED):** a configured cap of two can coexist with more active processes, revived waits or replacement sessions. D-072 explicitly records redispatch outside the cap; resource use also includes session-owned children not counted as Baton lanes.

### 24. Sessions dispatched together receive incomplete concurrency context

**Category:** session lifecycle. **What:** dispatch_run passes the same original rows to every dispatch_one. The latter derives “also in flight” by intersecting updated log events with those old rows. A session started earlier in that batch has no row in that snapshot.

**Evidence:** `lib/tick.sh:245–268,296–301,375–375`; `lib/dispatch.sh:254–264`; `lib/derive.sh:172–179`; `tests/scenarios/held-plan-wins/expected/home/prompts/0badc0d1-0000-4000-8000-000000000000/1.txt:1–9` and `tests/scenarios/held-plan-wins/expected/home/prompts/0badc0d2-0000-4000-8000-000000000000/1.txt:1–9`.

**Prevents:** giving co-dispatched workers a complete view of current peers. **User symptom:** both expected prompts say nothing else is in flight despite the scenario dispatching two milestones. **INFERRED:** shared-file and merge coordination then depends on later discovery by the coding sessions.

### 25. A successful resume does not end the retry cycle of an API wait

**Category:** error handling and recovery. **What:** an API wait clears on a later session-written consumed ending or dispatch, not on productive progress after a delivered resume. When the next interval becomes due, wait_retry_run can stop/resume the still-working session again.

**Evidence:** `lib/derive.sh:305–339`; `lib/waits.sh:83–103`; `lib/stops.sh:458–485`; `tests/scenarios/wait-clears-on-resume/home/log.jsonl:1–6`.

**Prevents:** recognizing recovery before the full close-out arrives. **User symptom (INFERRED):** work lasting beyond retryMinutes after the error clears can be interrupted repeatedly, while the model hold remains. **Observed helper check:** after a delivered resume with no subsequent session-written ending, derive_waits still returned the rate-limit wait with `due:true`.

### 26. A consumed ending can disable crash detection for the rest of an attempt

**Category:** error handling and recovery. **What:** crash_check excludes a session with any ending on disk, and separately any consumed event for the attempt, even when a later resume restarted work. A previously acted-on no-handover rung then has nothing new to act on.

**Evidence:** `lib/rows.sh:37–48,176–194`; `lib/stops.sh:307–328,368–388`; `lib/status.sh:186–189`.

**Prevents:** normal crash recovery after an earlier recoverable ending in the same attempt. **User symptom (INFERRED):** the resumed worker disappears and the lane can remain without a live row, new crash event or actionable park. **Observed helper check:** dispatch → no-handover consume → delivered resume → absent row yielded no_row_count 1, ladder acted true, and no crash sighting.

### 27. The generic failure ladder can repeat across attempts without reaching its final rung

**Category:** error handling and recovery. **What:** the ladder counts failures per attempt and resets at dispatch. At two failures it redispatches, creating a new attempt whose count restarts. Cross-attempt bounds exist for unfinished and invalid_request, but not for repeated generic no-handover/crash cycles.

**Evidence:** `lib/stops.sh:307–328,338–357,368–418`; `lib/derive.sh:385–404`; `lib/declared.sh:27–55`.

**Prevents:** a bounded end to a milestone that repeatedly fails in the same generic way across fresh sessions. **User symptom (INFERRED):** resume/redispatch cycles continue without a ladder-end park. **Observed helper check:** three successive attempts with two no-handover endings each all returned `next:"redispatch"`, not escalation.

### 28. Repairing a dispatch failure's actual cause need not release its park

**Category:** error handling and recovery. **What:** two dispatch failures park the lane. Its automated release compares selected plan rows and the committed prompt, not permissions, the executable, the worktree or the service. Only hash fields present when parked are compared: a missing prompt has no prior prompt hash.

**Evidence:** `lib/tick.sh:181–203`; `lib/escalate.sh:32–36,78–97,433–464`; `lib/candidates.sh:269–275`; `lib/escalate.sh:303–305`.

**Prevents:** recovery merely by fixing a missing permission file, service, workspace or previously missing brief. **User symptom (INFERRED):** the notification says the next tick dispatches after the cause is fixed, but the lane stays parked with no session for a ruling. Re-read resolution is narrower than that message.

### 29. A first-request failure may have no actionable ending

**Category:** error handling and recovery. **What:** the repository's live proof records a refused model creating a session with a live pid, failed state and no StopFailure artifact. Current crash logic requires no pid; model_not_found routing requires an API-error consume; the remaining detector is transcript-age stall.

**Evidence:** `docs/milestones/M04.md:258–267,371–377`; `docs/DECISIONS.md:68–68,80–80`; `lib/rows.sh:170–194,259–303`; `lib/stops.sh:458–528`.

**Prevents:** prompt recovery from that recorded startup failure. **User symptom:** the historical result was a failed idle session; **INFERRED from unchanged paths:** notice waits for stallMinutes rather than immediately identifying the model error, and automatic model-edit recovery has no API artifact to route.

### 30. Waiting-state coverage is narrower than the runtime states Baton reads

**Category:** observability. **What:** live question detection matches only waitingFor equal to “input needed.” A non-remote row whose status is waiting is excluded from stall detection. Remote-marked lanes bypass question detection entirely and rely on stalls, regardless of the global Remote Control setting.

**Evidence:** `lib/rows.sh:269–278,345–391`; recorded other waiting values at `.scratch/baton/research/background-sessions.md:131–184`; `tests/scenarios/remote-row-not-a-park/expected/out/1.stdout:1–1`.

**Prevents:** equivalent attention handling for sandbox, worker, permission or local-dialog waits and remote question variants. **User symptom (INFERRED):** some waits have no immediate park; others surface only as a generic stall or long-running notice. The exact waiting states a new target will encounter are external runtime facts.

### 31. Takeover protection depends on a readable transcript and a live row

**Category:** session lifecycle. **What:** takeover derivation scans only in-flight lanes. A missing transcript without an orphaned sibling is silently skipped. Ownership is inferred from newest-message hash membership, not an explicit actor identity; hashes from refused resume events are included.

**Evidence:** `lib/derive.sh:199–247`; `lib/rows.sh:93–152,176–184`.

**Prevents:** a durable, comprehensive stand-off whenever a person takes over. **User symptom (INFERRED):** after a taken-over session loses its row, that protection is absent from crash reconciliation; a missing transcript gives no stand-off; identical text to an earlier Baton prompt can be misclassified.

### 32. A manual done transition can clear a park without closing the logged lane

**Category:** session lifecycle. **What:** the merge-failed/main-broken edit route resolves a park on a new done cell, but lanes_open closes a dispatch only with a later complete consume or replacement dispatch. The edit route merely prints an idle session's job; it does not close its lane.

**Evidence:** `lib/escalate.sh:433–473`; `lib/derive.sh:121–145`; `tests/scenarios/main-broken-done-edit/expected/out/1.stdout:1–6`; `docs/milestones/M06.md:235–237`.

**Prevents:** the documented manual close-out fallback from producing the same lifecycle state as a normal complete handover. **User symptom:** the fixture explicitly reports the session still counting against the cap. **INFERRED:** if it later disappears without a complete artifact, the historical consumed ending also excludes it from normal crash detection.

### 33. Some parks have no usable operator resolution

**Category:** error handling and recovery. **What:** answer refuses multiple parks even for one project-qualified milestone; no park identifier is accepted. A rejection with no recoverable project can create a park without a ruling target or re-read hashes, while edit checks run only for registered projects.

**Evidence:** `lib/answer.sh:173–188`; `lib/inbox.sh:248–267`; `lib/escalate.sh:160–180,214–217`; `lib/tick.sh:306–315,350–364`; `tests/scenarios/answer-two-matches/expected/out/1.stderr:5–7`; `tests/scenarios/reject-unparseable/expected/home/log.jsonl:1–2`.

**Prevents:** resolving every recorded escalation through the public controls. **User symptom:** the qualified answer can reproduce the same ambiguity refusal. **INFERRED:** an unassigned park can remain visible indefinitely even after the file/project problem is corrected.

### 34. A slow or hung external command can hold every operational verb

**Category:** error handling and recovery. **What:** all verbs—including status and plan—share the lock. Claude commands and Git operations have no Baton-enforced execution deadline. The “thirty seconds” polling bounds count sleeps/listings, not wall time including each listing's duration.

**Evidence:** `bin/baton:58–112`; `lib/lock.sh:6–17`; `lib/dispatch.sh:13–29,188–198`; `lib/stops.sh:141–172,235–250`.

**Prevents:** independent diagnosis or control while an external operation stalls. **User symptom (INFERRED):** ticks, status, answer and wake refuse with exit 75 while the holder remains alive; one target's slow call delays all projects. The repository itself notes that stop settling can exceed thirty seconds (`lib/stops.sh:157–161`).

### 35. Stale-lock recovery assumes complete metadata and a meaningful pid

**Category:** state and persistence. **What:** lock creation and writing pid/at are separate. Stale breaking returns without action when at is absent/unparseable; a live reused pid prevents breaking an abandoned lock. The lock writer verifies only directory existence before log append, not that the caller owns it.

**Evidence:** `lib/lock.sh:6–21`; `lib/tick.sh:41–58`; `lib/log.sh:16–21`; `docs/milestones/M03.md:487–495`.

**Prevents:** automatic recovery from every interrupted lock acquisition or stale-owner condition. **User symptom (INFERRED):** the relay can repeatedly refuse work until someone intervenes. Timestamp-only comparison during a stale rename also does not establish unique ownership; concurrent replacement behavior was not exercised in this audit.

### 36. A completed-tick marker can conceal partial failure

**Category:** error handling and recovery. **What:** several failed passes print diagnostics and continue; a failed project's reconciliation is skipped, and holds/reserve failures can leave dispatch proceeding. If the final return is zero, verb_tick still writes last-tick. The marker is written after releasing the lock.

**Evidence:** `lib/tick.sh:333–342,350–378,389–396`; `lib/tick.sh:61–67`.

**Prevents:** using last-tick as proof that all eligible projects and safety checks completed successfully. **User symptom (INFERRED):** status shows a fresh tick despite a skipped project or failed hold pass; the distinguishing detail may exist only in the scheduler streams. Separate post-lock marker writers can contend for the same temporary pathname.

### 37. Plan parsing does not establish a valid dependency graph

**Category:** configuration. **What:** the parser validates cell tokens and duplicate milestone IDs, but not dependency existence, cycles, self-dependencies, gate-name uniqueness or references to nonexistent held milestones. Table extraction also assumes the line after a header is a separator and does not track Markdown code fences.

**Evidence:** `lib/plan.sh:26–69,72–105,144–182,190–216`.

**Prevents:** distinguishing an unsatisfiable/misread plan from ordinary work waiting on dependencies. **User symptom (INFERRED):** a plan can parse yet never progress, or a quoted example can be treated as the plan. **Observed helper check:** an M01↔M02 cycle, M03 depending on missing M999, duplicate gate names and a hold on missing M888 all parsed, with no eligible milestone.

### 38. Artifact validation is materially weaker than the documented shape

**Category:** state and persistence. **What:** several required fields are checked only for nonempty values. Milestones need not be IDs or plan members; written_at need not be a timestamp; stopped detail is not required; context containment is not checked. Eligible dispositions/wait/gate shapes are not comprehensively validated at acceptance.

**Evidence:** `lib/inbox.sh:103–195`; `lib/candidates.sh:63–70`; compare `CONTRACT.md:42–57,92–94`.

**Prevents:** treating successful validation as evidence that downstream rules have meaningful typed inputs. **User symptom (INFERRED):** malformed values become omissions, incorrect waits, generic parks or later jq/shell failures. **Observed helper check:** stopped/other with milestone M999, written_at 42 and no detail was accepted using the existing fixture transcript and registration.

### 39. Configuration values are read without a validated configuration boundary

**Category:** configuration. **What:** config_num stringifies whatever a key contains; missing/unreadable files fall back to defaults. Numeric consumers use shell arithmetic, numeric test operators or argjson. Model aliases accept any nonempty mapped value, while timing and resource settings have no type/range validation.

**Evidence:** `lib/derive.sh:15–18,327–337`; `lib/plan.sh:109–118,145–146`; `lib/tick.sh:246–260`; `lib/lifecycle.sh:62–64,239–242`; `lib/waits.sh:233–238`.

**Prevents:** predictable configuration changes across unfamiliar workloads or environments. **User symptom (INFERRED):** a malformed value fails inside a later rule; invalid/missing config can instead reinstate defaults without a dedicated diagnosis. The fixed 60-second interval is duplicated in code and plist, independently of config.

### 40. Quota policy assumes one account and uses coarse model identity

**Category:** configuration. **What:** rate/billing holds span projects, two distinct model strings trigger an all-model hold, and non-Fable holds compare literal model names. Reserve selection takes the newest usable seven-day status reading from any session; no reading lifts the reserve, and there is no age bound apart from a numeric reset timestamp.

**Evidence:** `lib/waits.sh:117–179,182–266`; `lib/derive.sh:440–451`; `tests/scenarios/fable-reserve-no-reading/expected/out/1.stdout:1–2`.

**Prevents:** interpreting those controls as precise per-project, per-account or per-model-family budgets. **User symptom (INFERRED):** one project's limit can hold unrelated work; aliases/full IDs can evade a literal hold; stale telemetry can hold or release Fable incorrectly. These are heuristic quota controls, not measured remaining-capacity admission.

### 41. Recovery cost and retained state grow with the entire history

**Category:** state and persistence. **What:** log_json slurps the whole log repeatedly; several derivations scan the event list inside another event loop. Typed-message hashing reads complete transcripts and launches tools per message. Sidecars, archives, telemetry files and milestone worktrees are retained without a size bound or cleanup path in the relay.

**Evidence:** `lib/log.sh:42–69,99–107`; `lib/derive.sh:101–145,185–196,205–245`; `lib/candidates.sh:50–75`; `CONTRACT.md:33–37`; `docs/SPEC.md:190–196,358–363`.

**Prevents:** assuming stable resource use over arbitrarily long histories or large projects. **User symptom (INFERRED):** slower ticks/status, expanding disk use, and eventually oversized JSON passed in command arguments. No runtime scale benchmark was performed; this finding is about the read/write structure and absence of bounds, not a measured present slowdown.

### 42. Installation does not activate one consistent version of code and state

**Category:** state and persistence. **What:** executable scripts/libraries are overwritten sequentially, outside the verb lock. Existing registrations and permissions are kept as-is; existing per-lane settings are not migrated. The applet has a staging recipe, but the relay scripts have no equivalent version switch or state-schema compatibility check.

**Evidence:** `install.sh:11–17,36–77,79–99,118–147,150–167`; `lib/dispatch.sh:74–94`; `docs/milestones/M07-c.md:279–283`.

**Prevents:** establishing that an upgrade/rollback gives every reader, hook and resumed session a matching set of code, policy and state. **User symptom (INFERRED):** concurrent reads may meet a partial script update, and old permissions/settings survive newer code. The repository explicitly records that the added notify deny rules do not reach an existing permissions file automatically.

### 43. Rejected-file paths do not preserve immutable evidence

**Category:** observability. **What:** reject_move moves to rejected under the original basename without refusing an existing destination. Earlier rejected events keep pointing to that same path. The detailed rejection explanation is printed, while the event stores the rule and path.

**Evidence:** `lib/inbox.sh:233–239,264–268`; `docs/milestones/M02.md:348–350`; contrary later description at `docs/DECISIONS.md:109–109`.

**Prevents:** reliably recovering the exact rejected artifact and diagnosis from an older event. **User symptom (INFERRED):** a repeated bad filename replaces prior rejected content; following the older event shows newer bytes, and the detailed reason may require launchd.out. The “existing destination refused” statement is true of archive_move, not reject_move.

### 44. Second-resolution timestamps are also used as park identities

**Category:** state and persistence. **What:** a resolution identifies a park by its at plus project/milestone, without a unique event ID, class or session in the resolution join. The gap derivation also compares local-offset ISO strings lexically for some historical ordering.

**Evidence:** `lib/log.sh:6–9`; `lib/derive.sh:185–196,498–501`; `lib/escalate.sh:189–202`.

**Prevents:** unambiguous park resolution and correct chronological ordering in every clock/offset case. **User symptom (INFERRED):** distinct parks raised in one second can close together; a daylight-saving offset change can misclassify events relative to the marker. **Observed helper check:** two same-project/milestone parks with identical at and one resolution yielded an empty parked list.

### 45. The status view omits states needed to explain some stalled work

**Category:** observability. **What:** status uses rows_json, which turns listing failure into an empty fleet. It prints live lanes but not the unclassified no-row half, and obtains unrecorded archives without rendering them. It shows no candidate queue or comprehensive admission verdict; the plan view's eligible state is only graph eligibility.

**Evidence:** `lib/log.sh:72–76`; `lib/status.sh:164–219,222–225`; `lib/derive.sh:260–298`; `lib/plan.sh:200–216`.

**Prevents:** a complete answer to why a milestone has not started or resumed. **User symptom (INFERRED):** fleet failure can look like no live work, orphaned consumption is not displayed, and plan can say eligible for a milestone the automatic dispatcher cannot select. Refused-resume detail is also outside the resume event (`lib/stops.sh:256–269`).

### 46. A notification event records intent, not successful delivery

**Category:** observability. **What:** notification/escalation events are logged before transport. The fallback suppresses osascript failure; applet launch success is not proof that a banner appeared. Once-only rules consult the event rather than a delivery receipt.

**Evidence:** `lib/notify.sh:70–110,156–165`; `lib/escalate.sh:182–186`; `lib/derive.sh:426–437`; `notify/Baton.applescript:42–67`.

**Prevents:** guaranteeing that a person actually receives the event that stops a lane. **User symptom (INFERRED):** a notification permission, application or transport failure can leave a parked lane without a seen message, while its once-only key is already spent. Spool flushing covers stranded files, not every failure between intent and visible delivery.

### 47. Notification clicks cannot address the notification clicked

**Category:** developer experience. **What:** the applet keeps one global newest target. An empty-spool launch opens that target and removes every delivered Baton notification, regardless of which message the person clicked.

**Evidence:** `notify/Baton.applescript:5–10,55–60,70–85`; `docs/milestones/M07-c.md:155–162,270–278`.

**Prevents:** reliable per-project/per-lane navigation from several simultaneous messages. **User symptom:** the recorded behavior is opening the newest session and clearing older messages too; a newer session-less gap notice redirects to needs-input. Older parks remain in status, but the clicked message does not select its own lane.

### 48. Wake message delivery depends on model-generated shell syntax

**Category:** security and secrets. **What:** the wake model is told to paste user text verbatim into a heredoc with the fixed delimiter MESSAGE and to interpolate a milestone into a command. Its extra deny rules match command text. The verb's stdin handling is safe for the tested apostrophe/dollar/backtick case; generating the surrounding shell remains a separate model step.

**Evidence:** `lib/lifecycle.sh:137–155,325–335`; `install.sh:79–93`; `tests/scenarios/wake-verb-stdin/cmd:1–6`; `docs/milestones/M07-b.md:402–423`.

**Prevents:** arbitrary message text being an entirely data-only, deterministic transport. **User symptom (INFERRED):** a literal delimiter line ends the prescribed heredoc early; a model's formatting mistake changes the command. The recorded deny-text limitation also rejects messages mentioning protected verbs/paths. The final standing prompt itself was not exercised by Haiku in the recorded proof.

### 49. A finished session's fork loses the hooks' closed-lane exemption

**Category:** session lifecycle. **What:** wake follows a fork through a wake.copy field, but Stop/StopFailure exemption requires an archived complete artifact carrying the new session ID. The old completion artifact names the original. The hooks do not consult the wake-copy relationship.

**Evidence:** `lib/lifecycle.sh:24–38,337–353`; `hooks/stop-gate:16–35`; `hooks/stop-failure:15–25`; `docs/ARCHITECTURE.md:402–411`.

**Prevents:** a forked continuation of a finished conversation behaving exactly like the completed original. **User symptom (INFERRED):** a wake copy can demand a handover again or write spurious stopped artifacts during a follow-up conversation. The existing wake-fork fixture verifies routing to the copy, not execution of its hooks.

### 50. Persisted prompts and artifacts have no content-secrecy boundary

**Category:** security and secrets. **What:** prompt sidecars retain exact kickoff/ruling/wake text; archives retain session-authored details and context; statusline stores its payload whole. Those writers do not redact sensitive content or set restrictive directory/file modes independently of the inherited umask.

**Evidence:** `lib/log.sh:97–107`; `lib/inbox.sh:225–239,394–439`; `hooks/statusline:7–12`; `lib/stops.sh:263–269`; `lib/lifecycle.sh:328–347`; `install.sh:11–17`.

**Prevents:** assuming that confidential material in an arbitrary project's prompts or results stays within that project's existing storage policy. **User symptom (INFERRED):** additional readable copies persist outside the checkout and prompt text is passed as process arguments. Actual permissions, secret presence and host access were not inspected; no leaked credential is asserted.

### 51. Workflow extension requires changing several fixed tables and readers

**Category:** extensibility. **What:** outcomes, stopped reasons, escalation/notification classes, edit-resolution classes, template kinds and model/effort syntax are fixed in shell/jq logic. There is no configured extension point connecting new lifecycle semantics to validation, routing, rendering and recovery.

**Evidence:** `lib/inbox.sh:107–119,170–189`; `lib/stops.sh:33–83`; `lib/notify.sh:141–153`; `lib/escalate.sh:32–55,257–313`; `lib/plan.sh:107–134`.

**Prevents:** representing project-specific ending types or policies solely in the registration/plan. **User symptom (INFERRED):** new reason strings are rejected or collapse to other, and a new class must agree across several code paths. Existing environment seams substitute dependencies for tests; they do not expose a general workflow extension mechanism.

### 52. The standing check is not portable with the repository

**Category:** developer experience. **What:** installation expectations hardcode the canonical checkout and project basename; commands explicitly address projects/Baton. The runner uses BSD sed/date forms and installation cases require Apple's compilation/signing utilities.

**Evidence:** `tests/scenarios/install/cmd:4–14`; `tests/scenarios/install/expected/out/1.stdout:1–5,38–43`; `tests/run.sh:84–121`; `docs/milestones/M02.md:266–270,359–362`.

**Prevents:** treating a fresh clone elsewhere as an equivalent validation environment. **User symptom:** M02 recorded 81/82 passing in a pristine clone because install expected the original path. **INFERRED from current expectations:** relocation still changes those assertions, and a non-macOS runner cannot execute the same standing check unchanged.

### 53. Repository instructions do not describe one consistently authoritative protocol

**Category:** developer experience. **What:** CLAUDE.md retains a notice saying contract-2 supersedes conflicting contract-1 close-out instructions. The foundation handoff names immutable messages, committed-graph authority and kernel locking, whereas the current implementation uses baton:1, historical dispositions and a mkdir lock. The referenced foundation commit is not an ancestor of HEAD. Old copy-ready prompts also retain superseded close-outs.

**Evidence:** `CLAUDE.md:3–7`; `docs/M03-FOUNDATION-HANDOFF.md:11–17,25–44`; `lib/inbox.sh:107–119`; `lib/candidates.sh:50–75`; `lib/lock.sh:6–21`; `docs/milestones/M07.md:391–405`; compare `CONTRACT.md:33–37`.

**Prevents:** a fresh reader identifying one protocol and recovery instruction set from the repository alone. **User symptom (INFERRED):** a session can follow a superseding notice whose mechanisms are absent, or an old prompt that removes a workspace the current contract requires keeping. M03's evidence records the earlier integration dispute; it is not evidence that the foundation was subsequently implemented.

### 54. Fixture success does not establish the full unattended, unfamiliar-project workflow

**Category:** developer experience. **What:** the runner compares state after two scenario commands with stored expected output; it does not independently assert every intermediate invariant. The CLI shim does not run a coding session or normally append its transcript/produce its handover. Live acceptance for a usage-limit night and a fresh Mac was explicitly unheld; M08 has no completion evidence.

**Evidence:** `tests/run.sh:126–189`; `tests/shim/claude:48–125`; `tests/scenarios/takeover-handback/cmd:5–6`; `docs/milestones/M07.md:295–324`; `docs/milestones/M07-d.md:165–169,197–205`; `docs/milestones/M08.md:74–80,105–107`.

**Prevents:** concluding from “243 scenarios, 0 failed” that deployment, real quota recovery, arbitrary target settings and cross-project kickoff have been proved. **User symptom (INFERRED):** a scenario can pass its recorded expectations while a real session exposes a prerequisite or transition the shim does not execute. This audit did not rerun the suite or claim those live checks passed.

### Category coverage

Every requested category was examined and populated; none is marked clean.

| Category | Limitation ranks |
|---|---|
| cross-project portability | 1, 2, 9, 21 |
| environment and setup coupling | 4, 6, 7, 8 |
| state and persistence | 14, 17, 18, 19, 20, 35, 38, 41, 42, 44 |
| session lifecycle | 13, 22, 23, 24, 31, 32, 49 |
| error handling and recovery | 16, 25, 26, 27, 28, 29, 33, 34, 36 |
| observability | 30, 43, 45, 46 |
| configuration | 3, 37, 39, 40 |
| security and secrets | 10, 11, 12, 15, 48, 50 |
| extensibility | 5, 51 |
| developer experience | 47, 52, 53, 54 |

## GAPS — ABSENT CAPABILITIES

These are absences, rather than defective behavior of an existing feature. **INFERRED** applies to why each capability could matter to a universal tool; the absence is based on the full source inventory and the boundaries cited below. This is not a requested feature set or an implementation prescription.

1. **Adoption of an already-running or previously hand-started coding session as a managed lane.** There is no adoption/import command that creates the run relationship and installs the required controls. A hand-started handover can be consumed, but it does not acquire a dispatched attempt or a ruling target. Evidence boundary: `bin/baton:43–122`; `lib/inbox.sh:206–214`; `lib/escalate.sh:205–217`. **INFERRED relevance:** users often begin work before choosing a handoff tool.

2. **Intake of work that is not already a Baton milestone.** No command takes a plain task, issue, ticket or existing arbitrary planning document and turns it into a managed unit. There is no issue-tracker intake or discovery of work sources. Evidence boundary: `bin/baton:43–122`; `lib/plan.sh:26–182,226–237`; `lib/dispatch.sh:235–264`. **INFERRED relevance:** an unseen project's source of work may not be a pre-authored milestone table.

3. **Target onboarding and workspace provisioning.** No code discovers a target's required tools, performs contract migration, establishes target-specific readiness, or provisions a new workspace's dependencies/local inputs. The existing installer installs Baton and registers itself; M08 introduces no onboarding code. Evidence boundary: `install.sh:8–99`; `lib/dispatch.sh:35–59,235–266`; `docs/milestones/M08.md:31–57`. **INFERRED relevance:** first use cannot depend on a previous hand-prepared workspace.

4. **Dependencies between projects.** Plan dependency and wait/blocker resolution operate on IDs within one project's plan; there is no cross-project dependency model or completion barrier. M08's ordering relative to the first Reclaim dispatch lives in prose and artifact placement. Evidence boundary: `lib/plan.sh:72–105,190–197`; `lib/declared.sh:73–81`; `lib/candidates.sh:94–163`; `docs/milestones/M08.md:59–80,95–98`. **INFERRED relevance:** a project may depend on a library or setup step managed in another checkout.

5. **Transfer of a run/conversation to another host or runtime.** There is no portable handoff bundle, export/import operation, or translation between coding-runtime conversation formats. Current resume addresses a local Claude session ID and saved settings/workspace state. Evidence boundary: `bin/baton:43–122`; `lib/stops.sh:188–298`; `lib/lifecycle.sh:123–155,272–361`. **INFERRED relevance:** continuity may need to outlive the original machine, checkout or coding client.

6. **Explicit cancellation, pause/drain and project deregistration.** These are absent from the command surface. Plan holds govern ordinary admission; stopping a Claude process is not represented as an operator cancellation state. Evidence boundary: `bin/baton:43–122`; `lib/derive.sh:121–145`; `lib/stops.sh:33–71`. **INFERRED relevance:** people need to distinguish intentional suspension/abandonment from a failure the tool may recover.

7. **A context checkpoint before an impending session boundary.** Baton has no producer of a checkpoint based on context remaining, no pre-compaction handoff, and no serialized inventory of unfinished tool actions. The status payload is retained; recovery consumes brief evidence after an ending and gives fixed continuation instructions. Evidence boundary: `hooks/statusline:7–12`; `lib/templates.sh:37–57`; `lib/stops.sh:33–71`. **INFERRED relevance:** session continuity may need to preserve partial work before a failure or context reset.

8. **Enforced cost, token, turn, elapsed-work or target-resource budgets.** There is a concurrency cap, quota hold/reserve, sleep assertion bound and long-running notice. There is no budget that terminates or defers work based on accumulated cost/turns, and no claims for ports, databases, devices or other target resources. Evidence boundary: `lib/dispatch.sh:188–198`; `lib/rows.sh:307–335`; `lib/tick.sh:245–277`; `lib/waits.sh:117–266`. **INFERRED relevance:** arbitrary projects can have constraints unrelated to the number of parent coding sessions.

9. **Independent verification of a handoff's acceptance results and merge coordination.** No Baton component runs a target's acceptance checks, adjudicates the finished code, claims shared files or serializes the sessions' merge transactions. The contract delegates those acts to the coding session. Evidence boundary: `CONTRACT.md:28–40`; `lib/inbox.sh:33–48,139–168`; `lib/templates.sh:22–34`; `docs/SPEC.md:173–174`. **INFERRED relevance:** an arbitrary project may require evidence stronger than session-authored completion and nonoverlapping worktrees.

10. **Supported state backup/restore and schema migration.** There is no backup, restore, relocation or state-migration command; the rollback described in the repository changes installed code while retaining state. Evidence boundary: `bin/baton:43–122`; `install.sh:36–99`; `docs/SPEC.md:358–363`. **INFERRED relevance:** long-lived runs and project moves need continuity beyond the original directory layout and code version.

11. **A public machine-readable control/inspection interface and dispatch preview.** There is no JSON status mode, inspect/dry-run verb, API server or event subscription. Internal derivations return JSON, but the public views format prose and the dispatch verb acts. Evidence boundary: `bin/baton:43–122`; `lib/status.sh:93–225`; `lib/plan.sh:242–256`. **INFERRED relevance:** editors or other local tools cannot use a documented structured interface to inspect and initiate handoffs.

12. **An out-of-process monitor of Baton itself.** The gap report runs inside the next tick and status; no independent component reports a permanently unloaded, hung or non-starting relay. Evidence boundary: `lib/rows.sh:396–416`; `lib/tick.sh:377–396`; `lib/status.sh:197–202`; `docs/SPEC.md:145–145`. **INFERRED relevance:** autonomous work can stop before the component responsible for reporting its absence runs again.

## MILESTONE FORMAT

This section reconstructs the convention present in the files. It does not define a new milestone or change Baton's contract.

### Naming, numbering and headings

The current files are `docs/milestones/M01.md` through `M08.md`, plus `M07-b.md`, `M07-c.md` and `M07-d.md`. Each starts with an H1 of the form `# M<nn> — <title>`. Top-level brief sections use numbered H2 headings, 1 through 11, followed by three unnumbered H2 headings. The suffix does not create nested files: a split/addition is a peer brief and a peer row in the plan. Dependencies determine execution order; filename sorting does not. Evidence: all 11 brief heading sequences; `docs/MILESTONES.md:28–46,83–90`.

The split rule describes a remainder as `Mxx-b`, with its own brief and a plan row depending on the milestone it came from. M07-c and M07-d were later additions placed in the dependency chain, not a general numbering algorithm implemented by Baton. The parser accepts an M followed by digits and one optional lowercase/alphanumeric suffix, broader than the two-digit examples. Evidence: `docs/MILESTONES.md:3–14,83–90`; `lib/plan.sh:72–75`.

### Reusable skeleton, preserving the observed section order

````markdown
# M<nn> — <title>

## 1. Identity

- **ID:** M<nn>. **Objective:** <bounded objective and purpose>.
- **User-visible result:** <observable resulting behavior>.

## 2. Dependencies and entry conditions

<Predecessor milestone(s), installed state, gates, and externally observable
preconditions; identify whose act or evidence each precondition requires.>

## 3. Required reading

<Repository instructions, glossary, contract, exact SPEC/ARCHITECTURE sections,
decision IDs, predecessor completion evidence, and any evidence files.>

## 4. Requirements, scope, non-goals

- **Covers:** <requirement IDs and named proof items>.
- **Scope:** <the work this milestone contains>.
- **Non-goals:** <work outside this milestone and its owner, if known>.

## 5. Expected files (proposed)

<Paths expected to be added/modified; distinguish paths outside the repository.>

## 6. Interfaces

- **Introduces:** <functions, commands, data/event shapes, or no code>.
- **Consumes:** <existing interfaces or prerequisite milestones>.

## 7. Implementation checklist (ordered)

1. <First concrete act>.
2. <Next concrete act>.
<N>. <Verification, review, completion evidence, handover as applicable>.

<Natural split point and the bounded remainder, when present.>

## 8. Fixtures, verification, acceptance

- **No-build:** <applicable inspection checks, when present>.
- **Fixture-run:** <named scenarios and repeat requirement>.
- **Manual, live:** <permitted proof and observation, when applicable>.
- **Acceptance:** <observable conditions or named acceptance columns that hold>.

## 9. Definition of done and evidence

<Handoff-template reference and the exact output/captures required as evidence.>

## 10. Risks and decisions this milestone settles

- **<Risk or open decision>.** <Its evidence and ownership>.

## 11. Handoff and next milestone

<Next eligible milestone(s), dispositions, gates and who initiates the next act;
or explicitly none.>

## Recovery procedure

<What to inspect; resume the first unfinished checklist item;
no completion claim without all acceptance criteria.>

## Completion evidence

<Initially empty. The completing session appends the evidence structure below.>

## Copy-ready session prompt

```
<Identity and scope in second-person imperative form>

WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.

STARTUP ORDER. <Reading order, inspection and recovery clause.>

WHAT TO SETTLE RATHER THAN INHERIT. <Decisions with evidence; established facts.>

CONSTRAINTS. <Project rules, permitted operations and boundaries.>

VERIFICATION. <Pointer to section 8 and reporting requirement.>

CLOSE-OUT, in this order, once the <ID> checklist is finished.
1. <Ordered close-out acts as that project's contract requires>.
<Last item writes and prints the handover artifact>.
```
````

The labeled verification bullets vary: M07 has fixture/manual/acceptance; M07-d has fixture/acceptance; earlier briefs include No-build. “Natural split point” appears where applicable, not in every brief. Evidence: `docs/milestones/M01.md:161–177`; `docs/milestones/M07.md:70–75`; `docs/milestones/M07-d.md:59–67`.

### Acceptance language

The convention describes facts that must **hold**, not percentages of progress. Typical phrases name the command, state, or observation: M07-d says a repeated handover changes no disposition and dispatches nothing; M08 names the graph output and observed dispatch of the starting milestone. Acceptance can refer back to named REQ acceptance columns. Verification is partitioned into fixtures, inspection and live/manual proof, with pass/fail/unrun reported explicitly. Definition of done then names the evidence package. Evidence: `docs/milestones/M01.md:165–182`; `docs/milestones/M07-d.md:59–67`; `docs/milestones/M08.md:74–85`; `docs/MILESTONES.md:16–23,92–105`.

The files distinguish a criterion's statement from later evidence about it. For example, M07 explicitly records two product success criteria as not held despite marking its own milestone complete. A reusable reading of the convention therefore cannot treat a filled Completion evidence section as proof that every earlier statement is satisfied. Evidence: `docs/milestones/M07.md:100–106,295–318`.

### Dependencies and preconditions

Two representations coexist:

- The **plan table** carries machine-readable Depends on IDs/ranges and Status, plus a separate Gate/Holds/Cleared table. It does not contain all operational preconditions. Evidence: `docs/MILESTONES.md:26–49`.
- Brief **section 2** states operational entry conditions in prose: predecessor complete **and installed**, service/setup state, a gate's decision entry, a migration commit, or absence of another active session. Section 7 can require observing these before proceeding; the prompt restates them. Evidence: `docs/milestones/M03.md:13–17,80–86`; `docs/milestones/M07-c.md:12–15`; `docs/milestones/M08.md:15–21,61–69,114–114`.

Dependencies are also described as interface consumption in section 6 and handed forward in section 11. The code parses only the plan tables; prose preconditions remain instructions to the coding session. Evidence: `lib/plan.sh:26–69,141–182`; `docs/milestones/M08.md:54–57,95–103`.

### Completion-evidence appendix and kickoff anatomy

`docs/MILESTONES.md:92–105` requires ten evidence topics, in order: what changed; files added/modified/deleted; interfaces; checks run with output; checks not run and why; known limitations; deviations and decisions; commits/merge commit; observed working-tree state; exact next step/eligible milestone. Completed briefs generally express these as numbered H3 headings.

There are real deviations from that order: M03 appends 4b/5b/6b after earlier sections; M07-b and M07-c lead with measurements and rulings before the ten-topic handoff; M07-d leads with settlements. Those are observed extensions, not additional mandatory template sections. Evidence: `docs/milestones/M03.md:379–505`; `docs/milestones/M07-b.md:145–241`; `docs/milestones/M07-c.md:102–164`; `docs/milestones/M07-d.md:91–117`.

The kickoff remains one fenced block under the exact H2, with seven parts: identity/scope; slot paragraph; startup/recovery; decisions to settle with evidence; constraints; verification; ordered close-out. Parts are mostly uppercase prose labels rather than Markdown headings inside the block. The fixed slot is intended to be replaced whole by Baton. Evidence: `CLAUDE.md:69–97`; `CONTRACT.md:9–16`; `lib/dispatch.sh:96–123`.

### Verbatim reference: docs/milestones/M08.md

The entire audited M08 file follows verbatim. Its instructions and historical design choices are quoted source material, not recommendations made by this audit. Its empty Completion evidence section is preserved.

````markdown
# M08 — Reclaim onboarding

## 1. Identity

- **ID:** M08. **Objective:** Reclaim becomes the second registered project. Baton's side of the
  handover-method change: register Reclaim, confirm its migrated plan parses, prove item 38
  against its path, and place the hand-written starting artifact in the inbox so the next tick
  dispatches Reclaim's first Baton-driven milestone. The last Baton milestone; held by the gate
  `Reclaim migrated` until the person has made the migration commit in Reclaim (D-021).
- **User-visible result:** `baton plan Reclaim` prints Reclaim's graph with every built milestone
  `done` and the two gates; `baton status` lists Reclaim; a `complete` artifact for the last
  hand-run Reclaim milestone sits in the inbox listing the starting milestone with disposition
  `run`; the next tick dispatches `Baton · Reclaim · M<nn>`.

## 2. Dependencies and entry conditions

M07-d complete and installed; the gate `Reclaim migrated` cleared in `docs/MILESTONES.md` by the
D-number recording the migration commit; in Reclaim, that commit on `main`, M14 closed, and no
Reclaim session in flight (`claude agents --json` shows no row with `cwd` under
`/Users/danny/Documents/Apps/Reclaim`). The starting milestone is whichever the person's gate in
Reclaim's plan clears first — M19 is the recommendation (D-021); M15 stays behind "v0.1 ships".

## 3. Required reading

`CLAUDE.md`; `CONTEXT.md`; `CONTRACT.md`; `docs/SPEC.md` §2.1, §2.6 (REQ-PLAN-06), §2.8
(REQ-PERM-02), §7.1; `docs/ARCHITECTURE.md` §3; `docs/DECISIONS.md` D-021;
`/Users/danny/Documents/Apps/Reclaim/CLAUDE.md`, `docs/MILESTONES.md`, `docs/STATUS.md`,
`docs/DECISIONS.md` (the migration entry), and the brief of the starting milestone — all read
only; `.scratch/baton/issues/09-dispatching-more-than-one-at-once.md` §1 (the example table).

## 4. Requirements, scope, non-goals

- **Covers:** REQ-CONTRACT-01, 02 for Reclaim; REQ-PLAN-06 for Reclaim; REQ-PERM-02 for Reclaim;
  item 38 against Reclaim's path.
- **Scope:** `~/.baton/projects/Reclaim/project.json` and `permissions.json` (allow
  `Bash(xcodebuild:*)`, `Bash(swift:*)`, `Bash(swiftc:*)`, `Bash(xcrun:*)`; deny the two classes);
  `baton plan Reclaim` green; the conformance check of the starting brief (the two headings, the
  slot line); the hand-written artifact for the last hand-run Reclaim milestone, `session` set to
  that milestone's real session id (found in its completion evidence or by `--resume` picker),
  `merged_as` its merge commit, `eligible[]` from Reclaim's plan with the starting milestone `run`
  and every other eligible one `held` by its gate; a fixture scenario `reclaim-plan-parses` over a
  copy of the migrated table.
- **Non-goals:** any edit under `/Users/danny/Documents/Apps/Reclaim` — the migration is the
  person's commit and any correction it needs is reported, not made; dispatching a Reclaim
  milestone from this session — the tick does that after the close-out; anything about which
  Reclaim milestone runs, which is Reclaim's plan's and the person's.

## 5. Expected files (proposed)

`tests/scenarios/reclaim-plan-parses/`; `docs/ARCHITECTURE.md` §10 row M08; `docs/DECISIONS.md`;
this brief. Outside the repository: `~/.baton/projects/Reclaim/{project.json,permissions.json}`
and one artifact in `~/.baton/inbox/`.

## 6. Interfaces

- **Introduces:** nothing in code; Reclaim's registration.
- **Consumes:** M01–M07.

## 7. Implementation checklist (ordered)

1. Confirm the entry conditions; if any fails, write an `asking` artifact naming it and stop.
2. Write `project.json` and `permissions.json` for Reclaim.
3. `baton plan Reclaim`; every cell parses; every built milestone reads `done`; the gates table
   holds `v0.1 ships` and `D-026` (or whatever the migration named); any complaint is reported as
   a correction the person makes in Reclaim.
4. Check the starting brief conforms: `## Completion evidence` and `## Copy-ready session prompt`
   present, the slot line verbatim as part 2, the close-out in part 7 per `CONTRACT.md` clause 3.
5. Item 38 against Reclaim's path: with the service down, a tick-dispatched fixture session `cat`s
   a file under `/Users/danny/Documents/Apps/Reclaim` — read only — and reports it.
6. The hand-written artifact, `.tmp` then rename, into the inbox; `baton status` shows it
   un-consumed.
7. `sh tests/run.sh`, `/review-2`, `/address`, completion evidence, the handover.

## 8. Fixtures, verification, acceptance

- **Fixture-run:** `reclaim-plan-parses`, twice.
- **Manual:** items 3 to 6.
- **Acceptance:** `baton plan Reclaim` green; the artifact consumed by the next tick and the
  starting milestone dispatched under the name `Baton · Reclaim · M<nn>` — observed by the
  person, recorded here by hand afterwards.

## 9. Definition of done and evidence

Handoff per template with `baton plan Reclaim`'s output, the item-38 capture, the artifact's
text.

## 10. Risks and decisions this milestone settles

- **The artifact's `session` must have a transcript on disk** or consumption rejects it; find the
  real id of the last hand-run milestone's session and check the glob before writing.
- **Reclaim's `permissions.json` is Reclaim's allowlist**, from its D-030 (builds and tests
  authorised); widen only through `baton allow` afterwards.
- **Nothing here edits Reclaim.** A plan that does not parse is the person's to fix.

## 11. Handoff and next milestone

None in Baton: the plan is complete. The artifact lists nothing eligible, and the next thing the
tick dispatches is Reclaim's.

## Recovery procedure

Inspect `~/.baton/projects/Reclaim/` and the inbox; resume from the first unfinished checklist
item; no completion claim without every acceptance criterion.

## Completion evidence

## Copy-ready session prompt

```
You are implementing milestone M08 of Baton at /Users/danny/Documents/Apps/Baton. Baton is a relay: a personal tool for one person on one Mac, on Claude Code 2.1.270, that carries a build from one Claude Code session to the next — a launchd-run tick every sixty seconds that reads its inbox, its dispatch log, the target project's plan file and one git check, then dispatches, resumes, waits and escalates by fixed rules; it embeds no model call. M08 registers Reclaim as the second project, confirms its migrated plan parses, proves the granted shell against its path, and places the starting artifact so the next tick dispatches Reclaim's first Baton-driven milestone.

WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.

STARTUP ORDER. Read CLAUDE.md, then CONTEXT.md, then CONTRACT.md, then docs/milestones/M08.md in full, then the SPEC, ARCHITECTURE and DECISIONS sections listed in M08 §3, then docs/milestones/M07-d.md's completion evidence, then — read only — /Users/danny/Documents/Apps/Reclaim/CLAUDE.md, docs/MILESTONES.md, docs/STATUS.md, the migration entry in docs/DECISIONS.md and the starting milestone's brief. Then inspect the working tree before writing anything. Confirm M08's entry conditions: the gate cleared, the migration commit on Reclaim's main, M14 closed, no Reclaim session in flight; if any fails, ask the person with AskUserQuestion, naming the condition and what you observed, and wait for the answer in this session — M08 §7 item 1's asking artifact predates D-089, and an asking artifact would stop and archive this session. If M08 "Completion evidence" is non-empty or ~/.baton/projects/Reclaim exists, follow M08's Recovery procedure and resume only the unfinished portion.

WHAT TO SETTLE RATHER THAN INHERIT. (1) The starting milestone is whatever Reclaim's plan makes eligible and un-held after the migration — read it from the table, do not assume M19 — and every other eligible milestone is listed held by its gate. (2) The session id on the hand-written artifact must be the real id of the last hand-run Reclaim milestone's session, found in its completion evidence and confirmed by the transcript glob ~/.claude/projects/*/<id>.jsonl, because consumption rejects an artifact whose session has no transcript. (3) Reclaim's allowlist is drawn from its own D-030 — builds and tests are authorised — as Bash rules for xcodebuild, swift, swiftc and xcrun; anything else is widened later through baton allow. Facts you do not re-derive: the project key is the basename of the canonical checkout, so it is Reclaim; the plan file is the "Order and dependencies" table in Reclaim's docs/MILESTONES.md with the four columns the migration added and the gates table; item 38 — a session dispatched by a service the tick started can read ~/Documents — was proved on Baton's own path in M03, and its cold-start half passed on 2026-09-12, and is repeated here on Reclaim's because the grant is per executable and the proof is cheap. Every session Baton dispatches into Reclaim will be on Remote Control, listed in Claude.app and on the phone, because the settings file writes remoteControlAtStartup true (D-081); its worktree is kept after close-out, and the hooks stand down once its complete handover is archived (D-078). (4) How this session writes ~/.baton/projects/Reclaim/project.json and permissions.json, which M08 §4 and §7 item 2 expect: install.sh composes the deny list every dispatched session runs under, and it names projects among Baton's state paths in its Edit, Write and Bash rules (install.sh lines 63 and 68), so the editor and any shell command naming that path are refused here — the rail working, not a fault to route around; settle it with the person through AskUserQuestion (a person's write, or a way the brief does not yet name) and record the decision. Facts carried from M07-d (docs/milestones/M07-d.md completion evidence, D-095 to D-097): a file in the inbox holding the same JSON value — keys sorted, written_at included — as an archived copy of a consumed handover for the same milestone and session is a repeat: archived with a repeated event and one line, and acted on not at all; so the hand-written starting artifact, once consumed, can be delivered again harmlessly, while a copy rewritten with a new written_at or any changed field is a new handover and is acted on. The repeat test runs before the checks, a log it cannot read leaves the file in the inbox, and a failed move into archive/ or rejected/ now writes no event and leaves the file for the next tick. Dispositions in force rank by the order handovers were first consumed; two different handovers delivered out of order still rank by consume order (D-096). From M07-c (D-092 to D-094): the Mac message is posted by the notifier applet ~/.baton/bin/Baton.app, which install.sh builds, under the sender Baton with Claude's icon, and a click opens the session in Claude.app. This session inherits BATON_HOME=/Users/danny/.baton/m03-probe/home from the background service (D-091), so name the home in any command that must reach the real one.

CONSTRAINTS. Never use Python. Shell only: /bin/sh with set -eu, jq -e, awk, git; no third-party packages; sh tests/run.sh is the standing check and every check is reported as passed, failed or unrun with its output. Never write anything under /Users/danny/Documents/Apps/Reclaim — the migration is the person's commit, and a plan that does not parse is reported as a correction for them, not fixed by you. Never dispatch a Reclaim milestone from this session; the tick does that after your close-out. Never start, stop, attach to or resume any session except the one fixture-project session item 5 needs, and never one named Baton · Reclaim · …. A question for the person is asked in this session with AskUserQuestion, never as an asking artifact the milestone could have avoided, because an asking artifact stops and archives the session and leaves the question readable only in JSON (D-089). Every resume is flagless. The log has one writer. The deny list refuses a Bash command whose text names a state path under .baton (archive, rejected, prompts, projects, lock, notify and the rest); edit what you are allowed to through the editor, and do not rephrase a refused command to get past the rule. You are in a worktree Baton created; stage only your own paths by name, never git add -A; merge into main at close-out and refresh there. Commit locally with the existing git identity, a neutral technical message, no authorship trailers, never addressing a person; take the next free D-number at the moment you write the entry.

VERIFICATION. Per M08 §8. Report every check as passed, failed or unrun with its output; an unrun check is never reported as passed.

CLOSE-OUT, in this order, once the M08 checklist is finished.
1. Run /review-2 on this session's changes and do a hand pass over the same checklist while the reviewers work. Launch the two reviewers as background agents pinned to Fable rather than as teammates. A fixture you write for a finding should be shown failing before the fix. Record what was run and what returned.
2. When the review report is in, run /address. No git remote; commit fixes locally. Run sh tests/run.sh again after the fixes.
3. Append the handoff to docs/milestones/M08.md under "Completion evidence" using the docs/MILESTONES.md template. Add the docs/ARCHITECTURE.md §10 row M08 detail and the docs/DECISIONS.md entries for what you settled. Commit on m08.
4. Merge m08 into main in /Users/danny/Documents/Apps/Baton; if the merge fails, write ~/.baton/inbox/M08-$CLAUDE_CODE_SESSION_ID.json with outcome stopped and reason merge-failed and go no further. Run sh tests/run.sh on main; fix main if it fails, else write stopped with reason main-broken. On main: write done in M08's Status cell in docs/MILESTONES.md; leave the worktree ../Baton-M08 in place so this session can be resumed later; commit, staging only your own paths. Then run BATON_HOME=/Users/danny/.baton sh install.sh from /Users/danny/Documents/Apps/Baton, so the tick that consumes your handover runs the relay you merged — the home is named because this session inherits the background service's environment, which carried the M03 probe's BATON_HOME into M07-b's, M07-c's and M07-d's sessions (D-091); the install also rebuilds the notifier applet when its source, Claude's icon or install.sh changed. If it prints that the installed launchd agent differs, or a warning that the notifier applet could not be built, quote that line, because copying the agent and reloading it is a person's act and a failed applet leaves the Mac message on osascript.
5. Do not mark M08 complete unless every acceptance criterion in §8 holds; a split follows the split rule in docs/MILESTONES.md. There is no Baton milestone after M08; do not start anything in Reclaim.
6. Write ~/.baton/inbox/M08-$CLAUDE_CODE_SESSION_ID.json (.tmp first, then rename) with baton 1, project /Users/danny/Documents/Apps/Baton, milestone M08, your session id, outcome complete, merged_as the merge commit on main, written_at, and an empty eligible list — Baton's plan is complete. Print it verbatim, last, in a fenced block whose info-string is baton; if anything lands after it, deal with it and print it again.
```

````

## UNKNOWNS

| Unknown | What the repository establishes | Exactly what would resolve it |
|---|---|---|
| The prerequisites that blocked the user's particular cross-project attempt | M08 anticipates contract migration, registration permissions, a retained real transcript, and a cold-service access proof; it contains no completion evidence. `docs/milestones/M08.md:15–46,61–90,105–118`. | The failed attempt's command/output and target identity, plus the target's actual instructions, plan, starting brief, registration and applicable settings at that attempt. This audit did not inspect Reclaim's current tree. |
| Which relay and settings are actually installed now | Installation is a copy; the code does not report an installed source revision. D-091 records prior probe-home drift. `install.sh:14–17`; `docs/DECISIONS.md:103–103`. | Checksums/content comparison of installed scripts against this HEAD; the loaded LaunchAgent definition; its runtime H and Claude-state roots; and current registrations/settings. |
| Whether foundation contract-2 remains intended to govern this project | A current notice says it supersedes conflicts, the handoff describes different mechanisms, and its cited commit is not in HEAD's ancestry. `CLAUDE.md:3–7`; `docs/M03-FOUNDATION-HANDOFF.md:25–44`. | An explicit current authority decision and the integration/acceptance record for that decision. The separate foundation tree was not treated as implemented code. |
| Current Claude Code/macOS/app compatibility | Repository captures record specific versions and behavior, with several premises corrected by later live observations. `docs/milestones/M07.md:100–106,181–222`; `docs/milestones/M07-c.md:104–139`. | Versioned captures from the presently installed CLI, service and apps covering dispatch, hooks, stop/resume, row transitions, Remote Control and notification clicks. No current external compatibility claim follows from the historical captures alone. |
| Effective target settings, workspace trust and inherited environment | Dispatch supplies only a partial settings object; research records additional settings and trust layers. `lib/dispatch.sh:74–94,167–198`; `.scratch/baton/research/hooks.md:241–263`. | The target's effective merged settings and trust result, a captured launched-session environment with secrets redacted, and confirmation that the three intended callbacks actually ran. |
| Whether a real usage-limit ending exercises the intended wait path end to end | StopFailure-on-rate-limit remained unobserved in the recorded acceptance window; fixtures construct the payload. `docs/milestones/M04.md:357–362`; `docs/milestones/M07.md:288–324`; `tests/payloads/stop-failure.json:1–1`. | A versioned real-limit capture tying the CLI ending, hook payload, inbox artifact, consume, wait, resume, recovered progress and final completion together. |
| Fresh-machine setup completeness | The fresh-Mac criterion is explicitly unheld/unassessed; notifier permission was measured only on the existing Mac. `docs/milestones/M07.md:312–324`; `docs/milestones/M07-c.md:259–268`. | A clean-user or fresh-Mac installation record enumerating tools, authentication, grants, trust and notification prompts, ending in an observed target kickoff and handoff. |
| Frequency and impact of persistence/concurrency windows | The ordering defects are visible in source; in-memory checks demonstrated selected derivations, not simultaneous real writers. `lib/inbox.sh:394–453`; `lib/dispatch.sh:266–292`; `docs/milestones/M07-d.md:203–205`. | Reproducible fault/interleaving traces at launch, archive move, log append, park creation, hook writes, stale-lock replacement and post-lock marker writes. A double invocation at frozen time alone does not establish those behaviors. |
| Which additional Git execution/configuration behavior an arbitrary target introduces | Worktree creation disables core.hooksPath but otherwise invokes Git in the target repository; the test harness suppresses host Git config. `lib/dispatch.sh:44–54`; `tests/run.sh:32–34`. | The target's effective Git configuration/attributes and a controlled trace of worktree creation, including any filters, filesystem helpers or other configured execution. No such target behavior was asserted as present here. |
| Sustainable size, runtime and resource limits | Whole-log/transcript reads, retained worktrees and the partial cap are visible; recorded development runs are not a scale study. `lib/derive.sh:101–145,205–245`; `lib/tick.sh:245–277`. | Measurements of tick/status duration, argument sizes, disk growth and process/resource use across representative history sizes and target workloads. |
| Actual confidentiality and external data/rights constraints | Writers preserve raw text, Remote Control is requested, and the installer copies Claude's icon from an installed app. `lib/log.sh:99–107`; `lib/dispatch.sh:84–88`; `install.sh:101–107,125–136`. | Actual filesystem modes/access, the target's content policy, current connection/data-handling terms, and—if use expands beyond the documented personal applet—the applicable rights for the copied icon. The repository acknowledges Anthropic's mark; it does not establish broader permission or a legal violation. |
| Whether “universal” includes other hosts, runtimes and non-milestone workflows | V1 explicitly targets one person, one Mac and Claude Code; this audit ranks barriers to an arbitrary unfamiliar project and separately lists plausible absent capabilities. `docs/SPEC.md:13–26,51–56`. | A statement of the intended universality boundary. This would change relevance/ranking of platform/runtime exclusions, not the observed implementation facts. |


