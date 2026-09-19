#!/bin/sh
# lib/dispatch.sh — step 8 of the tick as functions: the worktree, the settings file, the prompt
# from the brief on main, the slot line, claude --bg, the row, the sidecar, caffeinate and the
# dispatch event; plus the hand-run dispatch verb. On failure every function prints its detail
# on stdout and returns non-zero, so a caller captures once and branches on the status.
set -eu

# One cleanup admission per process (one tick or hand-run verb). Claim it in dispatch_one's
# caller shell, before any command substitution, so another candidate cannot replenish it.
do_cleanup_spent=false

# Launches this process could not prove started nothing. A `claude --bg` whose id did not parse, or
# whose row never appeared, may have left a worker running; when that worker is neither identified
# nor stopped — the cleanup budget was already spent, no job answered to the lane's name, or the stop
# was refused or never settled — nothing names it. No `dispatch` event was written, so derivation 1
# cannot count it, and the cap would admit over it: this is the other half of the same defect as a
# lane counted against a stale listing (D-130). `dispatch_run` adds this to the in-flight count, so
# an unresolved launch occupies a slot until something proves it did not start.
#
# A count and not a flag, because one tick can leave more than one behind. Claimed in the caller's
# shell like the budget above, and for the same reason. It lives no longer than the process: the next
# tick reads the listing from nothing, and a worker that really started carries a row there like any
# other — so the conservative reading costs at most the rest of one tick and needs no file, no clock
# and no event of its own.
do_unresolved=0

# row_for_id <id>: the agents row whose id is <id> and which carries a pid, polled for up to
# thirty seconds because the row appears a beat after backgrounded is printed. A worker that
# crashes before init never gets a row; the service records that in its own log as
# "bg settled <id> (crashed): <detail>" (item 47, D-027), so the poll reads that line and stops
# early. Prints the row, or the failure's detail.
row_for_id() {
  rf_i=0
  while [ "$rf_i" -lt 60 ]; do
    rf_row=$(rows_json | jq -ce --arg id "$1" 'map(select(.id == $id and .pid != null)) | first // empty' 2>/dev/null) \
      && { printf '%s\n' "$rf_row"; return 0; }
    if [ -f "$BATON_DAEMON_LOG" ]; then
      rf_settled=$(grep -F "bg settled $1 (crashed): " "$BATON_DAEMON_LOG" | tail -1 | sed 's/.*(crashed): //') || true
      if [ -n "$rf_settled" ]; then
        echo "session $1 was backgrounded and crashed before init: $rf_settled"
        return 1
      fi
    fi
    rf_i=$((rf_i + 1))
    sleep 0.5
  done
  echo "session $1 was backgrounded but no row with a pid appeared within thirty seconds"
  return 1
}

# worktree_entries <path>: this repository's registered worktrees, one "<path>\t<branch ref>" line
# each, detached and bare entries left out. Read from `git worktree list --porcelain`, which is
# git's own record and which `git worktree move` keeps correct — the only reading of a worktree's
# location that survives one (D-153). Empty, with status 0, when the path is not a repository at
# all: `dispatch_preconditions` asks for the names before it has established the checkout is
# usable, and a missing repository is that check's answer to give, not this one's.
worktree_entries() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { p = substr($0, 10); b = ""; next }
    /^branch /   { b = substr($0, 8); next }
    /^$/         { if (p != "" && b != "") print p "\t" b; p = ""; b = "" }
    END          { if (p != "" && b != "") print p "\t" b }'
}

# worktree_registered <path> <branch>: the absolute path of the worktree this repository has
# registered on <branch>, or empty when it has none.
worktree_registered() {
  worktree_entries "$1" | awk -F '\t' -v b="refs/heads/$2" '$2 == b { print $1; exit }'
}

# worktree_managed <path> <milestone>: where a worktree this project does not have yet is created —
# $BATON_HOME/worktrees/<project key>/<milestone>, the managed root. The project key is the
# basename of the canonical checkout, as it is everywhere else in Baton.
worktree_managed() {
  printf '%s' "$BATON_HOME/worktrees/$(basename "$1")/$2"
}

# worktree_of <path> <milestone>: the names a milestone's worktree carries — the path git has
# registered for the branch <milestone lowercased>, or the managed root when the project has no
# worktree on that branch yet — without touching either. Printed as {"worktree","branch"}.
# `worktree_ensure` creates from these and `dispatch_preconditions` inspects them, so the naming is
# written once and the two cannot drift apart.
#
# The registration is asked rather than a sibling path derived, because the two answers part company
# the moment a worktree is moved: the derived path finds no directory, `worktree add` is taken
# instead, and git refuses the branch it is already holding elsewhere — `fatal: '<branch>' is
# already used by worktree at '<new path>'`, exit 128, measured on git 2.54 — which reaches
# `dispatch_failed … worktree` and parks the lane on the second try. Resolution is therefore not a
# convenience beside the managed root but the thing that makes moving one safe at all (D-153).
worktree_of() {
  wo_branch=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
  wo_wt=$(worktree_registered "$1" "$wo_branch")
  [ -n "$wo_wt" ] || wo_wt=$(worktree_managed "$1" "$2")
  jq -nc --arg w "$wo_wt" --arg b "$wo_branch" '{worktree: $w, branch: $b}'
}

