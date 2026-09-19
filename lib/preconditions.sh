#!/bin/sh
# lib/preconditions.sh — what a dispatch needs before it creates anything, read once and shared.
# `verb_plan` reports every eligible milestone's result and `dispatch_one` refuses on the same
# result before `worktree_ensure` runs, so a knowable defect costs no branch, worktree, settings
# file, prompt sidecar, session or caffeinate process, and a person is told about every eligible
# milestone's defects in one pass rather than one dispatch at a time.
#
# Nothing here writes, composes settings, creates a worktree, runs a verb or touches a session. The
# brief is read through `prompt_from_brief`, the one parser, so the three cases that function
# already distinguishes stay its own and are not written a second time here (D-098 keeps the
# inbox's near-duplicate checker separate for now, deliberately).
set -eu

# The stage each check reports under is one of the existing `dispatch_failed` stages, so no new
# event kind or stage is introduced: a `prompt` defect is in the brief's own text, a `worktree`
# defect is in the ground the worktree would be made from, and a `settings` defect is in the rules
# the settings file would be composed out of.

# permissions_inspect <project>: the project's `permissions.json` present, parsing, and carrying the
# deny rules `settings_compose` refuses to compose without. Read-only: it never writes a settings
# file and never widens anything. Prints nothing on success; on failure prints the detail and
# returns 1. The guard it mirrors stays where it is, in `settings_compose`, and still runs there.
permissions_inspect() {
  pi_perm=$BATON_HOME/projects/$1/permissions.json
  pi_need="Baton needs $1's permission rules at $pi_perm to carry the two deny classes a bypassPermissions session runs behind (docs/SPEC.md REQ-PERM-04)."
  pi_repair="Restore the owner's deny rules yourself, then dispatch again: vi $(shell_word "$pi_perm")"
  [ -f "$pi_perm" ] || { printf '%s\n' "$pi_need The file does not exist. $pi_repair"; return 1; }
  if ! pi_len=$(jq -e '(.permissions.deny // []) | length' "$pi_perm" 2>&1); then
    printf '%s\n' "$pi_need It does not parse as JSON holding permissions.deny: $(printf '%s' "$pi_len" | head -1). $pi_repair"
    return 1
  fi
  case "$pi_len" in
    0) printf '%s\n' "$pi_need permissions.deny is empty, and a session without that rail is not dispatched. $pi_repair"; return 1 ;;
  esac
}

