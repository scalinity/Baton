#!/bin/sh
# tests/completion-fixture.sh <shape> — the git shapes a completion chain is judged against.
#
# `merged_as` ancestry can be failed with one commit off `main`, which is why the harness makes
# `$offmain` and nothing more. A completion chain cannot: it needs a baseline B, a candidate branch
# tip T, an integration commit M and, for some shapes, a `main` that has moved on since. Those have
# to be built per scenario, and their ids are not knowable when the fixture's home/ is written.
#
# So this builds the shape and then substitutes: it writes "<NAME> <value>" lines to $tmp/subs and
# replaces @NAME@ in $BATON_HOME with the value. `tests/run.sh` puts the values back as @NAME@
# before the diff, so an expectation names BASELINE, CANDIDATE and MERGE rather than hashes that
# would move whenever tests/project/ changed.
#
# Every commit is made with plumbing and fixed dates and identity, so it is the same commit however
# often this runs. That matters because a scenario's cmd runs twice: the second run rebuilds the
# same shape, finds the same ids, and substitutes nothing, because the first run already did.
set -eu
shape=${1:?the shape to build}
repo=$PWD/Fixture
subs=$PWD/subs

export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example \
       GIT_AUTHOR_DATE=2026-09-02T00:00:00+0000 \
       GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example \
       GIT_COMMITTER_DATE=2026-09-02T00:00:00+0000

# The root commit, not `main`: a cmd runs twice, and the first run moves `main` to the shape's
# integration commit, so reading `main` here would make the second run build on the first run's
# output and report a different baseline for the same scenario.
root=$(git -C "$repo" rev-list --max-parents=0 main)

# cf_commit <message> <path> <content> <parent> [<second parent>]: one commit, built through the
# index rather than the working tree, so nothing has to be checked out and the result depends on
# its inputs alone. Prints the commit id.
cf_commit() {
  cf_msg=$1; cf_path=$2; cf_content=$3; cf_parent=$4; cf_parent2=${5:-}
  cf_blob=$(printf '%s\n' "$cf_content" | git -C "$repo" hash-object -w --stdin)
  GIT_INDEX_FILE=$repo/.git/cf-index; export GIT_INDEX_FILE
  rm -f "$GIT_INDEX_FILE"
  git -C "$repo" read-tree "$cf_parent"
  git -C "$repo" update-index --add --cacheinfo "100644,$cf_blob,$cf_path"
  cf_tree=$(git -C "$repo" write-tree)
  unset GIT_INDEX_FILE
  if [ -n "$cf_parent2" ]; then
    git -C "$repo" commit-tree "$cf_tree" -p "$cf_parent" -p "$cf_parent2" -m "$cf_msg"
  else
    git -C "$repo" commit-tree "$cf_tree" -p "$cf_parent" -m "$cf_msg"
  fi
}

# cf_merge <message> <tree-from> <first parent> <second parent>: the merge commit a close-out makes,
# carrying the candidate's tree, which is what a fast-forwardable merge of one branch produces.
cf_merge() {
  git -C "$repo" commit-tree "$(git -C "$repo" rev-parse "$2^{tree}")" -p "$3" -p "$4" -m "$1"
}

: > "$subs"
cf_say() { printf '%s %s\n' "$1" "$2" >> "$subs"; }

# Two commits on the root, and the baseline is the second of them: the milestone's declared scope,
# and the standing check Baton runs itself on the tree it is judging.
#
# They are built here rather than left in `tests/project/`, which every scenario shares. Five
# expectations elsewhere pin a commit id derived from that tree — `b4-ladder-end-legacy` and
# `ladder-end-edit` among them, through the slot line's "a previous attempt left work on this
# branch at <sha>" — so a line added to a brief there moves fixtures that have nothing to do with
# this milestone. Nothing outside the completion scenarios sees these two commits.
CF_SCOPE='# M02 — The second

## 5. Expected files (proposed)

`docs/milestones/M02.md`; `docs/{one,two}.md`; `src/*.txt`. Three spans that are not patterns sit
here on purpose: `git worktree move` holds spaces, `$BATON_HOME` is outside the repository, and
`proposed` names no path. README.md is named in prose and so is not declared.

## Completion evidence

## Copy-ready session prompt

```
You are implementing milestone M02 of Fixture. One line that never changes.
```'