# worktree_ensure <path> <milestone>: the milestone's worktree on branch <milestone lowercased>,
# created from main under the managed root when the project has none, reused where git has it
# recorded — wherever that is — with the commit it stands at. Prints
# {"worktree","branch","reused","commit"}.
#
# Reuse is verified rather than assumed. A path git handed back is this repository's worktree on
# this branch by construction; the managed path is not, because a directory can be sitting there
# that Baton did not put there. Both identities are therefore asked of the directory itself, and a
# question that cannot be answered refuses: dispatching a session into another repository, or onto
# another branch, would have it merge work into a place nobody is looking.
worktree_ensure() {
  we_path=$1; we_id=$2
  we_names=$(worktree_of "$we_path" "$we_id")
  we_wt=$(printf '%s' "$we_names" | jq -r .worktree)
  we_branch=$(printf '%s' "$we_names" | jq -r .branch)
  if [ -d "$we_wt" ]; then
    we_reused=true
    we_commit=$(git -C "$we_wt" rev-parse HEAD 2>&1) || { echo "$we_wt exists but is not a worktree: $we_commit"; return 1; }
    # Both answers are resolved before they are compared. `--path-format=absolute` makes a path
    # absolute; it does not make it canonical, so a project registered through a symlinked path
    # would be told its own worktree belongs to somebody else. Measured on this Mac the two already
    # agree, which is exactly why the resolution is written now rather than after it has bitten.
    we_theirs=$(git -C "$we_wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || we_theirs=
    [ -z "$we_theirs" ] || we_theirs=$(cd "$we_theirs" 2>/dev/null && pwd -P) || we_theirs=
    we_ours=$(git -C "$we_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || we_ours=
    [ -z "$we_ours" ] || we_ours=$(cd "$we_ours" 2>/dev/null && pwd -P) || we_ours=
    if [ -z "$we_ours" ] || [ -z "$we_theirs" ] || [ "$we_ours" != "$we_theirs" ]; then
      echo "$we_wt is not a worktree of $we_path: its repository is ${we_theirs:-unreadable} and the checkout's is ${we_ours:-unreadable}. Baton reuses only the project's own worktree, so move that directory aside yourself: mv $(shell_word "$we_wt") $(shell_word "$we_wt.aside")"
      return 1
    fi
    we_on=$(git -C "$we_wt" symbolic-ref --quiet HEAD 2>/dev/null) || we_on=
    if [ "$we_on" != "refs/heads/$we_branch" ]; then
      echo "$we_wt is on ${we_on:-a detached HEAD} and $we_id's branch is refs/heads/$we_branch. Baton reuses a worktree only on the milestone's own branch, so check it out there yourself: git -C $(shell_word "$we_wt") checkout $(shell_word "$we_branch")"
      return 1
    fi
  else
    we_reused=false
    mkdir -p "$(dirname "$we_wt")"
    # core.hooksPath is emptied because `worktree add` runs the repository's post-checkout hook, and
    # from M03 this call is made by a launchd job whose shell has Full Disk Access. A dispatched
    # session runs under bypassPermissions inside that checkout and the deny list does not cover a
    # target's own .git, so a hook written there would be code the tick then executes — which is
    # exactly what INV-12 says never happens (D-048).
    if git -C "$we_path" show-ref --verify --quiet "refs/heads/$we_branch"; then
      we_out=$(git -C "$we_path" -c core.hooksPath=/dev/null worktree add "$we_wt" "$we_branch" 2>&1) \
        || { echo "$we_out"; return 1; }
    else
      we_out=$(git -C "$we_path" -c core.hooksPath=/dev/null worktree add "$we_wt" -b "$we_branch" main 2>&1) \
        || { echo "$we_out"; return 1; }
    fi
    we_commit=$(git -C "$we_wt" rev-parse HEAD)
  fi
  jq -nc --arg w "$we_wt" --arg b "$we_branch" --argjson r "$we_reused" --arg c "$we_commit" \
    '{worktree: $w, branch: $b, reused: $r, commit: $c}'
}

# worktree_legacy_id <checkout> <path>: the milestone named by a legacy sibling worktree path —
# <dirname checkout>/<basename checkout>-<milestone>, the convention every worktree carried before
# the managed root — or empty when the path is not one of those.
worktree_legacy_id() {
  wl_prefix=$(dirname "$1")/$(basename "$1")-
  case "$2" in
    # A path with a further component below the sibling is not one of these, whatever its head
    # spells: `<checkout>-x/y` would name the milestone `x/y`, whose managed parent nothing creates,
    # and the move would then fail with git's own ENOENT once a minute. Outside the convention is
    # passed over silently, which is what this function says of every other path.
    "$wl_prefix"*/*) ;;
    "$wl_prefix"?*) printf '%s' "${2#"$wl_prefix"}" ;;
    *) ;;
  esac
}

# worktree_migrate <project> <rows json>: move this project's legacy sibling worktrees into the
# managed root. Nothing is deleted, reset or recreated: `git worktree move` rewrites git's two
# administrative files and leaves branches, commits, uncommitted changes and ignored build products
# exactly as they were (D-137). A worktree already under the managed root, one whose path is not
# the legacy convention, and one whose branch is not the milestone's own are all passed over, so the
# pass is idempotent and touches nothing it did not itself name.
#
# **One guard, not D-075's three — and the guard is "a session Baton may still resume".** D-075
# guarded a *delete* with `Status` reads `done` and a verified `merged_as` with no newer ending,
# because a delete is irreversible and a question it could not answer had to fail safe. A move loses
# no bytes, so neither of those is restored here, and both are named so that a later reader does not
# restore them by analogy: they read the *plan*, and the plan is not what is at risk.
#
# What is at risk is one thing only. The harness resolves a session by its id and restores the
# working directory it recorded, so moving the ground under a session it can still be asked to
# resume strands it — `bg settled … (crashed): working directory no longer exists`. A live row is
# therefore not the whole of that set, which is the correction D-155 records: Baton resumes sessions
# **by id whose rows carry no pid** — the crash ladder after two sightings, `baton answer` into a
# lane whose `asking` consume stopped the session, `baton allow --resume`, and a wait retry. A
# reboot makes every row `pid`-less at once. So the guard is asked twice, and refuses if either says
# yes: any row whose `cwd` is the worktree or under it, live or not; and any **open lane** for that
# milestone in the log — a dispatch with no later `complete` consumption, which is exactly the set
# `status` shows and exactly the set something may still resume. A guard that cannot be answered —
# rows that will not parse, a log that will not read — refuses like a guard that answered yes.
#
# A refusal says nothing, because a guarded worktree is one `status` already shows, and a line per
# guarded worktree per sixty seconds would bury the moves that did happen. A move says so once.
#
# **No refusal fails the pass, and that is deliberate.** A destination already occupied and a move
# git will not make — a locked worktree, a cross-volume rename — are facts about one directory that
# stand until a person acts, not a tick that did not complete. The pass's status decides the tick's
# marker, and a marker withheld every minute would have `status` report the relay as down while it
# runs. Only a failure that is the tick's own — a checkout whose registration will not read —
# returns non-zero (D-155).
worktree_migrate() {
  wm_project=$1; wm_rows=$2
  wm_status=0
  wm_path=$(project_path "$wm_project") || {
    render_failure err "baton: $wm_project's checkout could not be read; no worktree was migrated: $wm_path"
    return 1
  }
  # Resolved, as `worktree_ensure` resolves the two repository paths it compares: git prints the
  # registration canonicalised, so a checkout registered through a symlink would match no sibling at
  # all and the pass would do nothing while saying nothing.
  wm_path=$(cd "$wm_path" 2>/dev/null && pwd -P) || wm_path=$(project_path "$wm_project")
  # The open lanes, once per project rather than once per worktree. A log that will not read leaves
  # this empty and every move is refused below, which is the guard failing closed.
  wm_lanes=''
  wm_log=$(log_json 2>/dev/null) && wm_lanes=$(lanes_open "$wm_project" "$wm_log" 2>/dev/null) || wm_lanes=''
  wm_root=$(dirname "$(worktree_managed "$wm_path" x)")
  # A repository git cannot read here answers with no entries and this pass does nothing, which is
  # right rather than lax: step 1's self-check has already parked a project whose git check failed,
  # so a project reaching this point has been asked that question and answered it.
  wm_entries=$(worktree_entries "$wm_path")
  while IFS='	' read -r wm_wt wm_ref; do
    [ -n "$wm_wt" ] || continue
    wm_id=$(worktree_legacy_id "$wm_path" "$wm_wt")
    [ -n "$wm_id" ] || continue
    # The milestone comes from the directory's own name and is then checked against the branch git
    # has it on, rather than being read back out of the branch: `m07-b` uppercased is `M07-B`, which
    # is not the milestone `M07-b` and would name a worktree nothing else in Baton can find.
    [ "$wm_ref" = "refs/heads/$(printf '%s' "$wm_id" | tr 'A-Z' 'a-z')" ] || continue
    wm_to=$(worktree_managed "$wm_path" "$wm_id")
    [ "$wm_wt" != "$wm_to" ] || continue
    # Something already at the destination is a state rather than an error: the worktree keeps
    # working where it is, nothing is at risk, and Baton never writes over a directory it did not
    # put there. The check is load-bearing rather than belt-and-braces — `git worktree move` onto an
    # existing *directory* moves the worktree *inside* it rather than refusing — and the likeliest
    # cause is not a stray directory but this worktree itself, moved by hand or by a rename that
    # landed before git rewrote its two administrative files, leaving the registration on the old
    # path. So the repair named is the one that fixes that: `worktree repair` rewrites both files
    # from whichever side is right.
    [ ! -e "$wm_to" ] || {
      render_failure err \
        "baton: $wm_project/$wm_id's worktree stays at $wm_wt, because $wm_to already exists and Baton never writes over a directory it did not put there. If that is this worktree, moved by hand, register it where it now stands; otherwise move it aside." \
        "git -C $(shell_word "$wm_path") worktree repair $(shell_word "$wm_to")"
      continue
    }
    # Any row in this worktree, live or not, and any open lane for the milestone. Both readings must
    # be a number; neither being answerable refuses the move.
    wm_rowsin=$(printf '%s' "$wm_rows" | jq -r --arg w "$wm_wt" '
      [ .[] | (.cwd // "") | select(. == $w or startswith($w + "/")) ] | length' 2>/dev/null) || wm_rowsin=
    case "$wm_rowsin" in ''|*[!0-9]*) continue ;; esac
    [ "$wm_rowsin" -eq 0 ] || continue
    wm_open=$(printf '%s' "$wm_lanes" | jq -r --arg m "$wm_id" \
      '[ .[] | select(.milestone == $m) ] | length' 2>/dev/null) || wm_open=
    case "$wm_open" in ''|*[!0-9]*) continue ;; esac
    [ "$wm_open" -eq 0 ] || continue
    mkdir -p "$wm_root"
    if wm_out=$(git -C "$wm_path" worktree move "$wm_wt" "$wm_to" 2>&1); then
      log_event worktree_moved "$wm_project" "$wm_id" "" "" \
        "$(jq -nc --arg f "$wm_wt" --arg t "$wm_to" --arg b "${wm_ref#refs/heads/}" \
           '{from: $f, to: $t, branch: $b}')"
      render_row out record 'worktree    %s · moved to %s\n' \
        "$(render_token out lane "$wm_project/$wm_id")" "$(render_token out path "$wm_to")"
    else
      render_failure err "baton: $wm_project/$wm_id's worktree stays at $wm_wt: git would not move it to $wm_to: $(printf '%s' "$wm_out" | head -1)"
    fi
  done <<MIGRATE
$wm_entries
MIGRATE
  return "$wm_status"
}

# shell_word <string>: the string as exactly one shell word, single-quoted, with any quote of its
# own closed, escaped and reopened. What the composed hook commands are built out of, so that a path
# or a value holding a space, a quote or anything else the shell reads is still one word when the
# CLI runs the command (D-133).
shell_word() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# settings_compose <project> <milestone>: the dispatched settings file at
# settings/<project>-<milestone>.json from the project's permissions.json: the mode as
# documentation, allow and deny copied, no ask rules, `remoteControlAtStartup: true`, the three
# hooks carrying Baton's home, the project key and the milestone on their command lines and
# pointing at the installed relay. A permissions.json without deny rules fails the stage: a
# bypassPermissions session without the rail is not dispatched. Prints the path.
#
# **Remote Control is on for every session** (REQ-ESC-08, D-081). It is what lists a session in
# Claude.app and on the phone and lets a person type into it there; a session started with the key
# false was measured absent from Claude.app altogether. The key is written rather than left to the
# account's default, which is what connected every dispatched session from M02 on, so that a change
# to that default cannot take Baton's sessions out of reach; a flagless resume restores the path.
settings_compose() {
  sc_perm=$BATON_HOME/projects/$1/permissions.json
  sc_out=$BATON_HOME/settings/$1-$2.json
  [ -f "$sc_perm" ] || { echo "$sc_perm is missing"; return 1; }
  # Every token of the composed command is quoted, the executable path as much as the assignment
  # values. The CLI runs this string through a shell, so a `BATON_HOME` holding a space used to give
  # a command whose first word was a truncated path and whose remainder was a stray argument — the
  # hook simply did not run, and nothing said so (D-133). The quoting is done here rather than inside
  # the jq program because this is where a shell word is a natural thing to build.
  sc_env="BATON_HOME=$(shell_word "$BATON_HOME") BATON_PROJECT=$(shell_word "$1") BATON_MILESTONE=$(shell_word "$2")"
  sc_json=$(jq -e \
    --arg statusline "$sc_env $(shell_word "$BATON_HOME/bin/statusline")" \
    --arg stop       "$sc_env $(shell_word "$BATON_HOME/bin/stop-gate")" \
    --arg failure    "$sc_env $(shell_word "$BATON_HOME/bin/stop-failure")" '
    if ((.permissions.deny // []) | length) == 0
      then error("permissions.deny is empty; a bypassPermissions session needs the two deny classes") else . end
    | { permissions: { defaultMode: "bypassPermissions",
                       allow: (.permissions.allow // []),
                       deny: .permissions.deny },
        remoteControlAtStartup: true,
        statusLine: { type: "command", command: $statusline },
        hooks: {
          Stop:        [{ hooks: [{ type: "command", command: $stop }] }],
          StopFailure: [{ hooks: [{ type: "command", command: $failure }] }] } }' \
    "$sc_perm" 2>&1) || { echo "$sc_perm: $sc_json"; return 1; }
  mkdir -p "$BATON_HOME/settings"
  printf '%s\n' "$sc_json" > "$sc_out.tmp"
  mv "$sc_out.tmp" "$sc_out"
  printf '%s\n' "$sc_out"
}

# prompt_from_brief <path> <brief> <heading>: the first fenced block under the line
# "## <heading>" in the brief as it is on main — git show, never the working tree, so a person
# mid-edit cannot change what a session receives. The search ends at the next "## " heading.
# Prints the block's body.
prompt_from_brief() {
  pb_id=${2##*/}; pb_id=${pb_id%.md}
  pb_needed="Baton needs $pb_id's brief $2 on main with a fenced block under \"## $3\"."
  pb_commit="git -C \"$1\" add -- \"$2\" && git -C \"$1\" commit -m \"Record $pb_id brief\""
  pb_text=$(git -C "$1" show "main:$2" 2>&1) || {
    if [ -f "$1/$2" ]; then
      printf '%s\n' "$pb_needed It is written on disk but not committed to main. A dispatch reads briefs from main and creates its worktree from main, so the session would not have the file. On main, run: $pb_commit"
    else
      printf '%s\n' "$pb_needed It does not exist on main or in the working tree. Write the brief with that heading and fenced block, then commit it on main: $pb_commit"
    fi
    return 1
  }
  pb_body=$(printf '%s\n' "$pb_text" | HEADING="## $3" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    !found && trim($0) == ENVIRON["HEADING"] { found = 1; next }
    found && !infence && /^## / { exit }
    found && !infence && /^```/ { infence = 1; next }
    found && infence && /^```/ { closed = 1; exit }
    found && infence { print }
    END { exit (closed ? 0 : 1) }') || {
      printf '%s\n' "$pb_needed The brief is on main, but no complete fenced block follows that heading. Add the heading and fenced block, then commit it on main: $pb_commit"
      return 1
    }
  printf '%s' "$pb_body"
}

# brief_size <checkout> <milestone>: the Size a milestone's brief declares in its `## 1.` section,
# lowercased, or empty when it declares none. Read with `git show main:`, as the kickoff prompt is,
# so a person mid-edit cannot change the effort a session is dispatched at any more than they can
# change the prompt it receives.
#
# §1 and not the whole document, for the reason M12's generation check gives when it refuses a brief
# that declares no Size there: the kickoff prompt states the Size too, and a brief whose only Size is
# inside the fenced block has told the session and not the plan. §1 is where a person and a dispatch
# both look for it.
#
# A brief that cannot be read here yields no Size rather than a failure. `dispatch_preconditions` has
# already established that it is on `main` with a complete fenced block, and `prompt_from_brief` reads
# it again a moment later with three messages of its own; a second failure path for the same cause
# would report the effort as the problem when the brief is.
#
# The line has to *declare* the Size and not merely mention it: what precedes `Size:` may be list
# markers, emphasis and whitespace and nothing else — one character class, with no `{n,m}` interval,
# which the awk here does support but which would add nothing the class does not already allow.
# M12's generation check asks the looser question — is there a line in §1 holding `Size:` at all —
# and that is right for a check whose answer is yes or no, where a false match costs a defect
# reported that a person then reads. This one reads a value off the line and dispatches on it, so it
# owes the stricter question. Without the anchor, a §1 sentence
# such as "- **Objective:** settle the Size: Large, then build." is the first match, `found` is set,
# and the real `- **Size:** Small` line two lines down is never reached: the milestone dispatches at
# `high` on a word from a clause about deciding something. Anchoring it costs one pattern and is the
# difference between reading a declaration and grepping prose.
brief_size() {
  bs_text=$(git -C "$1" show "main:docs/milestones/$2.md" 2>/dev/null) || return 0
  printf '%s\n' "$bs_text" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^## / { inside = (trim($0) ~ /^## 1\./); next }
    inside && !found && /^[-*+ \t]*Size:/ {
      s = $0; sub(/^.*Size:/, "", s); gsub(/\*/, "", s)
      sub(/[,;.].*$/, "", s); s = trim(s)
      if (s != "") { print tolower(s); found = 1 }
    }'
}

# size_effort <size>: the reasoning effort a declared Size asks for, or empty for a Size Baton does
# not recognise. The mapping, settled once here so that later pacing consumes this seam rather than
# inventing a second one (M13 §10, D-174):
#
#     small → medium      medium → high      large → high
#
# It is read off this repository's own briefs rather than chosen. Every brief whose §1 line declares
# both a Size and an effort agrees with it: M09, M10 and M10-b are Small at medium effort; M11, M12
# and M17-b are Large at high; M13, M15, M15-b, M15-c and M17 are Medium at high. The one brief that
# reads otherwise — M14, Medium at medium effort — carries `medium` in its plan row's Effort cell,
# which wins, so the column and the mapping together reproduce every effort the plan states and
# neither has to guess. Medium and Large share `high` because nothing in the record asks for more:
# `xhigh` for Large would spend a setting no brief here has ever called for.
#
# Anything else is empty — no Size line, a Size that is not one of the three, M16's "Live trial" —
# which is the effort every dispatch has carried for a blank Effort cell all along: `claude_bg`
# leaves the flag off and the CLI's own default stands. Baton does not guess an effort out of prose
# it cannot read. And a Size is not a plan cell, so an unreadable one never parks the project the
# way `parse_effort` refusing a cell does: it is a description the brief owes its reader, which M12's
# generation check already asks for by name.
size_effort() {
  case "$1" in
    small) printf '%s\n' medium ;;
    medium|large) printf '%s\n' high ;;
    *) : ;;
  esac
}