# prompt_references: the kickoff prompt on stdin, every `docs/…` reference it names on stdout, one
# per line as "<kind> <token>", deduplicated in first-seen order:
#   path <p>        a concrete path to look up on main
#   ambiguous <t>   a reference no concrete path can be read out of without evaluating the text
# A template placeholder — `docs/milestones/<ID>.md` — is neither: a brief that writes one means the
# shape of a path, not a filename, so it is passed over rather than reported. Shell text is never
# evaluated: a reference carrying a variable or a glob is reported as needing a concrete path
# instead of being guessed at or silently dropped. Finite brace alternatives are expanded, because
# `docs/{a,b}.md` names two files and both are knowable; a range or a nested brace is not.
#
# Markdown delimiters and sentence punctuation are trimmed off the ends of a word and a closing
# delimiter inside one ends it, so `docs/SPEC.md`, (docs/SPEC.md), "docs/SPEC.md" and
# [docs/SPEC.md](docs/SPEC.md) all yield the same spelling — which is otherwise preserved exactly.
prompt_references() {
  awk -v q="'" '
    BEGIN {
      lead  = "`\"" q "([*_"
      trail = "`\"" q ")],.;:!?*_"
      cut   = "`\"" q ")]"
    }
    function trimmed(w,   c) {
      while (length(w) > 0 && index(lead, substr(w, 1, 1)) > 0) w = substr(w, 2)
      while (length(w) > 0 && index(trail, substr(w, length(w), 1)) > 0) w = substr(w, 1, length(w) - 1)
      for (c = 1; c <= length(w); c++) if (index(cut, substr(w, c, 1)) > 0) return substr(w, 1, c - 1)
      return w
    }
    function out(kind, token) {
      if ((kind " " token) in seen) return
      seen[kind " " token] = 1
      print kind, token
    }
    function expand(w,   o, c, pre, mid, post, n, parts, i) {
      o = index(w, "{"); c = index(w, "}")
      if (o == 0 || c == 0 || c < o) { out("ambiguous", w); return }
      pre = substr(w, 1, o - 1); mid = substr(w, o + 1, c - o - 1); post = substr(w, c + 1)
      if (mid == "" || index(mid, "{") > 0 || index(mid, "..") > 0 \
          || index(post, "{") > 0 || index(post, "}") > 0) { out("ambiguous", w); return }
      n = split(mid, parts, ",")
      if (n < 2) { out("ambiguous", w); return }
      for (i = 1; i <= n; i++) if (parts[i] == "") { out("ambiguous", w); return }
      for (i = 1; i <= n; i++) out("path", pre parts[i] post)
    }
    function classify(w) {
      w = trimmed(w)
      if (w !~ /^docs\//) return
      if (index(w, "<") > 0 || index(w, ">") > 0) return
      if (index(w, "$") > 0 || index(w, "*") > 0 || index(w, "?") > 0 || index(w, "[") > 0) { out("ambiguous", w); return }
      if (index(w, "{") > 0 || index(w, "}") > 0) { expand(w); return }
      out("path", w)
    }
    { for (i = 1; i <= NF; i++) classify($i) }
  '
}

# dispatch_preconditions <project> <milestone>: the whole read-only inspection, as one JSON object
#
#   { project, milestone, brief, worktree, branch, references_inspected,
#     failures: [ { check, stage, path, detail } ] }
#
# `failures` is ordered — the checkout, then the brief, its slot paragraph and the documents it
# names, then the branch and worktree, then the permission rules — and empty when every
# precondition is met. `path` is the file the failure's repair names, so a reader has somewhere to
# go without parsing the detail. `check` is a stable name; `stage` is the existing dispatch stage.
#
# Status 0 when the inspection was made, whatever it found. Status 1, with the detail on stdout,
# when it could not be made at all — a different thing from a milestone that is not ready, which a
# caller must not read as success.
dispatch_preconditions() {
  dp_project=$1; dp_id=$2
  dp_path=$(project_path "$dp_project") \
    || { echo "$BATON_HOME/projects/$dp_project/project.json does not name a checkout"; return 1; }
  dp_brief=docs/milestones/$dp_id.md
  dp_names=$(worktree_of "$dp_path" "$dp_id")
  dp_wt=$(printf '%s' "$dp_names" | jq -r .worktree)
  dp_branch=$(printf '%s' "$dp_names" | jq -r .branch)
  dp_commit="git -C $(shell_word "$dp_path") add -- $(shell_word "$dp_brief") && git -C $(shell_word "$dp_path") commit -m $(shell_word "Record $dp_id brief")"
  dp_fail='[]'
  dp_refs=false

  # 1. The checkout. Both the brief and the worktree come from `main`, so a checkout without one is
  # the ground failing under every other check rather than a defect in this milestone's brief.
  if dp_head=$(git -C "$dp_path" rev-parse --verify --quiet "main^{commit}" 2>&1); then
    dp_usable=true
  else
    dp_usable=false
    dp_add main worktree "$dp_path" "Baton needs $dp_project's checkout at $dp_path to have a main branch: every brief is read from main and every milestone worktree is created from it. main does not resolve to a commit there${dp_head:+ ($(printf '%s' "$dp_head" | head -1))}. Repair the checkout yourself, then check it with: git -C $(shell_word "$dp_path") rev-parse --verify main"
  fi

  # 2. The brief on main, its slot paragraph, and the documents it names.
  if [ "$dp_usable" = true ]; then
    if dp_prompt=$(prompt_from_brief "$dp_path" "$dp_brief" "Copy-ready session prompt"); then
      dp_refs=true
      if ! dp_slot=$(slot_line "$dp_prompt" "WHAT ELSE IS IN FLIGHT."); then
        dp_add slot prompt "$dp_brief" "Baton needs $dp_id's kickoff prompt to carry the slot paragraph it replaces at dispatch with what else is in flight: $dp_slot Write the paragraph \"WHAT ELSE IS IN FLIGHT. Runs alone unless the dispatch says otherwise.\" into the fenced block under \"## Copy-ready session prompt\", then commit it on main: $dp_commit"
      fi
      dp_reflist=$(printf '%s' "$dp_prompt" | prompt_references)
      while read -r dp_kind dp_token; do
        [ -n "$dp_kind" ] || continue
        if [ "$dp_kind" = ambiguous ]; then
          dp_add reference-ambiguous prompt "$dp_brief" "Baton needs every document $dp_id's kickoff prompt names to be a concrete path it can look up on main. \"$dp_token\" is not one, and Baton never evaluates the text to find out what it means. Write the concrete path into the fenced block under \"## Copy-ready session prompt\", then commit it on main: $dp_commit"
          continue
        fi
        dp_ref=${dp_token%/}
        if ! git -C "$dp_path" cat-file -e "main:$dp_ref" 2>/dev/null; then
          dp_add reference prompt "$dp_ref" "Baton needs every document $dp_id's kickoff prompt names to be on main, because the session is told to read them and its worktree is created from main. It names $dp_token, which main does not have. Write or restore that document, then commit it on main: git -C $(shell_word "$dp_path") add -- $(shell_word "$dp_ref") && git -C $(shell_word "$dp_path") commit -m $(shell_word "Record $dp_ref")"
        fi
      done <<REFS
$dp_reflist
REFS
    else
      dp_add brief prompt "$dp_brief" "$dp_prompt"
    fi
  fi

  # 3. The branch and the worktree, when either already exists. An existing worktree is read at its
  # own HEAD rather than at the branch it is expected to carry, and a readable old copy of the brief
  # is not taken as proof that the brief's commit arrived — the two answer different questions, so
  # both are asked. Nothing here requires unrelated main commits to be merged, a clean worktree, or
  # the loss of a branch-local completion-evidence edit.
  dp_briefcommit=
  [ "$dp_usable" = false ] || dp_briefcommit=$(git -C "$dp_path" log -1 --format=%H main -- "$dp_brief" 2>/dev/null || true)
  dp_carries="the commit that last changed $dp_brief on main, because the session reads its brief in that worktree"
  if [ -d "$dp_wt" ]; then
    if ! dp_wthead=$(git -C "$dp_wt" rev-parse HEAD 2>&1); then
      # `worktree_ensure`'s own words for this, unchanged: what to do with a directory Baton did not
      # create and cannot read is a person's judgement, and Baton does not script moving it away.
      dp_add worktree worktree "$dp_wt" "$dp_wt exists but is not a worktree: $dp_wthead"
    else
      dp_stale=false
      if [ -n "$dp_briefcommit" ] && ! git -C "$dp_wt" merge-base --is-ancestor "$dp_briefcommit" "$dp_wthead" 2>/dev/null; then
        dp_stale=true
        dp_add branch worktree "$dp_wt" "Baton needs $dp_id's worktree $dp_wt to stand on $dp_carries. Its HEAD does not contain that commit. Bring main into the branch yourself: git -C $(shell_word "$dp_wt") merge main"
      fi
      if [ ! -r "$dp_wt/$dp_brief" ]; then
        # Which repair is the honest one turns on the answer ancestry gave. A branch that is behind
        # needs main brought into it; a branch that already carries the commit needs the one path
        # put back, and naming a merge there would be advice that changes nothing.
        if [ "$dp_stale" = true ]; then
          dp_repair="Bring main into the branch yourself: git -C $(shell_word "$dp_wt") merge main"
        else
          dp_repair="The branch already carries that commit, so put back the one path yourself: git -C $(shell_word "$dp_wt") checkout HEAD -- $(shell_word "$dp_brief")"
        fi
        dp_add worktree-brief worktree "$dp_wt" "Baton needs $dp_id's brief $dp_brief readable in its own worktree $dp_wt, because that is the copy the session reads. The worktree has no readable copy of it. $dp_repair"
      fi
    fi
  elif [ "$dp_usable" = true ] && git -C "$dp_path" show-ref --verify --quiet "refs/heads/$dp_branch"; then
    if [ -n "$dp_briefcommit" ] && ! git -C "$dp_path" merge-base --is-ancestor "$dp_briefcommit" "refs/heads/$dp_branch" 2>/dev/null; then
      dp_add branch worktree "$dp_wt" "Baton needs $dp_id's branch $dp_branch to contain $dp_carries. The branch does not contain that commit and has no worktree yet. Create the worktree on that branch and merge main into it yourself: git -C $(shell_word "$dp_path") worktree add $(shell_word "$dp_wt") $(shell_word "$dp_branch") && git -C $(shell_word "$dp_wt") merge main"
    fi
  fi

  # 4. The permission rules the settings file would be composed out of, inspected without composing
  # or writing one.
  dp_perm=$(permissions_inspect "$dp_project") \
    || dp_add permissions settings "$BATON_HOME/projects/$dp_project/permissions.json" "$dp_perm"

  jq -nc --arg p "$dp_project" --arg m "$dp_id" --arg b "$dp_brief" --arg w "$dp_wt" --arg br "$dp_branch" \
    --argjson r "$dp_refs" --argjson f "$dp_fail" \
    '{project: $p, milestone: $m, brief: $b, worktree: $w, branch: $br, references_inspected: $r, failures: $f}'
}

# dp_add <check> <stage> <path> <detail>: one failure onto the ordered array. A helper of
# `dispatch_preconditions` alone, which is why it reads and writes that function's variable.
dp_add() {
  dp_fail=$(printf '%s' "$dp_fail" | jq -c --arg c "$1" --arg s "$2" --arg p "$3" --arg d "$4" \
    '. + [{check: $c, stage: $s, path: $p, detail: $d}]')
}
