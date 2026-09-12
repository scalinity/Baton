# Contract 2: run identity is authoritative; artifact fields must bind to that run.
def token: type=="string" and test("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$");
def text: type=="string" and length>0;
length==1 and (.[0] |
  type=="object" and .baton==2 and (.message_id|token) and (.run|token)
  and (.session|token) and (.milestone|type=="string" and test("^M[0-9]+(-[a-z0-9]+)?$"))
  and (.project|text) and (.plan_revision|type=="string" and test("^[0-9a-f]{40,64}$"))
  and (.written_at|type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
  and (.outcome|type=="string") and (has("eligible") or has("wait_for") or has("model") or has("prompt")|not)
  and (if .outcome=="complete" then (.merged_as|type=="string" and test("^[0-9a-f]{40,64}$"))
       elif .outcome=="asking" then (.question|text) and ((.options // [])|type=="array" and all(.[];text))
       elif .outcome=="stopped" then (.reason|type=="string" and IN("unfinished","blocked","merge-failed","main-broken","no-handover","api-error","other"))
         and (.detail|type=="string") and (if .reason=="blocked" then (.blocked_by|token) else true end)
         and (if .reason=="api-error" then (.error|text) else true end)
       else false end))