# slot_line <prompt> <paragraph>: replaces the one paragraph beginning WHAT ELSE IS IN FLIGHT.
# with <paragraph> and prints the result; fails if the prompt has no such paragraph.
slot_line() {
  sl_out=$(printf '%s\n' "$1" | REP="$2" awk '
    /^WHAT ELSE IS IN FLIGHT\./ { print ENVIRON["REP"]; skipping = 1; replaced = 1; next }
    skipping && !/^[ \t]*$/ { next }
    skipping { skipping = 0 }
    { print }
    END { exit (replaced ? 0 : 1) }') || { echo "the prompt has no paragraph beginning WHAT ELSE IS IN FLIGHT."; return 1; }
  printf '%s' "$sl_out"
}

# cli_plain: stdin to stdout with the CLI's colour escapes removed. Everything Baton reads from the
# CLI's own output goes through it first.
#
# Measured while running live item 44 (D-050): with FORCE_COLOR set in the environment — which every
# process started from inside a Claude Code session inherits — `claude --bg` prints
# `backgrounded · <ESC>[36m82b69058<ESC>[39m · …` even with stdout redirected to a file, so the id
# does not match the hexadecimal test and a dispatch that had really started a session was recorded
# as a launch failure. The lane then never opened and the next tick dispatched a second session for
# the same milestone. The launchd job sets only LC_ALL and so never saw it; a hand-run
# `baton dispatch` from inside a session saw it every time.
cli_plain() { sed "s/$(printf '\033')\[[0-9;]*[a-zA-Z]//g"; }

# resume_classify <stdout> <stderr> <exit status>: what a flagless `claude --bg --resume` printed, as
# {outcome, note, copy}, both streams already through cli_plain. The one classifier every resume uses —
# a ruling, a continuation, a wake — so a note variant learned once is learned everywhere (D-058).
#
# The fork test comes first and matches the family: a note saying the CLI `started a copy` is a fork,
# and the copy is the 8-hex job id after the last ` as `. Then the success line, `woke session `. Else
# refused, with stderr's first line as the reason, because stdout carries a `backgrounded` line
# whichever way the resume went. The note is cut to 500 bytes: it is copied onto an event, and a line
# `log_event` refused after the resume had landed would lose the record of a resume that happened.
resume_classify() {
  rcl_both=$(printf '%s\n%s\n' "$1" "$2")
  rcl_copy=''
  rcl_note=$(printf '%s\n' "$rcl_both" | grep -F 'started a copy' | head -1 || true)
  if [ -n "$rcl_note" ]; then
    rcl_outcome=forked
    rcl_copy=$(printf '%s\n' "$rcl_note" | sed -n 's/.* as \([0-9a-f]\{8,\}\).*/\1/p' | head -1)
  elif printf '%s\n' "$rcl_both" | grep -Fq 'woke session '; then
    rcl_outcome=delivered
    rcl_note=$(printf '%s\n' "$rcl_both" | grep -F 'woke session ' | head -1)
  else
    rcl_outcome=refused
    rcl_note=$(printf '%s\n' "$2" | grep -v '^[[:space:]]*$' | head -1 || true)
    [ -n "$rcl_note" ] || rcl_note=$(printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | grep -v '^backgrounded ' | head -1 || true)
    [ -n "$rcl_note" ] || rcl_note="the resume printed nothing and exited $3"
  fi
  rcl_note=$(printf '%s' "$rcl_note" | head -c 500)
  jq -nc --arg o "$rcl_outcome" --arg n "$rcl_note" --arg c "$rcl_copy" \
    '{outcome: $o, note: $n} | if $c != "" then . + {copy: $c} else . end'
}

# claude_env_clean: removes from this process every CLAUDE* variable but CLAUDE_CONFIG_DIR. `bin/baton`
# calls it once, before any verb, so no `claude` Baton starts or resumes inherits them.
#
# A process started from inside a Claude Code session inherits that session's variables — its session
# id, its Remote Control bridge session id, its entrypoint — and the wake session runs `baton wake`
# from inside itself by design, as a person may run any verb by hand. Measured live (D-087): a `--bg`
# session started from a shell carrying them recorded "Remote Control disconnected — Session creation
# failed", while the same start under launchd's clean environment connected and recorded its claude.ai
# URL; a session that cannot reach Claude.app answers into a thread nobody can read. CLAUDE_CONFIG_DIR
# stays, because it names which Claude Code the person runs rather than which session this is. An
# authentication variable of that family is removed with the rest, which is accepted on this Mac, where
# login lives in the keychain.
claude_env_clean() {
  for cec_v in $(env | sed -n 's/^\(CLAUDE[A-Z0-9_]*\)=.*/\1/p'); do
    [ "$cec_v" = CLAUDE_CONFIG_DIR ] || unset "$cec_v"
  done
}

# claude_bg <worktree> <name> <model> <effort> <settings> <prompt>: the one command, with the
# worktree as cwd and LC_ALL set. Sets bg_status, bg_stdout, bg_stderr and bg_id (empty when no
# "backgrounded · <id>" line was printed, which is the failure test).
claude_bg() {
  cb_tmp=$(mktemp "${TMPDIR:-/tmp}/baton-bg.XXXXXX")
  set +e
  ( cd "$1" && LC_ALL=en_US.UTF-8 "$BATON_CLAUDE" --bg -n "$2" --model "$3" ${4:+--effort "$4"} \
      --permission-mode bypassPermissions --settings "$5" "$6" ) > "$cb_tmp" 2> "$cb_tmp.err"
  bg_status=$?
  set -e
  bg_stdout=$(cli_plain < "$cb_tmp"); bg_stderr=$(cli_plain < "$cb_tmp.err")
  rm -f "$cb_tmp" "$cb_tmp.err"
  bg_id=$(printf '%s\n' "$bg_stdout" | LC_ALL=en_US.UTF-8 awk '$1 == "backgrounded" && $3 ~ /^[0-9a-f]+$/ { print $3; exit }')
}

# dispatch_failed_classify <text>: the stage of a dispatch that produced no session, from the
# four strings known from the binary; launch by default. The specific strings are matched before
# the service line because the binary prints "Starting background service…" on the way to them.
dispatch_failed_classify() {
  case "$1" in
    *"Error: Settings file not found:"*) echo settings ;;
    *"requires accepting the disclaimer first"*) echo launch ;;
    *"cannot be combined with --print"*) echo launch ;;
    *"Starting background service"*) echo service ;;
    *) echo launch ;;
  esac
}

