#!/bin/sh
# Immutable, content-addressed releases. No active session's pinned hooks are replaced.
set -eu
umask 077
here=$(cd "$(dirname "$0")" && pwd -P)
BATON_HOME=${BATON_HOME:-$HOME/.baton}
. "$here/lib/lock.sh"
lock_take
mkdir -p "$BATON_HOME/bin" "$BATON_HOME/releases" "$BATON_HOME/projects" "$BATON_HOME/inbox" "$BATON_HOME/processing" "$BATON_HOME/archive" "$BATON_HOME/rejected"
release_id=$(cd "$here" && find bin lib hooks -type f | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256 | awk '{print $1}')
release=$BATON_HOME/releases/$release_id
if [ ! -d "$release" ]; then
  staging=$(mktemp -d "$BATON_HOME/releases/.stage.XXXXXX")
  cp -R "$here/bin" "$here/lib" "$here/hooks" "$staging/"
  staged_id=$(cd "$staging" && find bin lib hooks -type f | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256 | awk '{print $1}')
  [ "$staged_id" = "$release_id" ] || { echo 'baton: source changed during install; incomplete release not selected' >&2; exit 1; }
  printf '%s\n' "$release_id" > "$staging/release-id"
  chmod -R go-rwx "$staging"
  mv "$staging" "$release"
fi
selection=$BATON_HOME/.current-$$
ln -s "releases/$release_id" "$selection"
mv -fh "$selection" "$BATON_HOME/current"
wrapper=$(mktemp "$BATON_HOME/bin/.baton.XXXXXX")
cat > "$wrapper" <<'WRAPPER'
#!/bin/sh
set -eu
home=$(cd "$(dirname "$0")/.." && pwd -P)
release=$(cd "$home/current" && pwd -P)
BATON_HOME=${BATON_HOME:-$home}
export BATON_HOME
exec /bin/sh "$release/bin/baton" "$@"
WRAPPER
chmod 700 "$wrapper"
mv "$wrapper" "$BATON_HOME/bin/baton"
if [ ! -x "$BATON_HOME/bin/sh" ]; then cp /bin/sh "$BATON_HOME/bin/sh"; fi
if [ ! -f "$BATON_HOME/config.json" ]; then
  printf '%s\n' '{"schema":2,"cap":2,"claudeVersion":"2.1.268","trustedLocal":false,"models":{"fable":"fable","opus":"opus","sonnet":"sonnet","haiku":"haiku"}}' > "$BATON_HOME/config.json"
fi
canonical=$(git -C "$here" worktree list --porcelain|awk '/^worktree / {print substr($0,10);exit}')
project=$(basename "$canonical")
mkdir -p "$BATON_HOME/projects/$project"
if [ ! -f "$BATON_HOME/projects/$project/project.json" ]; then
  jq -n --arg p "$canonical" '{path:$p,plan:"docs/MILESTONES.md",contract:2,check:["sh","tests/run.sh"],checkReplaySafe:true}' > "$BATON_HOME/projects/$project/project.json"
fi
if [ ! -f "$BATON_HOME/projects/$project/permissions.json" ]; then
  jq -n --arg h "/$BATON_HOME" '{permissions:{deny:(["Bash(sudo:*)","Bash(su:*)","Bash(doas:*)","Bash(osascript * administrator privileges*)"]
    + (["log.jsonl","config.json","mutation.lock","current","bin","releases","runs","settings","projects","processing","archive","rejected","integrations"]
       | map("Edit(\($h)/\(.)/**)","Write(\($h)/\(.)/**)","Edit(\($h)/\(.))","Write(\($h)/\(.))")))}}' > "$BATON_HOME/projects/$project/permissions.json"
fi
printf 'installed release %s; existing configuration and active sessions preserved\n' "$release_id"
printf 'review docs/MIGRATION.md before enabling dispatch; trustedLocal defaults to false\n'
