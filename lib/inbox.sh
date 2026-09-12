#!/bin/sh
# Immutable messages are claimed before validation. The decision is committed before archival;
# a processing file is sufficient to resume interrupted acknowledgement and archival.
set -eu
project_key_of() {
  for pk_pj in "$BATON_HOME"/projects/*/project.json; do
    [ -f "$pk_pj" ] || continue
    if [ "$(jq -r .path "$pk_pj")" = "$1" ]; then basename "$(dirname "$pk_pj")"; return; fi
  done
  return 1
}
merged_as_verify() {
  printf '%s' "$2" | grep -Eq '^[0-9a-f]{40,64}$' || return 1
  [ "$(baton_git -C "$1" rev-parse --verify "$2^{commit}")" = "$2" ] && baton_git -C "$1" merge-base --is-ancestor "$2" main
}
artifact_hash() { jq -Sc . "$1" | shasum -a 256 | awk '{print $1}'; }
artifact_check() {
  jq -se -f "$BATON_LIB/artifact.jq" "$1" >/dev/null 2>&1 || { echo 'contract-2-schema'; return 1; }
  ac_a=$(jq -c . "$1")
  ac_run=$(run_get "$(printf '%s' "$ac_a"|jq -r .run)") || { echo 'unknown-run'; return 1; }
  jq -ne --argjson a "$ac_a" --argjson r "$ac_run" \
    '$a.session==$r.session and $a.project==$r.path and $a.milestone==$r.milestone and $a.plan_revision==$r.plan_revision' >/dev/null \
    || { echo 'run-identity'; return 1; }
  [ "$(printf '%s' "$ac_run"|jq -r .state)" = active ] || { echo 'run-not-active'; return 1; }
  if [ "$(printf '%s' "$ac_a"|jq -r .outcome)" = complete ]; then
    ac_receipt=$(integration_record "$(printf '%s' "$ac_a"|jq -r .run)" integrated) || { echo 'no-integration-receipt'; return 1; }
    ac_sha=$(printf '%s' "$ac_a"|jq -r .merged_as)
    [ "$ac_sha" = "$(printf '%s' "$ac_receipt"|jq -r .integrated_commit)" ] \
      && merged_as_verify "$(printf '%s' "$ac_run"|jq -r .path)" "$ac_sha" \
      || { echo 'integration-mismatch'; return 1; }
  fi
  printf '%s\n' "$ac_a"
}
message_event() {
  log_json | jq -ce --arg id "$1" '[.[]|select(.kind=="consumed" and .message_id==$id)]|last // empty'
}
reject_claim() {
  rc_file=$1; rc_reason=$2
  rc_id=$(basename "$rc_file" .json)
  rc_dest=$BATON_HOME/rejected/$rc_id.json
  mkdir -p "$BATON_HOME/rejected"
  # The stable claim name makes rejection replay idempotent, even when the input is not JSON.
  log_event rejected '' '' '' '' "$(jq -nc --arg path "$rc_dest" --arg why "$rc_reason" --arg id "rejected:$rc_id" '{path:$path,reason:$why,event_id:$id}')" || return 1
  mv "$rc_file" "$rc_dest" || return 1
  printf 'rejected %s: %s\n' "$rc_dest" "$rc_reason"
}
consume_claim() {
  cc_file=$1
  if ! jq -se -f "$BATON_LIB/artifact.jq" "$cc_file" >/dev/null 2>&1; then reject_claim "$cc_file" contract-2-schema; return; fi
  cc_id=$(jq -r .message_id "$cc_file")
  cc_hash=$(artifact_hash "$cc_file") || return 1
  cc_a=$(jq -c . "$cc_file")
  cc_prior=''
  if cc_prior=$(message_event "$cc_id"); then
    [ "$(printf '%s' "$cc_prior"|jq -r .payload_sha256)" = "$cc_hash" ] \
      || { reject_claim "$cc_file" conflicting-message-id; return; }
  else
    if ! cc_checked=$(artifact_check "$cc_file"); then
      # A fast worker can publish before its row is observed. Keep the claimed message while
      # its prepared launch remains unresolved; do not invent session ownership from the file.
      cc_run=$(run_get "$(printf '%s' "$cc_a"|jq -r .run)" 2>/dev/null || echo '{}')
      if printf '%s' "$cc_run"|jq -e '.state=="prepared" or .state=="uncertain"' >/dev/null; then
        printf 'processing %s: awaiting dispatch acknowledgement\n' "$cc_id"; return
      fi
      reject_claim "$cc_file" "$cc_checked"; return
    fi
  fi
  cc_run=$(run_get "$(printf '%s' "$cc_a"|jq -r .run)") || return 1
  cc_dest=$BATON_HOME/archive/$cc_id.json
  mkdir -p "$BATON_HOME/archive"
  if [ -f "$cc_dest" ] && [ "$(artifact_hash "$cc_dest")" != "$cc_hash" ]; then reject_claim "$cc_file" archive-conflict; return; fi
  cc_fields=$(printf '%s' "$cc_a"|jq -c --arg archive "$cc_dest" --arg hash "$cc_hash" --arg eid "consumed:$cc_id" \
    '{message_id,outcome,reason,error,blocked_by,merged_as,question,options,context}
     | with_entries(select(.value!=null))
     | . + {archive:$archive,payload_sha256:$hash,event_id:$eid,
       written_by:(if .reason=="no-handover" then "stop-gate" elif .reason=="api-error" then "stop-failure" else "session" end)}')
  run_event consumed "$(printf '%s' "$cc_a"|jq -r .run)" "$cc_fields" || return 1
  # Consumption is observation only. No hook/artifact may stop a human-controlled session.
  if [ "$(printf '%s' "$cc_a"|jq -r .outcome)" = asking ]; then
    run_event escalation "$(printf '%s' "$cc_a"|jq -r .run)" "$(printf '%s' "$cc_a"|jq -c --arg id "asking:$cc_id" '{class:"asking",scope:"lane",carries:{question,options,context},event_id:$id}')" || return 1
  fi
  mv "$cc_file" "$cc_dest" || return 1
  printf 'consumed %s (%s)\n' "$cc_id" "$(printf '%s' "$cc_a"|jq -r .outcome)"
}
inbox_consume() {
  lock_require || return 1
  mkdir -p "$BATON_HOME/processing" "$BATON_HOME/inbox"
  for ic_file in "$BATON_HOME"/processing/*.json; do
    [ -f "$ic_file" ] || continue
    consume_claim "$ic_file" || return 1
  done
  for ic_file in "$BATON_HOME"/inbox/*.json; do
    [ -f "$ic_file" ] || continue
    [ ! -L "$ic_file" ] || { echo "baton: refusing inbox symlink $ic_file" >&2; return 1; }
    ic_claim=$BATON_HOME/processing/$(new_id).json
    mv "$ic_file" "$ic_claim" || return 1
    consume_claim "$ic_claim" || return 1
  done
}