# caffeinate_hold <pid>: caffeinate -i -w <pid>, detached, so the Mac stays awake while the
# session's process lives.
caffeinate_hold() {
  "$BATON_CAFFEINATE" -i -w "$1" < /dev/null > /dev/null 2>&1 &
}

# dispatch_failed <project> <milestone> <stage> <detail>: the event and the message. The detail
# is the one field an outside process sizes (a whole stderr), so it is cut to 2000 bytes and
# marked, keeping the line under log_event's 4 KB refusal.
dispatch_failed() {
  df_detail=$4
  df_truncated=false
  if [ "$(printf '%s' "$df_detail" | wc -c | tr -d ' ')" -gt 2000 ]; then
    df_detail=$(printf '%s' "$df_detail" | head -c 2000)
    df_truncated=true
  fi
  log_event dispatch_failed "$1" "$2" "" "" "$(jq -nc --arg s "$3" --arg d "$df_detail" --argjson t "$df_truncated" \
    '{stage: $s, detail: $d} | if $t then . + {detail_truncated: true} else . end')"
  render_failure err "baton: dispatch of $1 $2 failed at $3: $df_detail"
}

# dispatch_stop_jobs <job>...: stop the admitted cleanup's jobs, then settle all successful
# stops together in one loop. A matching row must not buy another thirty seconds of polling.
# Calls themselves have no timeout; this bounds polling, not wall-clock duration (D-114).
dispatch_stop_jobs() {
  dsj_pending='[]'; dsj_status=0
  for dsj_job do
    if dsj_out=$("$BATON_CLAUDE" stop "$dsj_job" 2>&1); then
      dsj_pending=$(printf '%s' "$dsj_pending" | jq -c --arg id "$dsj_job" '. + [$id]')
    else
      printf 'cleanup: stop %s failed: %s\n' "$dsj_job" "$dsj_out"
      dsj_status=1
    fi
  done
  [ "$dsj_pending" != '[]' ] || return "$dsj_status"
  dsj_i=0
  while [ "$dsj_i" -lt 60 ]; do
    if dsj_rows=$(rows_read) && printf '%s' "$dsj_rows" | jq -e --argjson ids "$dsj_pending" \
        'all(.[]; .pid == null or (.id as $id | ($ids | index($id)) == null))' > /dev/null 2>&1; then
      return "$dsj_status"
    fi
    dsj_i=$((dsj_i + 1))
    sleep 0.5
  done
  printf 'cleanup truncated: stops for %s did not settle within the shared thirty-second polling budget\n' "$*"
  return 1
}

