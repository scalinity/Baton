#!/bin/sh
# lib/completion.sh — what a completion claim has to prove, and the evidence Baton produces itself.
#
# `merged_as_verify` asks whether a hexadecimal value resolves to a commit ancestral to `main`.
# This repository's own first commit answers yes, so an artifact naming it passes a check that was
# supposed to establish that a milestone's work was merged (L13). Ancestry alone proves that a
# commit is old, not that it is this milestone's.
#
# What binds a claim to the work is a chain of four commits, each resolved to its immutable id:
#
#     B  the dispatch baseline — the commit the milestone's worktree stood at when Baton
#        dispatched the attempt, recorded by the dispatch event and by nothing the session writes
#     T  the frozen candidate — the tip of that attempt's recorded branch, read once and used for
#        every derivation after it, so a branch that moves cannot substitute a second candidate
#     M  the integration commit — the artifact's own `merged_as`
#     V  the checked revision — the revision Baton actually ran the standing check on
#
# and four facts about them: B is an ancestor of T, T is an ancestor of M, M is on `main`, and V is
# M or a descendant of M on `main`. The middle one is the load-bearing one. Ancestry from B to M
# alone is satisfied by any old commit with scoped work on some unrelated branch; requiring the
# candidate itself to be inside M is what makes the claim name the work.
#
# The changed paths come from that same frozen T against B — the branch's own commits and nothing
# else, so parallel work that landed on `main` after the dispatch cannot stand in for this
# milestone's. At least one of them must fall inside the milestone's declared scope.
#
# The check result is Baton's. A session can write any string it likes; a string is not a test run.
# Baton checks out V into a tree of its own under `$BATON_HOME`, establishes that the tree really
# is V, runs the project's registered command in it under a deadline, and records the exit status
# it got. The three fields this file produces — `baseline`, `changed_paths` and `check_result` —
# are therefore Baton's alone, and an artifact carrying any of them is rejected (D-149).
#
# Every evidence-producing step happens before `archive_move`, which is what makes an archived
# artifact a checked one by construction, and is what lets the reconciliation of a lost `consumed`
# receipt be a receipt write rather than a second verification (D-146).
#
# On failure every function prints its detail on stdout and returns non-zero, as M02's do.
set -eu

# COMPLETION_PATHS_SHOWN and COMPLETION_PATH_CHARS: how many changed paths the `consumed` event
# carries, and how long each is allowed to be on it. The whole list goes to the evidence file; the
# event carries the head of it and the count.
#
# Both bounds matter, and the second is not decoration. `log_event` refuses a line at 4 KB, and a
# refused line after the artifact has already moved is a receipt that never gets written — which
# `inbox_reconcile` then finds unrecorded on the next tick, composes again at the same size, and
# fails at again, every sixty seconds, each failure also withholding the tick marker (D-133). Ten
# paths of three hundred characters reach that on their own, so the count alone does not bound the
# line. A hundred and twenty characters times ten is comfortably inside the limit beside the rest of
# the record, and the untruncated paths are a file away.
COMPLETION_PATHS_SHOWN=10
COMPLETION_PATH_CHARS=120

# COMPLETION_DEADLINE_DEFAULT: the standing check's deadline in seconds when the registration names
# none. Half an hour is past any run this repository has measured and short of a night.
COMPLETION_DEADLINE_DEFAULT=1800