CF_CHECK_PASSES='#!/bin/sh
# The fixture project’s standing check. It reports the revision it is standing at, so a recorded
# result can be read against the revision the record names rather than taken on trust.
set -eu
echo "fixture check at $(git rev-parse HEAD)"'

CF_CHECK_FAILS="$CF_CHECK_PASSES"'
echo "one scenario failed"
exit 1'

CF_CHECK_SLOW='#!/bin/sh
# A check that outlasts its deadline. The scenario registers deadline_seconds 1, so this is a
# second-order wait and not a slow test: what is being exercised is the poll giving up, which the
# harness never sees the duration of.
set -eu
sleep 30
echo "this line is never reached"'

case "$shape" in
  check-fails) cf_check=$CF_CHECK_FAILS ;;
  check-slow)  cf_check=$CF_CHECK_SLOW ;;
  *)           cf_check=$CF_CHECK_PASSES ;;
esac

scoped=$(cf_commit "the milestone's brief declares its scope" docs/milestones/M02.md "$CF_SCOPE" "$root")
base=$(cf_commit "the project's standing check" check.sh "$cf_check" "$scoped")

candidate=''; merge=''; wrong=''; head=''

case "$shape" in
  # The ordinary close-out: one in-scope commit on the branch, merged into main.
  valid|forged-check|check-fails|check-slow|repeat)
    candidate=$(cf_commit "the milestone's work" docs/one.md "one" "$base")
    merge=$(cf_merge "merge m02" "$candidate" "$base" "$candidate")
    ;;
  # main carries work of its own after the merge, from a lane this milestone knows nothing about.
  # The changed paths must still be the branch's, and the checked revision must be the merge.
  main-moved-on)
    candidate=$(cf_commit "the milestone's work" docs/one.md "one" "$base")
    merge=$(cf_merge "merge m02" "$candidate" "$base" "$candidate")
    head=$(cf_commit "another lane's work" docs/three.md "three" "$merge")
    ;;
  # The branch changed nothing at all against its baseline.
  unchanged-branch)
    candidate=$base
    merge=$(cf_commit "a commit that is not the branch's" docs/three.md "three" "$base")
    ;;
  # The branch changed one file, and it is not in the milestone's declared scope.
  out-of-scope)
    candidate=$(cf_commit "work outside the declared scope" README.md "readme" "$base")
    merge=$(cf_merge "merge m02" "$candidate" "$base" "$candidate")
    ;;
  # The branch did in-scope work and was never merged; main moved on separately. The claim descends
  # from the baseline, which is exactly the ancestry that used to be enough.
  unmerged-candidate)
    candidate=$(cf_commit "the milestone's work, unmerged" docs/one.md "one" "$base")
    merge=$(cf_commit "an unrelated commit on main" docs/three.md "three" "$base")
    ;;
  # The branch moved on after the merge, so its tip is no longer inside the commit being claimed.
  branch-moved)
    cf_first=$(cf_commit "the milestone's work" docs/one.md "one" "$base")
    merge=$(cf_merge "merge m02" "$cf_first" "$base" "$cf_first")
    candidate=$(cf_commit "a commit made after the merge" docs/two.md "two" "$cf_first")
    cf_say FIRST "$cf_first"
    ;;
  # The dispatch recorded a baseline the branch does not descend from.
  wrong-baseline)
    wrong=$(cf_commit "a baseline on no branch of this milestone" docs/three.md "three" "$base")
    candidate=$(cf_commit "the milestone's work" docs/one.md "one" "$base")
    merge=$(cf_merge "merge m02" "$candidate" "$base" "$candidate")
    ;;
  *) echo "completion-fixture: unknown shape $shape" >&2; exit 2 ;;
esac

git -C "$repo" branch -f m02 "$candidate"
git -C "$repo" update-ref refs/heads/main "${head:-$merge}"

cf_say BASELINE "$base"
cf_say CANDIDATE "$candidate"
cf_say MERGE "$merge"
[ -z "$wrong" ] || cf_say WRONG "$wrong"
[ -z "$head" ] || cf_say HEAD "$head"

# The substitution into the scenario's own home/. A second run finds no placeholder left and
# changes nothing, which is what lets the cmd be run twice.
while read -r cf_name cf_value || [ -n "$cf_name" ]; do
  [ -n "$cf_name" ] && [ -n "$cf_value" ] || continue
  find "$BATON_HOME" -type f -exec sed -i '' "s|@$cf_name@|$cf_value|g" {} +
done < "$subs"
