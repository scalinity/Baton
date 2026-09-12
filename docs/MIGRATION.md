# Migration and operation

## Existing M03 work

M03 is already in progress on `m03` in `Baton-M03`. Do not restart it or replace its runtime/docs
wholesale with the foundation checkout. Read `GOVERNANCE.md` and `M03-RECONCILIATION.md`, preserve
its current work, and prepare a combined candidate at a coherent checkpoint. The new foundation
dependency governs compatibility acceptance, not whether M03 may already have started.

M03 recorded that its copied shell needed ad-hoc signing to execute on this host; signature
verification alone passed on the unusable copy. Preserve that finding and its host-specific evidence.
The foundation installer's copy step alone is not launchd readiness. Bring the validated shell setup,
immutable release/plist integration and outstanding cold-start proof together before activation.

## Before activating contract 2

Run `sh tests/run.sh` in the checkout and review the changes. Preserve a copy of existing Baton state
and finish or claim active legacy work. Installation does not migrate artifacts, rewrite registrations,
accept bypass disclaimers, grant Full Disk Access, change provider settings or load launchd.

A contract-2 project registration contains:

```json
{
  "path": "/absolute/canonical/checkout",
  "plan": "docs/MILESTONES.md",
  "contract": 2,
  "check": ["sh", "tests/run.sh"],
  "checkReplaySafe": true,
  "gateApprovals": {}
}
```

The check is the project's actual, authorized, synchronous standing check. It must be safe to rerun
after interruption and must not modify the checked Git tree or leave background workers running.
For projects requiring builds, obtain the project's normal build authorization before invoking
integration. Registering a command is not permission to violate the user's build restrictions.

Migrate the target's contract and milestone prompts before changing `contract` to 2. Workers now
prepare their close-out on their branch, use `baton integrate <run>`, and publish immutable messages.
Remove instructions to merge/repair canonical main, remove worktrees, recursively refresh briefs,
or enumerate successor dispositions. Gate approvals are separate person-owned authorization tokens.

Configure `claudeVersion` to an actually validated provider version and retain the response-shape
checks. The seeded 2.1.268 value records the original prototype; changing it alone does not validate
a new provider. Set `trustedLocal: true` only when intentionally choosing same-account execution
with bypass mode. Pattern deny lists do not isolate files or processes. A new installation defaults
to false. The original allowlist-widening flow is not part of the contract-2 bypass interface.

## Install and rollback

`sh install.sh` assembles an immutable release under `releases/<content-sha>/`, then atomically
selects it with `current`. `bin/baton` resolves that release once per invocation. Dispatched settings
pin its absolute hooks. Existing registrations/config remain unchanged; inspect them deliberately.
Use the installed wrapper for real dispatch; checkout execution is used by fixture tests.

Keep prior releases while sessions reference them. Rollback requires verifying that the older
release understands the current protocol and journal. In particular, **do not run the version-1
mutator against a version-2 home**. Preserve the version-1 backup separately if reverting the whole
installation. No version of the installer in this foundation deletes old work or releases.

## Legacy sessions and artifacts

Version-1 logs are historical evidence. They do not grant run authority. Version-1 inbox files fail
the contract-2 schema and are retained in rejected/. Unmatched archive files are reported by status;
never silently replay them as completions because their prior side effects are unknown.

For a hand-started session, `baton adopt <project> <milestone> <session>` requires exactly one live
provider row in a linked worktree of the registered repository, a readable transcript and an eligible
milestone. It records a new run as human-owned. It does not retrofit the provider's old hook settings.
Update the session's instructions and publication method, or finish it manually and start a fresh
managed run. `baton release <run>` then explicitly acknowledges the current typed-record boundary.
A session in canonical main must first move its work to an appropriate linked worktree; adoption
never blesses concurrent canonical editing.

## Recover without guessing

- `baton status` works while another mutation holds the lock. It exposes provider failures,
  ownership, questions, processing leftovers and pending integration.
- `baton reconcile` reads a healthy fleet, acknowledges exact matching uncertain launches and
  resumes inbox processing. It never starts another process to compensate for an unknown result.
- A prepared local failure or unmatched uncertain launch remains reserved. Inspect it; use
  `baton abandon <run> '<reason>'` only after establishing the deliberate disposition. The command
  requires a healthy listing with no matching live run and preserves all work.
- Claim before manual control. Release acknowledges a specific typed record; repeated text does
  not count as the same record. Missing/unreadable ownership evidence holds automatic integration.
- Fix a failed integration candidate, then use `baton integrate <run> --retry`. This preserves the
  previous operation. If a checked operation may have promoted, repeat normal integration to
  reconcile, including when later human commits have advanced main beyond the verified commit;
  --retry refuses to discard its receipt. Checks are bounded and their process groups are cleaned
  up before failure is returned; successful parents may not leave unchecked background workers.
- A torn **legacy** journal needs manual inspection/restoration. Current journal replacement avoids
  new partial append tails on process interruption. It does not promise power-loss durability.

## Scope that remains unimplemented

No tick is installed or enabled by the foundation changes. M03 has a separate, actively developed
tick/notification/launchd implementation; its actual running/installed state is not inferred from
this statement. Automated resumes, answer delivery, model quota
policy, remote operation and multiple simultaneous workers within one project remain their revised
milestones. Status presents their evidence without pretending that those actions are scheduled.

## Recovery from a saved checkpoint or damaged state

This is an operator procedure for F-45; the foundation does not implement an automatic restore or
repair command. M08 must rehearse it in fixtures and document target-specific operation before
claiming tested operational recovery.

1. Establish which controller/release owns mutation and record live work. Obtain a coherent copy
   while that writer is quiescent or through a proved snapshot mechanism; copying files while they
   change is not a transactional backup. Do not interrupt an agent merely because this document exists.
2. Preserve the original damaged bytes and provenance. Keep the journal together with referenced
   messages/archives, prompts, receipts, configuration, release identity and candidate Git work.
   Missing referenced evidence is a recovery problem, not a field to fill with a guess.
3. Inspect a candidate restoration in an isolated home with mutation disabled. Validate record
   structure, IDs, message hashes, receipt/commit references and protocol/release compatibility.
   An older executable may not understand newer state even if it can parse the JSON.
4. Observe the current provider and Git state. Effects may have happened after the restored
   checkpoint: a process may already exist, a prompt may already have been delivered, or a checked
   commit may already be on main. A backup does not undo them. Reconcile or retain uncertainty;
   never blindly replay all prepared requests or manufacture their acknowledgements.
5. Record the recovery disposition and evidence before resuming mutation through one writer.
   Keep human ownership and unresolved work intact. A missing process observation is unavailable,
   not permission to cancel, abandon or redispatch automatically.

Future cleanup/retention must preserve everything still referenced by an open operation or required
for recovery. The current no-pruning policy remains; this procedure adds no automatic deletion,
new runtime command, deployment or power-loss guarantee.
