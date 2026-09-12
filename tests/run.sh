#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd -P)
for file in "$root/bin/baton" "$root/install.sh" "$root"/lib/*.sh "$root"/hooks/* "$root/tests/foundation.sh"; do
  sh -n "$file"
done
jq -n -f "$root/lib/artifact.jq" >/dev/null
sh "$root/tests/legacy-read.sh"
sh "$root/tests/foundation.sh"