# completion_baseline <project> <milestone> <attempt>: B and the branch, from that attempt's own
# `dispatch` event — the one record of where the session started that no session can write. Prints
# {baseline, branch}; prints the detail and returns 1 when the attempt has no dispatch.
#
# It is the **earliest** baseline recorded for the milestone on the branch this attempt was
# dispatched on, not the attempt's own. The two differ only after a redispatch, and there the
# earlier one is the right answer: a redispatch reuses the worktree, so its recorded baseline is
# the branch tip its predecessor left, and judging it against that asks it to redo work that is
# already on the branch. The ladder's ordinary shape is an attempt that commits and merges and then
# dies before writing its handover — `no-handover`, redispatch, and a successor whose whole job the
# recovery clause defines as finishing the close-out. Judged against its own baseline that
# successor changed nothing and an honest completion is refused, which is the outcome the
# acceptance list names as a failure rather than a pass (D-152, amending D-145).
#
# It is still a fact Baton recorded and never a guess: every candidate is a `baseline` on a
# `dispatch` event of this milestone, on this branch, at or before this attempt. What it does not
# do is let a *different* branch's baseline in, which is what the branch match is for.
#
# A dispatch written before M10 carries `worktree_commit` instead, and only when the worktree was
# reused. It is read as the baseline where it is there, and its absence leaves the field empty for
# `completion_chain` to fall back from.
completion_baseline() {
  cb_log=$(log_json) || { echo "$cb_log"; return 1; }
  cb_ev=$(printf '%s' "$cb_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" '
    [ .[] | select(.kind == "dispatch" and .project == $p and .milestone == $m and .attempt == $a) ]
    | last // empty')
  [ -n "$cb_ev" ] || { echo "no dispatch event names $1/$2 attempt $3"; return 1; }
  cb_branch=$(printf '%s' "$cb_ev" | jq -r '.branch // ""')
  printf '%s' "$cb_log" | jq -c --arg p "$1" --arg m "$2" --argjson a "$3" --arg b "$cb_branch" '
    [ .[] | select(.kind == "dispatch" and .project == $p and .milestone == $m
                   and (.attempt != null) and .attempt <= $a and (.branch // "") == $b)
          | (.baseline // .worktree_commit // "") | select(. != "") ]
    | {baseline: (first // ""), branch: $b}'
}

# completion_scope_patterns <repo> <milestone>: the milestone's declared scope, one pattern per
# line, read from its brief on `main` — `git show`, never the working tree, for the reason
# `brief_pointer_check` reads it there.
#
# The convention is the brief's existing `## 5. Expected files (proposed)` section, and the word
# proposed is the point: this is not an allowlist of everything the milestone may touch, it is a
# list of places its work must show up in. A changed path outside it is ordinary; a milestone with
# no changed path inside it did not do the work its brief describes.
#
# A pattern is a backticked span of that section that names a path — one holding a `/` or ending in
# an extension — with `{a,b}` expanded the way the briefs already write it and a `$VARIABLE` span
# dropped, because `$BATON_HOME` is deliberately outside the repository. Prints nothing with status
# 1 when the brief has no such section, which makes the milestone unprovable rather than
# trivially provable.
completion_scope_patterns() {
  csp_text=$(git -C "$1" show "main:docs/milestones/$2.md" 2>/dev/null) \
    || { echo "docs/milestones/$2.md is not on main in $1"; return 1; }
  # The section's absence is a different refusal from the section naming no path — a brief with no
  # §5 cannot be scoped at all, and reporting "nothing matched" of it would blame the branch — so
  # it is asked before the extraction rather than read out of a pipeline's status, which is the
  # last stage's and never awk's.
  printf '%s\n' "$csp_text" | grep -q '^## 5\.' \
    || { echo "docs/milestones/$2.md on main has no \"## 5.\" section"; return 1; }
  printf '%s\n' "$csp_text" | awk '
    # One awk program rather than a shell pipeline, because the work is string work: the section
    # walk, the backtick spans, the brace groups and the path test are each two lines here and
    # each a quoting problem in sh. A `case` pattern ending in a quoted expansion also cannot sit
    # inside `$(…)`, whose scanner reads the `)` ending that pattern list as the one closing the substitution.
    function keep(p) {
      sub(/\/+$/, "", p)                            # a trailing separator is how a brief spells a directory
      if (p == "") return
      if (p ~ /^\$/) return                         # $BATON_HOME and its kind are outside the repository
      if (p ~ /[ \t]/) return                       # a span with a space is prose, not a path
      if (p ~ /[{}]/) return                        # a group this program declined to guess at
      if (p !~ /\// && p !~ /\.[A-Za-z]+$/) return  # a path holds a separator or ends in an extension
      seen[p] = 1
    }
    # Every expansion of one span, breadth first and bounded: a brief that wrote a pathological
    # nest would otherwise cost the tick its minute. One group at a time, so a span with two
    # groups expands both.
    function expand(s,   queue, qn, qi, cur, head, list, tail, n, parts, k) {
      qn = 0; queue[qn++] = s
      for (qi = 0; qi < qn && qn < 256; qi++) {
        cur = queue[qi]
        if (match(cur, /\{[^{}]*,[^{}]*\}/)) {
          head = substr(cur, 1, RSTART - 1)
          list = substr(cur, RSTART + 1, RLENGTH - 2)
          tail = substr(cur, RSTART + RLENGTH)
          n = split(list, parts, ",")
          for (k = 1; k <= n; k++) queue[qn++] = head parts[k] tail
        } else {
          keep(cur)
        }
      }
    }
    /^## 5\./ { inside = 1; next }
    /^## / { inside = 0 }
    inside {
      # Odd fields are outside the backticks and even ones inside, so a line with one field
      # carries no span at all.
      n = split($0, part, "`")
      for (i = 2; i <= n; i += 2) if (part[i] != "") expand(part[i])
    }
    END { for (p in seen) print p }' | sort -u
}

# completion_in_scope <patterns> <path>: whether one changed path falls inside the declared scope.
# Equality, a directory prefix, or the pattern read as a glob — `tests/scenarios/completion-*` is
# how a brief names a family of fixtures, and `case` matches a separator inside `*` so the glob
# reaches the files under each.
completion_in_scope() {
  cis_patterns=$1; cis_path=$2
  printf '%s\n' "$cis_patterns" | while IFS= read -r cis_p; do
    [ -n "$cis_p" ] || continue
    if [ "$cis_path" = "$cis_p" ]; then echo match; break; fi
    case "$cis_path" in
      "$cis_p"/*) echo match; break ;;
    esac
    case "$cis_path" in
      $cis_p) echo match; break ;;
    esac
  done | grep -q match
}

# completion_chain <repo> <baseline> <branch> <merged_as>: B, T, M and the paths the branch
# changed, as one document, or the detail and status 1.
#
# T is resolved once, at the top, and every later step reads that value: a second `rev-parse` of
# the branch could answer with a commit the ancestry was never checked against, which is exactly
# the substitution §7.2 forbids. M arrives already verified against `main` by `merged_as_verify`
# and is resolved here to its full id so the three comparisons are between ids and never between
# a claim and an id.
#
# The baseline arrives resolved by the caller, which has already established that there is one.
# There is deliberately no fallback that derives it from the repository: at the moment a completion
# is judged, `main` already contains the merge, so the merge-base of the branch with `main` is the
# branch tip itself — a baseline equal to the candidate, an empty diff, and a milestone refused for
# having done nothing. A guessed baseline is worse than no baseline, because it refuses honest work
# while looking like proof (D-145).
completion_chain() {
  cc_repo=$1; cc_base=$2; cc_branch=$3; cc_merged=$4

  cc_t=$(git -C "$cc_repo" rev-parse --verify --quiet "refs/heads/$cc_branch^{commit}" 2>/dev/null) \
    || { echo "$cc_repo has no branch $cc_branch, so the attempt's candidate cannot be resolved"; return 1; }

  cc_m=$(git -C "$cc_repo" rev-parse --verify --quiet "$cc_merged^{commit}" 2>/dev/null) \
    || { echo "$cc_merged is not a commit in $cc_repo"; return 1; }

  cc_base=$(git -C "$cc_repo" rev-parse --verify --quiet "$cc_base^{commit}" 2>/dev/null) \
    || { echo "the dispatch baseline recorded for $cc_branch is not a commit in $cc_repo"; return 1; }

  git -C "$cc_repo" merge-base --is-ancestor "$cc_base" "$cc_t" \
    || { echo "the dispatch baseline $cc_base is not an ancestor of $cc_branch at $cc_t, so the branch is not this attempt's"; return 1; }
  git -C "$cc_repo" merge-base --is-ancestor "$cc_t" "$cc_m" \
    || { echo "$cc_branch at $cc_t is not an ancestor of $cc_merged, so the commit claimed as the merge does not carry the work"; return 1; }

  # `core.quotePath=false`, because its default emits `docs/café.md` as `"docs/caf\303\251.md"` —
  # quotes and octal escapes included — and that string matches neither the equality test, the
  # directory prefix nor the glob, so a milestone whose only in-scope change carried a non-ASCII
  # path would be refused for having done nothing (D-152).
  cc_changed=$(git -C "$cc_repo" -c core.quotePath=false diff --name-only "$cc_base" "$cc_t" 2>/dev/null) \
    || { echo "the changes between $cc_base and $cc_t could not be read in $cc_repo"; return 1; }

  jq -nc --arg b "$cc_base" --arg t "$cc_t" --arg m "$cc_m" --arg br "$cc_branch" \
    --argjson c "$(printf '%s' "$cc_changed" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    '{baseline: $b, candidate: $t, integration: $m, branch: $br, changed_paths: $c}'
}

# completion_scope_check <repo> <milestone> <changed paths json>: at least one changed path inside
# the milestone's declared scope. Prints the patterns that matched; the detail and status 1
# otherwise, naming what the brief asked for rather than only that nothing matched.
completion_scope_check() {
  csc_patterns=$(completion_scope_patterns "$1" "$2") || { echo "$csc_patterns"; return 1; }
  [ -n "$csc_patterns" ] \
    || { echo "docs/milestones/$2.md §5 on main names no path, so the milestone declares no scope"; return 1; }
  csc_n=$(printf '%s' "$3" | jq length); csc_i=0
  csc_hits=''
  while [ "$csc_i" -lt "$csc_n" ]; do
    csc_path=$(printf '%s' "$3" | jq -r ".[$csc_i]"); csc_i=$((csc_i + 1))
    if completion_in_scope "$csc_patterns" "$csc_path"; then
      csc_hits="$csc_hits$csc_path
"
    fi
  done
  if [ -z "$csc_hits" ]; then
    # The patterns are named in the refusal, because the two ways to reach it read the same from
    # outside and are opposite in whose fault they are: a branch that did not do the work, and a
    # brief whose §5 names its paths in prose rather than between backticks and so declares a
    # narrower scope than it means (D-150).
    csc_named=$(printf '%s' "$csc_patterns" | tr '\n' ' ')
    if [ "$csc_n" -eq 0 ]; then
      echo "the branch changed nothing against its dispatch baseline; $2 §5 declares ${csc_named% }"
    else
      if [ "$csc_n" -eq 1 ]; then
        echo "the one path the branch changed is not inside $2's declared scope, which is ${csc_named% }"
      else
        echo "none of the $csc_n paths the branch changed is inside $2's declared scope, which is ${csc_named% }"
      fi
    fi
    return 1
  fi
  printf '%s' "$csc_hits" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# completion_check_dir <project> <milestone> <attempt>: where the standing check's tree, its output
# and its evidence live. One directory per attempt, under Baton's own home, so a check leaves
# nothing in the project it checked.
completion_check_dir() { printf '%s/checks/%s/%s-%s\n' "$BATON_HOME" "$1" "$2" "$3"; }

# completion_check_command <project>: the project's standing check, as its registration records it.
# Prints {command, deadline}; the detail and status 1 when the registration names none.
#
# The registration and not the artifact, and not the project's `CLAUDE.md` either: a command read
# from the thing being checked is a command the thing being checked can choose, and `CLAUDE.md`
# names the check in prose that only a person or a model reads. `install.sh` writes the field, and
# a project registered without one has a completion Baton cannot prove (D-147).
completion_check_command() {
  ccc_pj=$BATON_HOME/projects/$1/project.json
  [ -f "$ccc_pj" ] || { echo "$1 has no registration at $ccc_pj"; return 1; }
  ccc_cmd=$(jq -r '.check.command // empty' "$ccc_pj" 2>/dev/null) || ccc_cmd=''
  [ -n "$ccc_cmd" ] \
    || { echo "$1 is registered without a standing check, so Baton cannot run one: add .check.command to $ccc_pj"; return 1; }
  # Validated as text before any arithmetic, then normalised through it: `0` would time every check
  # out before it started and `007` is not JSON `--argjson` will take, and both are things a hand
  # edit can leave behind. An unusable value falls back to the default rather than refusing, because
  # the deadline is a bound on the run and not a fact the record depends on.
  ccc_deadline=$(jq -r '.check.deadline_seconds // empty' "$ccc_pj" 2>/dev/null) || ccc_deadline=''
  case "$ccc_deadline" in
    ''|*[!0-9]*) ccc_deadline=$COMPLETION_DEADLINE_DEFAULT ;;
    *) [ "${#ccc_deadline}" -le 9 ] || ccc_deadline=$COMPLETION_DEADLINE_DEFAULT
       ccc_deadline=$((ccc_deadline + 0))
       [ "$ccc_deadline" -ge 1 ] || ccc_deadline=$COMPLETION_DEADLINE_DEFAULT ;;
  esac
  jq -nc --arg c "$ccc_cmd" --argjson d "$ccc_deadline" '{command: $c, deadline: $d}'
}

# completion_check_run <repo> <project> <milestone> <attempt> <revision>: the standing check, run by
# Baton on the tree at <revision>. Prints the result document; the detail and status 1 when the
# tree could not be made or is not the revision it was asked for.
#
# The tree is a detached worktree of the project's own repository, checked out at that revision and
# then asked what it stands at, because a checkout labelled with a sampled HEAD is a label and not
# a proof. It is removed afterwards: it carries no session, so D-078's reason for keeping a
# worktree — that a session whose working directory is gone cannot be resumed — does not reach it,
# and a tree kept per attempt would grow a copy of the repository every milestone (D-148).
#
# The deadline is enforced with a done-marker rather than by waiting on the child: a finished child
# is a zombie until it is reaped and answers `kill -0` as though it were still running, so polling
# liveness would never end. A run that passes its deadline is killed, with its children, and
# recorded as `timed-out`, which is not a pass. The kill reaches one generation: `sh -c` execs a
# simple command, so the ordinary case is the check itself, but a check that forks workers of its
# own can leave them behind.
#
# The marker is renamed into place rather than written where the poll can see it. `>` creates the
# file before anything is written to it, so a poll that tests only for its existence can read an
# empty string, take the `''` arm below, and record a check that *passed* as `unrun` — which parks
# the project. The window is small and the failure is silent, which is the combination worth
# spending a rename on.
#
# The deadline counts iterations of a one-second sleep plus the loop's own work, so it is a lower
# bound on wall clock rather than an exact limit, and a sleeping Mac spends it while asleep.
completion_check_run() {
  ccr_repo=$1; ccr_project=$2; ccr_milestone=$3; ccr_attempt=$4; ccr_rev=$5

  ccr_cmd_doc=$(completion_check_command "$ccr_project") || { echo "$ccr_cmd_doc"; return 1; }
  ccr_cmd=$(printf '%s' "$ccr_cmd_doc" | jq -r .command)
  ccr_deadline=$(printf '%s' "$ccr_cmd_doc" | jq -r .deadline)

  ccr_dir=$(completion_check_dir "$ccr_project" "$ccr_milestone" "$ccr_attempt")
  ccr_tree=$ccr_dir/tree
  ccr_out=$ccr_dir/output.txt
  mkdir -p "$ccr_dir" 2>/dev/null || { echo "$ccr_dir is not a directory Baton can write"; return 1; }
  rm -f "$ccr_out" "$ccr_out.exit" "$ccr_out.exit.tmp"
  if [ -e "$ccr_tree" ]; then
    git -C "$ccr_repo" worktree remove --force "$ccr_tree" > /dev/null 2>&1 || true
    rm -rf "$ccr_tree"
  fi
  # A tree whose directory went away — a tick killed mid-check, a cleared temporary directory — is
  # still registered, and `worktree add` refuses a registered path. Pruning drops only entries whose
  # directory is gone, so a live milestone worktree is never touched by it.
  git -C "$ccr_repo" worktree prune > /dev/null 2>&1 || true

  # core.hooksPath for the reason worktree_ensure empties it: `worktree add` runs the repository's
  # post-checkout hook, and a target project's hook is not Baton's to run.
  ccr_add=$(git -C "$ccr_repo" -c core.hooksPath=/dev/null worktree add --detach "$ccr_tree" "$ccr_rev" 2>&1) \
    || { echo "the tree at $ccr_rev could not be checked out: $ccr_add"; return 1; }

  ccr_head=$(git -C "$ccr_tree" rev-parse HEAD 2>/dev/null) || ccr_head=''
  if [ "$ccr_head" != "$ccr_rev" ]; then
    git -C "$ccr_repo" worktree remove --force "$ccr_tree" > /dev/null 2>&1 || true
    echo "the tree Baton checked out stands at ${ccr_head:-nothing}, not at $ccr_rev"
    return 1
  fi
  ccr_dirty=$(git -C "$ccr_tree" status --porcelain 2>/dev/null) || ccr_dirty=''
  if [ -n "$ccr_dirty" ]; then
    git -C "$ccr_repo" worktree remove --force "$ccr_tree" > /dev/null 2>&1 || true
    echo "the tree Baton checked out at $ccr_rev is not clean, so what ran would not be that revision"
    return 1
  fi

  # `set +e` inside the subshell, which inherits this file's `set -e`: without it a check that
  # failed would kill the subshell at the failing command, the marker would never be written, and
  # the poll below would run to the deadline and record a failing check as `timed-out`. A check
  # exiting non-zero is the ordinary case this exists to catch, not an error in the shell.
  ( set +e
    cd "$ccr_tree" && sh -c "$ccr_cmd" > "$ccr_out" 2>&1
    printf '%s\n' "$?" > "$ccr_out.exit.tmp" && mv "$ccr_out.exit.tmp" "$ccr_out.exit" ) &
  ccr_pid=$!
  ccr_waited=0
  ccr_timedout=no
  while [ ! -f "$ccr_out.exit" ]; do
    if [ "$ccr_waited" -ge "$ccr_deadline" ]; then
      ccr_timedout=yes
      pkill -TERM -P "$ccr_pid" 2>/dev/null || true
      kill -TERM "$ccr_pid" 2>/dev/null || true
      break
    fi
    sleep 1
    ccr_waited=$((ccr_waited + 1))
  done
  wait "$ccr_pid" 2>/dev/null || true

  if [ "$ccr_timedout" = yes ]; then
    ccr_exit=-1; ccr_outcome=timed-out
  else
    ccr_exit=$(cat "$ccr_out.exit" 2>/dev/null) || ccr_exit=''
    case "$ccr_exit" in
      ''|*[!0-9]*) ccr_exit=-1; ccr_outcome=unrun ;;
      0) ccr_outcome=passed ;;
      *) ccr_outcome=failed ;;
    esac
  fi
  rm -f "$ccr_out.exit"

  git -C "$ccr_repo" worktree remove --force "$ccr_tree" > /dev/null 2>&1 || true

  # How long it took is not recorded. It is the one number in the result that the machine decides
  # rather than the repository, so a frozen expectation holding it would fail on a loaded Mac and
  # pass on a quiet one; nothing reads it, and `timed-out` already says the deadline was reached.
  jq -nc --arg r "$ccr_rev" --arg c "$ccr_cmd" --arg o "$ccr_outcome" --argjson e "$ccr_exit" \
    --arg p "$ccr_out" \
    '{revision: $r, command: $c, outcome: $o, exit: $e, output: $p}'
}

# completion_evidence_write <project> <milestone> <attempt> <document>: the evidence file, written
# before the artifact moves so that the whole list of changed paths and the whole check result
# outlive a `consumed` line that carries only the head of them — and so a tick killed between the
# move and its event leaves evidence a later tick can still read back. Prints the path it wrote, or
# nothing when it could not write, which the caller reads as "no pointer to record".
#
# Renamed into place, so a reader that finds the file finds a whole one.
completion_evidence_write() {
  cew_dir=$(completion_check_dir "$1" "$2" "$3")
  mkdir -p "$cew_dir" 2>/dev/null || return 0
  printf '%s\n' "$4" > "$cew_dir/result.json.tmp" 2>/dev/null \
    && mv "$cew_dir/result.json.tmp" "$cew_dir/result.json" 2>/dev/null \
    && printf '%s\n' "$cew_dir/result.json"
  return 0
}

# completion_verify <repo> <project> <milestone> <session> <merged_as>: the whole of it, as the one
# document the `consumed` event carries and the evidence file holds in full.
#
# Two completions are recorded unproved rather than rejected, because in both there is no commit to
# bind the claim to: one with no recorded attempt, which is the hand-started bootstrap M01 still
# stands on and is not the unattended chain this exists to protect; and one whose attempt was
# dispatched before the baseline was recorded, which is every attempt in flight when this landed.
# Baton proves what Baton dispatched, and says plainly when it did not (D-145).
#
# Prints the document with status 0 for a proved completion, an unproved one, and a proved one
# whose check failed; prints {rule, detail} with status 1 for a chain or scope that does not hold,
# which is a rejection.
completion_verify() {
  cv_repo=$1; cv_project=$2; cv_milestone=$3; cv_session=$4; cv_merged=$5

  cv_attempt=$(attempt_for_session "$cv_project" "$cv_milestone" "$cv_session") \
    || { jq -nc --arg d "$cv_attempt" '{rule: "completion-chain", detail: $d}'; return 1; }
  if [ -z "$cv_attempt" ]; then
    jq -nc --arg d "no dispatch event names session $cv_session, so Baton did not start this milestone and has no baseline to bind it to" \
      '{proved: false, why: $d}'
    return 0
  fi

  cv_disp=$(completion_baseline "$cv_project" "$cv_milestone" "$cv_attempt") \
    || { jq -nc --arg d "$cv_disp" '{rule: "completion-chain", detail: $d}'; return 1; }
  cv_base=$(printf '%s' "$cv_disp" | jq -r .baseline)
  cv_branch=$(printf '%s' "$cv_disp" | jq -r .branch)

  # An attempt dispatched before the baseline was recorded is the same case as one Baton never
  # dispatched: there is no commit to bind the claim to, and there is no honest way to recover one
  # after the merge has landed on `main`. It is recorded unproved with the reason, not rejected —
  # refusing every milestone already in flight when this landed would park lanes for having been
  # started a day early (D-145, M10 §7.5).
  if [ -z "$cv_base" ] || [ -z "$cv_branch" ]; then
    cv_unproved=$(jq -nc --argjson a "$cv_attempt" --arg d "the dispatch of attempt $cv_attempt recorded no baseline, so it predates the record a completion is bound to and there is nothing to bind this claim to" \
      '{proved: false, attempt: $a, why: $d}')
    # Written to the evidence file as a proved one is, so that a receipt reconciled later says the
    # same thing as the receipt this consumption writes now. A reader comparing two records of one
    # ending should not find the shape of the answer depending on which tick wrote it.
    completion_evidence_write "$cv_project" "$cv_milestone" "$cv_attempt" "$cv_unproved" > /dev/null
    printf '%s\n' "$cv_unproved"
    return 0
  fi

  cv_chain=$(completion_chain "$cv_repo" "$cv_base" "$cv_branch" "$cv_merged") \
    || { jq -nc --arg d "$cv_chain" '{rule: "completion-chain", detail: $d}'; return 1; }

  cv_hits=$(completion_scope_check "$cv_repo" "$cv_milestone" "$(printf '%s' "$cv_chain" | jq -c .changed_paths)") \
    || { jq -nc --arg d "$cv_hits" '{rule: "completion-scope", detail: $d}'; return 1; }

  cv_rev=$(printf '%s' "$cv_chain" | jq -r .integration)
  if ! cv_check=$(completion_check_run "$cv_repo" "$cv_project" "$cv_milestone" "$cv_attempt" "$cv_rev"); then
    cv_check=$(jq -nc --arg r "$cv_rev" --arg d "$cv_check" '{revision: $r, outcome: "unrun", exit: -1, detail: $d}')
  fi

  cv_full=$(printf '%s' "$cv_chain" | jq -c --argjson a "$cv_attempt" --argjson c "$cv_check" \
    --argjson h "$cv_hits" '{proved: true, attempt: $a} + . + {in_scope: $h, check: $c}')

  cv_evidence=$(completion_evidence_write "$cv_project" "$cv_milestone" "$cv_attempt" "$cv_full")

  completion_summary "$cv_full" "$cv_evidence"
}

# completion_summary <full document> <evidence path>: the document as the `consumed` event carries
# it — the head of the changed paths with the count beside it, every unbounded field cut, and the
# evidence pointer where the whole of it can be read. One definition, for D-146's own reason: the
# consumption and the reconciliation both need it, and two spellings would be two records.
#
# The cuts are in bytes and not in entries. `log_event` refuses a line at 4096 bytes, and a refusal
# here lands after `archive_move` has already run, so the receipt is never written — and then
# `inbox_reconcile` finds the file unrecorded, composes the same oversized line, and is refused
# again, every sixty seconds, for as long as Baton runs. A count bound alone does not prevent that:
# ten paths reach it on their own at three hundred characters each, and `check.detail` carries
# git's stderr at whatever length git chose. Cut like `asking_carries` cuts, at the source.
completion_summary() {
  printf '%s' "$1" | jq -c --arg e "$2" --argjson n "$COMPLETION_PATHS_SHOWN" \
    --argjson c "$COMPLETION_PATH_CHARS" '
    def cut($n): tostring | if (utf8bytelength <= $n) then . else .[0:$n] + "…" end;
    . + {changed_count: (.changed_paths | length)}
    | .changed_paths |= [ .[0:$n][] | cut($c) ]
    | if has("check") then .check |= (.command |= cut(200)
                                      | if has("detail") then .detail |= cut(300) else . end)
      else . end
    | del(.in_scope)
    | if $e != "" then . + {evidence: $e} else . end'
}

# completion_park_carries <completion json> <archive path>: what the `main-broken` park says when
# Baton's own run of the standing check did not pass. One definition, because two sites write this
# park — the consumption that found the result, and the reconciliation that finds the park was never
# written — and two spellings of one park is how a person comes to read two different accounts of
# one failure (D-152).
#
# Two sentences and not one with a hole in it: a check that never started has no command and no
# output to point at, and "Baton ran null … and it unrun" is the shape of a message assembled from
# fields rather than written.
completion_park_carries() {
  printf '%s' "$1" | jq -c --arg a "$2" '
    {detail: (if .check.detail
              then "Baton could not run the standing check on the tree at \(.check.revision): \(.check.detail)"
              else "Baton ran \(.check.command) on the tree at \(.check.revision), and it \(.check.outcome); its output is at \(.check.output)"
              end),
     archive: $a}'
}

# completion_park_owed <project>: the completions this project has recorded whose check did not pass
# and whose `main-broken` park was never written — one `{milestone, session, attempt, at, archive,
# completion}` per line of JSON, newest last.
#
# The park is a second append, a few statements after the `consumed` line that carries the failing
# result. A tick killed between them, or an `escalate` that refused, leaves a consumed completion
# with no park, and nothing re-derives one: `derive_parked` reads `escalation` events, and the
# unrecorded sweep only finishes files that have no receipt at all. The next tick would then
# dispatch the next milestone on a `main` Baton has already established does not build, which is
# the ending this milestone exists to stop (D-152).
#
# A park written and then resolved is not owed again: the test is whether any `main-broken`
# escalation for the project exists at or after the consumption, not whether one is open now. A
# person who answered the park has answered it.
completion_park_owed() {
  cpo_log=$(log_json) || { echo "$cpo_log"; return 1; }
  printf '%s' "$cpo_log" | jq -c --arg p "$1" '
    [ .[] | select(.kind == "escalation" and .project == $p and .class == "main-broken") | .at ] as $parks
    | .[]
    | select(.kind == "consumed" and .project == $p and .outcome == "complete")
    | select((.completion.check.outcome // "passed") != "passed")
    | . as $c
    | select([ $parks[] | select(. >= $c.at) ] | length == 0)
    | {milestone, session, attempt, at, archive, completion}
    | with_entries(select(.value != null))'
}

# completion_reserved_check <artifact>: the three fields this file produces are Baton's, and an
# artifact carrying one of them is rejected. A session that writes `"check_result": "passed"` is
# not reporting a test run, it is asserting one, and the whole of L13 is that an assertion read as
# evidence advances a chain nothing checked. Refusing the field is how the artifact's shape says
# so, rather than Baton silently overwriting a claim a person may later read and believe (D-149).
completion_reserved_check() {
  # The key is bound before the pipe. Inside `$a | has(.)` the dot is `$a` itself, which asks an
  # object whether it has an object as a key and raises, and the raise was swallowed here into
  # "nothing reserved" — a refusal that silently never refuses.
  crc_bad=$(printf '%s' "$1" | jq -er '
    . as $a | ["baseline", "changed_paths", "check_result"]
    | map(select(. as $k | $a | has($k))) | join(" and ")') || {
    echo "the artifact could not be read for the fields only Baton writes"
    return 1
  }
  [ -z "$crc_bad" ] || { printf 'the artifact carries %s, which only Baton writes\n' "$crc_bad"; return 1; }
}