# dispatch_one <project> <milestone> <plan json> <rows json>: step 8 for one milestone, or for the
# planning lane, which is dispatched exactly as a milestone is and differs in three places only.
#
# The planning lane (`lib/planning.sh`) has no row in the plan — there is no plan, which is what it
# is for — so its model and effort come from config.json, its preconditions are the ground and the
# rail rather than a brief on `main`, and its prompt is Baton's own text rather than a brief's fenced
# block. Everything after that is the same code: the same worktree, the same settings file, the same
# launch, the same cleanup budget, the same `dispatch` event and the same five lines. Writing it a
# second time would give the planning lane its own launch failure handling, and the cap's
# conservative count of a launch that could not be proved to have started nothing (D-130) is
# precisely the code that must not exist twice.
dispatch_one() {
  do_project=$1; do_id=$2; do_plan=$3; do_rows=$4
  do_path=$(project_path "$do_project")
  do_planning=false
  if [ "$do_id" = "$PLANNING_ID" ]; then
    do_planning=true
    # The "also in flight" list below reads this document, and the planning lane is dispatched for a
    # project whose plan is exactly what does not parse. An empty table is the truth about it.
    do_plan='{"milestones":[]}'
  fi

  # Before anything is created. Every defect `dispatch_preconditions` can see is knowable from the
  # plan, the checkout and Baton's own state, so seeing one after a branch, a worktree and a
  # settings file exist is a cost with nothing bought. The whole result is collected — `baton plan`
  # reports all of it — and the one event this failure writes carries the first defect in the
  # result's fixed order, which makes it deterministic rather than whichever check happened to run.
  # A result that could not be collected is not an absence of defects: it is refused in its own
  # right, because reading it as success is exactly the mistake this check exists to prevent.
  if [ "$do_planning" = true ]; then
    do_pre=$(planning_preconditions "$do_project")
  else
    do_pre=$(dispatch_preconditions "$do_project" "$do_id")
  fi || {
    dispatch_failed "$do_project" "$do_id" worktree "the dispatch preconditions for $do_id could not be read: $do_pre"
    return 1
  }
  if ! printf '%s' "$do_pre" | jq -e '(.failures | type) == "array"' > /dev/null 2>&1; then
    dispatch_failed "$do_project" "$do_id" worktree "the dispatch preconditions for $do_id returned no readable result; nothing was created"
    return 1
  fi
  if [ "$(printf '%s' "$do_pre" | jq -r '.failures | length')" -gt 0 ]; then
    dispatch_failed "$do_project" "$do_id" \
      "$(printf '%s' "$do_pre" | jq -r '.failures[0].stage')" \
      "$(printf '%s' "$do_pre" | jq -r '.failures[0].detail')"
    return 1
  fi

  if [ "$do_planning" = true ]; then
    # config.json's, because there is no row to read them from. Never `Remote: yes`: a planning
    # session is not one whose questions a person answers from the phone — it is told not to ask.
    do_model=$(planning_model)
    do_effort=$(planning_effort)
    do_remote=false
  else
    do_row=$(printf '%s' "$do_plan" | plan_row "$do_id")
    do_model=$(printf '%s' "$do_row" | jq -r .model)
    do_effort=$(printf '%s' "$do_row" | jq -r .effort)
    # The brief's declared Size, and only where the plan's Effort cell is blank. The cell wins
    # because the two are not the same kind of statement: a cell is an instruction a person wrote
    # into the plan about how this milestone is to be dispatched, and a Size is the brief describing
    # how big the work is. An instruction outranks a description, and the alternative would make a
    # person's edit to the column do nothing on any milestone whose brief happened to declare a Size.
    #
    # It sits inside this branch rather than beside it because the branch is already the place where
    # an effort that does not come from a plan row is decided: the lane above takes model and effort
    # from config.json for the one milestone that has no row at all. A Size-derived effort is that
    # same decision made from a third source, and the `dispatch` event below records whichever of the
    # three actually ran.
    [ -n "$do_effort" ] || do_effort=$(size_effort "$(brief_size "$do_path" "$do_id")")
    do_remote=$(printf '%s' "$do_row" | jq -r .remote)
  fi
  do_attempt=$(attempt_of "$do_project" "$do_id") || { render_failure err "baton: $do_attempt"; return 1; }
  do_attempt=$((do_attempt + 1))
  do_name=$(session_name "$do_project" "$do_id")

  do_wt=$(worktree_ensure "$do_path" "$do_id") || { dispatch_failed "$do_project" "$do_id" worktree "$do_wt"; return 1; }
  do_wt_path=$(printf '%s' "$do_wt" | jq -r .worktree)
  do_branch=$(printf '%s' "$do_wt" | jq -r .branch)
  do_reused=$(printf '%s' "$do_wt" | jq -r .reused)
  do_commit=$(printf '%s' "$do_wt" | jq -r .commit)

  do_settings=$(settings_compose "$do_project" "$do_id") || { dispatch_failed "$do_project" "$do_id" settings "$do_settings"; return 1; }

  if [ "$do_planning" = true ]; then
    # Baton's own text, composed from the registration the confirmation wrote and the defects the
    # last attempt left. There is no brief to read and none to be readable in the worktree, so the
    # two checks below are the milestone lane's alone.
    do_reg=$(jq -c . "$BATON_HOME/projects/$do_project/project.json" 2>/dev/null) \
      || { dispatch_failed "$do_project" "$do_id" prompt "$BATON_HOME/projects/$do_project/project.json does not parse, so the planning prompt cannot be composed"; return 1; }
    do_owed=$(planning_owed "$do_project") || do_owed='{}'
    do_prompt=$(planning_prompt "$do_project" "$do_path" "$do_reg" \
      "$(printf '%s' "$do_owed" | jq -c '.defects // []')" "$do_attempt") \
      || { dispatch_failed "$do_project" "$do_id" prompt "the planning prompt could not be composed"; return 1; }
  else
    do_brief=docs/milestones/$do_id.md
    do_prompt=$(prompt_from_brief "$do_path" "$do_brief" "Copy-ready session prompt") || { dispatch_failed "$do_project" "$do_id" prompt "$do_prompt"; return 1; }
    # The same readability the preconditions already inspected, asked again of the worktree that now
    # exists. It is kept as the final race check: the preconditions read a worktree that may not have
    # existed yet, and between that reading and this one `worktree_ensure` created or reused one. Its
    # removal would need proof that no such window exists, not the observation that it usually agrees.
    #
    # Its message no longer names a branch behind the brief's commit as the cause. That cause is what
    # the `behind-brief` precondition now refuses before this point, so a dispatch reaching here has
    # already been told the branch carries the commit: what is left is the file going between the two
    # readings, and a message naming a cause already ruled out would send a person the wrong way.
    if [ ! -r "$do_wt_path/$do_brief" ]; then
      dispatch_failed "$do_project" "$do_id" worktree "Baton needs $do_id's brief $do_brief readable in its own worktree. The preconditions found the branch carrying the brief's commit, and the file was not readable in $do_wt_path a moment later. Look at the worktree yourself, then dispatch again: git -C \"$do_wt_path\" status"
      return 1
    fi
  fi
  do_inflight=$(derive_in_flight "$do_project" "$do_rows") || { render_failure err "baton: $do_inflight"; return 1; }
  do_inflight=$(printf '%s' "$do_inflight" | jq -c .in_flight)
  # The peer's whole worktree path, not its basename. The basename was the name under the legacy
  # sibling convention — `../Fixture-M02`, where it said which project and which milestone — and M09
  # moved new worktrees to `<managed root>/<project>/<milestone>`, where it says only "M02" beside a
  # milestone already called M02. What this sentence is for is telling a session where another
  # session is working so it stays out of it, and a path is that; a name that repeats the id is not (D-176).
  do_also=$(printf '%s' "$do_inflight" | jq -r --arg me "$do_id" --argjson plan "$do_plan" '
    ($plan.milestones | map(select(.status == "done") | .id)) as $done
    | map(select(.milestone as $m | $m != $me and (($done | index($m)) == null)))
    | map("\(.milestone) (worktree \(.worktree), brief docs/milestones/\(.milestone).md)")
    | join(", ")')
  do_slot=$(slot_line_text "$do_wt_path" "$do_branch" "$do_path" "$do_also" "$do_attempt" "$do_commit")
  do_body=$(slot_line "$do_prompt" "$do_slot") || { dispatch_failed "$do_project" "$do_id" prompt "$do_body"; return 1; }

  claude_bg "$do_wt_path" "$do_name" "$do_model" "$do_effort" "$do_settings" "$do_body"
  if [ -z "$bg_id" ]; then
    do_detail=$bg_stderr
    [ -n "$do_detail" ] || do_detail="exit $bg_status with nothing on stderr; stdout: $bg_stdout"
    # The empty-stderr fallback already preserves stdout. Preserve it with stderr too (D-114).
    if [ -n "$bg_stderr" ] && [ -n "$bg_stdout" ]; then
      do_detail="stdout: $bg_stdout; stderr: $bg_stderr"
    fi
    if [ "$do_cleanup_spent" = true ]; then
      do_detail="cleanup skipped; budget spent this tick; $do_detail"
      do_unresolved=$((do_unresolved + 1))
      dispatch_failed "$do_project" "$do_id" "$(dispatch_failed_classify "$bg_stderr")" "$do_detail"
      return 1
    fi
    do_cleanup_spent=true
    # A row can lag the launch acknowledgement. Poll a successful or nonempty launch for the
    # same bound as row_for_id; a failed launch with no stdout still gets one fresh inspection.
    do_cleanup_limit=1
    if [ "$bg_status" -eq 0 ] || [ -n "$bg_stdout" ]; then do_cleanup_limit=60; fi
    do_cleanup_ids=; do_cleanup_i=0; do_cleanup_read=false
    while [ "$do_cleanup_i" -lt "$do_cleanup_limit" ]; do
      if do_cleanup_rows=$(rows_read); then
        do_cleanup_read=true
        do_cleanup_ids=$(printf '%s' "$do_cleanup_rows" | jq -r --arg n "$do_name" \
          '.[] | select(.name == $n and .pid != null) | .id // empty')
        [ -z "$do_cleanup_ids" ] || break
      fi
      do_cleanup_i=$((do_cleanup_i + 1))
      [ "$do_cleanup_i" -ge "$do_cleanup_limit" ] || sleep 0.5
    done
    if [ -z "$do_cleanup_ids" ]; then
      # Nothing to stop, which is not the same as nothing to worry about. A listing that could not be
      # read says nothing either way, and a launch the CLI acknowledged — it exited zero, or printed
      # something — whose row never appeared is the case `row_for_id` already treats as needing a
      # stop. Both leave a worker possibly running under no id, so both are unresolved. A launch that
      # exited non-zero printing nothing at all, whose one fresh inspection found no row of the
      # lane's name, is the one reading that says the CLI never got as far as starting anything.
      if [ "$do_cleanup_read" = false ]; then
        do_detail="cleanup: could not read live rows for $do_name; $do_detail"
        do_unresolved=$((do_unresolved + 1))
      elif [ "$do_cleanup_limit" -gt 1 ]; then
        do_detail="cleanup: no live row identified for $do_name within thirty seconds; $do_detail"
        do_unresolved=$((do_unresolved + 1))
      fi
    fi
    if [ -n "$do_cleanup_ids" ]; then
      # The listing's job ids are hex tokens, so this split introduces no glob characters.
      if ! do_cleanup=$(dispatch_stop_jobs $do_cleanup_ids); then
        do_detail="$do_cleanup; $do_detail"
        do_unresolved=$((do_unresolved + 1))
      fi
    fi
    dispatch_failed "$do_project" "$do_id" "$(dispatch_failed_classify "$bg_stderr")" "$do_detail"
    return 1
  fi

  if ! do_agent=$(row_for_id "$bg_id"); then
    do_stage=$(dispatch_failed_classify "$do_agent")
    # The launch gave us this id: even a listing that timed out cannot make it unknowable.
    if [ "$do_cleanup_spent" = true ]; then
      do_agent="cleanup skipped; budget spent this tick; $do_agent"
      do_unresolved=$((do_unresolved + 1))
    else
      do_cleanup_spent=true
      if ! do_cleanup=$(dispatch_stop_jobs "$bg_id"); then
        do_agent="$do_cleanup; $do_agent"
        do_unresolved=$((do_unresolved + 1))
      fi
    fi
    dispatch_failed "$do_project" "$do_id" "$do_stage" "$do_agent"
    return 1
  fi
  do_session=$(printf '%s' "$do_agent" | jq -r .sessionId)
  do_pid=$(printf '%s' "$do_agent" | jq -r .pid)

  do_sidecar=$(sidecar_write "$do_session" "$do_body")
  do_prompt_path=${do_sidecar% *}
  do_prompt_sha=${do_sidecar##* }

  caffeinate_hold "$do_pid"

  log_event dispatch "$do_project" "$do_id" "$do_session" "$do_attempt" "$(jq -nc \
    --arg name "$do_name" --arg model "$do_model" --arg effort "$do_effort" \
    --arg wt "$do_wt_path" --arg branch "$do_branch" --argjson reused "$do_reused" --arg commit "$do_commit" \
    --arg settings "$do_settings" --arg pp "$do_prompt_path" --arg sha "$do_prompt_sha" --argjson remote "$do_remote" \
    --argjson planning "$do_planning" '
    {name: $name, model: $model}
    # The role, on the one lane that is not a milestone. It is absent from every other dispatch
    # rather than written as `milestone`, because a field an event has no value for is absent from
    # it (§6.1), and every dispatch before this one had no role to name.
    | if $planning then . + {role: "planning"} else . end
    | if $effort != "" then . + {effort: $effort} else . end
    | . + {remote: $remote, worktree: $wt, branch: $branch, worktree_reused: $reused}
    # The baseline, on every dispatch and not only on a reused worktree. It was `worktree_commit`
    # and said only where a reused worktree happened to stand; it is now the commit a completion
    # claim has to descend from, which is a fact about the attempt and has to be there for every
    # one of them. Nothing read the old name (D-145).
    | . + {baseline: $commit}
    | . + {settings: $settings, prompt_path: $pp, prompt_sha256: $sha}')"

  # The five lines a dispatch leaves behind, on stdout: a person's own `baton dispatch` reads them
  # at the terminal and the tick's go to launchd.out, where they are the record of what it started.
  render_row out record 'backgrounded · %s · %s\n' "$(render_token out session "$bg_id")" "$do_name"
  render_row out record 'session   %s (attempt %s)\n' \
    "$(render_token out session "$do_session")" "$do_attempt"
  if [ "$do_reused" = true ]; then
    render_row out record 'worktree  %s (branch %s, reused at %s)\n' \
      "$(render_token out path "$do_wt_path")" "$do_branch" "$(render_token out session "$do_commit")"
  else
    render_row out record 'worktree  %s (branch %s)\n' \
      "$(render_token out path "$do_wt_path")" "$do_branch"
  fi
  render_row out record 'settings  %s\n' "$(render_token out path "$do_settings")"
  render_row out record 'prompt    %s\n' "$(render_token out path "$do_prompt_path")"
}

# verb_dispatch <project> <milestone>: refuse unless the plan makes the milestone eligible;
# refuse if a live row already carries its name; then dispatch_one. Rows are read once here.
verb_dispatch() {
  vd_plan=$(plan_of_project "$1") || { vd_st=$?; render_failure err "$vd_plan"; exit $vd_st; }
  printf '%s' "$vd_plan" | plan_row "$2" > /dev/null 2>&1 || { render_failure err "baton: $2 is not in $1's plan"; exit 2; }
  vd_rows=$(rows_json)
  if ! printf '%s' "$vd_plan" | plan_eligible | grep -Fqx "$2"; then
    vd_inflight=$(derive_in_flight "$1" "$vd_rows") || { render_failure err "baton: $vd_inflight"; exit 1; }
    vd_inflight=$(printf '%s' "$vd_inflight" | jq -c .in_flight)
    render_failure err "baton: $2 is not eligible; the plan reads:"
    # The row is found by its first field, so `plan_render` is asked for the plain form here and
    # the row it hands back is rendered afterwards. Colour in that field would match nothing and
    # the refusal would name no row at all — the failure would be silent, which is the worst kind.
    vd_row=$(printf '%s' "$vd_plan" | plan_render "$1" "$vd_inflight" | awk -v id="$2" '$1 == id')
    [ -z "$vd_row" ] || render_row err plain '%s\n' "$vd_row"
    exit 2
  fi
  vd_name=$(session_name "$1" "$2")
  if printf '%s' "$vd_rows" | jq -e --arg n "$vd_name" 'any(.[]; .name == $n and .pid != null)' > /dev/null; then
    render_failure err "baton: a live session named \"$vd_name\" already exists; nothing dispatched"
    exit 2
  fi
  dispatch_one "$1" "$2" "$vd_plan" "$vd_rows"
}
