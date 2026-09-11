# Claude Code 2.1.268 hooks: events, payloads, and what a return value can do

Date: 2026-09-11. Installed version: `2.1.268 (Claude Code)` (`/Users/danny/.local/bin/claude --version`).

## Sources

Official pages, fetched 2026-09-11. Each page serves its raw markdown at the page URL with `.md` appended (for example `https://code.claude.com/docs/en/hooks.md`); every quotation below is from that text.

| Key | URL |
|---|---|
| H | https://code.claude.com/docs/en/hooks (Hooks reference) |
| G | https://code.claude.com/docs/en/hooks-guide |
| S | https://code.claude.com/docs/en/settings |
| SR | https://code.claude.com/docs/en/settings-reference |
| C | https://code.claude.com/docs/en/cli-reference |
| HL | https://code.claude.com/docs/en/headless |
| AV | https://code.claude.com/docs/en/agent-view |
| EV | https://code.claude.com/docs/en/env-vars |
| P | https://code.claude.com/docs/en/permissions |
| SDK | https://code.claude.com/docs/en/agent-sdk/hooks |

Local, read-only: `claude --version`, `claude --help`. No session was started, stopped, attached or resumed. Context7 (`/websites/code_claude`) returned the same `idle_prompt` timing as H and G and added nothing.

The docs describe the current release. Where a statement is version-gated the docs' own "requires v2.1.x" is quoted; 2.1.268 is later than every gate cited here. Anything marked **unverified** is not stated in these sources.

## 1. Fields every event receives (H, "Common input fields")

Command hooks read this JSON on stdin; HTTP hooks receive it as the POST body.

| Field | Present | Notes |
|---|---|---|
| `session_id` | always | |
| `hook_event_name` | always | the event name |
| `cwd` | always | "Current working directory when the hook is invoked". Follows Claude into a worktree and after `cd`; `${CLAUDE_PROJECT_DIR}` stays at the project root where the session started |
| `transcript_path` | always | "Path to conversation JSON. The transcript file is written asynchronously and may lag the in-memory conversation, so it may not yet include the current turn's most recent messages when a hook fires." Use `last_assistant_message` on Stop/SubagentStop for the final text |
| `prompt_id` | after the first user input | UUID of the prompt being processed; requires v2.1.196 or later |
| `scratchpad_dir` | when the session has one | requires v2.1.257 or later |
| `permission_mode` | not on every event | `"default"`, `"plan"`, `"acceptEdits"`, `"auto"`, `"dontAsk"`, `"bypassPermissions"`; Manual arrives as `"default"` |
| `effort` | events in a tool-use context (PreToolUse, PostToolUse, Stop, SubagentStop) when the model supports it | `{ "level": "low" \| "medium" \| "high" \| "xhigh" \| "max" }`; also `$CLAUDE_EFFORT` in the hook's environment |
| `agent_id`, `agent_type` | with `--agent`, or when the hook fires inside a subagent | |
| `model` | SessionStart only, and not always | |

The hook process inherits the parent environment (minus `OTEL_*`). `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_DATA}` are substituted into `command` and `args`. `CLAUDE_ENV_FILE` (a file whose `export` lines persist into later Bash commands) exists for SessionStart, Setup, CwdChanged and FileChanged hooks only.

## 2. Output semantics shared by every event (H, "Exit code output" and "JSON output")

- stdout is parsed as JSON when, ignoring surrounding whitespace, it starts with `{` and ends with `}`; anything else is plain text. JSON is read on every exit code, not only 0.
- Exit 0: success. Plain-text stdout goes to the debug log, except on `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart` and `PostModelSwitch`, where "Claude Code adds plain-text stdout as context that Claude can see and act on". stderr on exit 0 goes to the debug log only.
- Exit 2: blocking error on the events that can block. "exit 2 blocks whether or not you print JSON: even a JSON `permissionDecision` of `"allow"` can't override it." The blocking message is "the reason from your JSON's blocking decision when it makes one, and your stderr text otherwise."
- Any other exit code: non-blocking. With valid JSON that passes schema validation "Claude Code ignores the exit code and the JSON alone decides the outcome"; otherwise the transcript shows a `<hook name> hook error` notice with the first stderr line and the action proceeds. Exit 1 does not block.
- Timeout: the hook is cancelled and its output discarded, so "on most events a timed-out hook renders no decision". Exceptions: a `PreModelSwitch` hook cancelled at its timeout blocks the switch; an Agent SDK callback hook that times out on `PreToolUse` blocks the tool call.
- Output strings (`additionalContext`, `systemMessage`, plain stdout) are capped at 10,000 characters; longer output is written to a file and replaced with a preview and path.
- "All matching hooks run in parallel. If you define the same handler in more than one settings file, it runs once."

Universal JSON fields:

| Field | Effect |
|---|---|
| `continue` (default `true`) | "If `false`, Claude stops processing entirely after the hook runs. Takes precedence over any event-specific decision fields" |
| `stopReason` | shown to the user when `continue` is `false`; "It stays in the conversation, so Claude sees it if the conversation continues" |
| `systemMessage` | "Warning message shown to the user"; in the Agent SDK and `--output-format stream-json` it can arrive as an `SDKInformationalMessage`. Several events discard it (noted per event below) |
| `suppressOutput` | "Has no effect" |
| `terminalSequence` | allow-listed OSC/BEL escape that Claude Code writes to the terminal; "In non-interactive mode with the `-p` flag and in the Agent SDK, it ignores the field" |
| top-level `decision: "block"` + `reason` | the decision pattern for UserPromptSubmit, UserPromptExpansion, PostToolUse, PostToolUseFailure, PostToolBatch, Stop, SubagentStop, ConfigChange and PreCompact. "The only value for `decision` is `"block"`. To allow the action to proceed, omit `decision` from your JSON, or exit 0 without any JSON at all" |
| `hookSpecificOutput` | object that "requires a `hookEventName` field set to the event name"; carries `additionalContext`, `permissionDecision`, `updatedInput`, and the other event-specific fields |

`additionalContext` is wrapped in a system reminder and inserted where the hook fired; for Stop and SubagentStop "at the end of the turn. The conversation continues so Claude can act on the feedback." On `--continue`/`--resume`, saved mid-session hook context is replayed rather than re-run; SessionStart runs again with `source` `"resume"` (or `"fork"`).

## 3. Event table

Every row is from H: the lifecycle table (when it fires), the matcher table, the "Exit code 2 behavior per event" table, the "Decision control" table, and each event's own input and decision-control sections. Payload = fields beyond section 1. Hook types are all five (`command`, `http`, `mcp_tool`, `prompt`, `agent`) unless a row says otherwise.

| Event | Matcher filters on | Payload beyond the common fields | What a return value can do |
|---|---|---|---|
| `SessionStart` | how the session started: `startup`, `resume`, `clear`, `compact`, `fork` | `source`; optional `model`, `agent_type`, `session_title`; on `resume`/`fork` with at least one prior response (v2.1.251+): `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd` | Cannot block (exit 2 "Shows stderr to user only"). Plain stdout becomes context. `hookSpecificOutput`: `additionalContext`, `initialUserMessage` (in `-p` "it becomes the first turn even if no prompt is provided"), `sessionTitle` (startup/resume/fork only), `watchPaths`, `reloadSkills`. Types: `command` and `mcp_tool` only; `mcp_tool` hooks are skipped at launch, including with `--continue`/`--resume`, and run after `/clear` or compaction. `CLAUDE_ENV_FILE` |
| `Setup` | `init`, `maintenance` | `trigger` | Nothing: "Setup hooks can't block; execution continues on any exit code", and every JSON field is discarded. Fires only with `--init-only`, `-p --init`, `-p --maintenance`. `command` only. `CLAUDE_ENV_FILE` |
| `UserPromptSubmit` | none | `prompt` | Exit 2 or `decision: "block"` "Blocks prompt processing and erases the prompt"; `reason`/stderr go to the user, not to context. Plain stdout or `hookSpecificOutput.additionalContext` is injected alongside the prompt; `sessionTitle`; `suppressOriginalPrompt`. "can't replace the prompt". Default timeout 30 s; a timed-out hook's context is dropped and the prompt still goes through |
| `UserPromptExpansion` | command name | `expansion_type` (`slash_command` or `mcp_prompt`), `command_name`, `command_args`, `command_source`, `prompt` | Exit 2 or `decision: "block"` blocks the expansion (`reason` shown to the user); `additionalContext` |
| `PreToolUse` | tool name (plus the per-handler `if` permission-rule filter) | `tool_name`, `tool_input`, `tool_use_id` | `hookSpecificOutput.permissionDecision`: `allow`, `deny`, `ask`, `defer`; `permissionDecisionReason`; `updatedInput` ("Replaces the entire input object"); `additionalContext`. Exit 2 = deny with stderr as the reason. Precedence `deny` > `defer` > `ask` > `allow`. A timed-out command hook does not block. `defer` is honoured only in `-p` |
| `PermissionRequest` | tool name | `tool_name`, `tool_input` (no `tool_use_id`), optional `permission_suggestions[]` | `hookSpecificOutput.decision`: `{ "behavior": "allow" \| "deny", "updatedInput", "updatedPermissions": [...], "message", "interrupt" }`. Exit 2 "isn't honored". Fires only when Claude Code would prompt (or would auto-deny a call that cannot prompt); "if no hook returns a decision, it denies the tool call" |
| `PermissionDenied` | tool name | `tool_name`, `tool_input`, `tool_use_id`, `reason` | `hookSpecificOutput.retry: true` tells the model it may retry; exit code and stderr ignored. Auto mode only |
| `PostToolUse` | tool name | `tool_name`, `tool_input`, `tool_response`, `tool_use_id`, `duration_ms` | Cannot block; exit 2 "Shows stderr to Claude; the tool already ran". `decision: "block"` + `reason` adds the reason next to the result; `additionalContext`; `updatedToolOutput` (must match the tool's output shape); `classifierContext` (v2.1.236+); `updatedMCPToolOutput` |
| `PostToolUseFailure` | tool name | `tool_name`, `tool_input`, `tool_use_id`, `error`, `is_interrupt`, `duration_ms` | Cannot block; `additionalContext`; exit 2 shows stderr to Claude |
| `PostToolBatch` | none | `tool_calls[]` of `{ tool_name, tool_input, tool_use_id, tool_response }` | `additionalContext` injected once before the next model call. `decision: "block"`, `continue: false`, or exit 2 "Stops the agentic loop before the next model call" |
| `Notification` | notification type (12 values, section 4.2) | `message`, optional `title`, `notification_type` | None: "Notification hooks can't block or modify notifications. Claude Code discards their `systemMessage` and `continue` fields but still emits `terminalSequence`". Exit code and stderr ignored. `command`/`http`/`mcp_tool` only |
| `MessageDisplay` | none | `turn_id`, `message_id`, `index`, `final`, `delta` | `displayContent` replaces the on-screen text only; no decision control; default timeout 10 s. In `-p`/SDK runs it fires once per message with the whole text. `command`/`http`/`mcp_tool` only |
| `SubagentStart` | agent type | `agent_id`, `agent_type` | Cannot block; `additionalContext` is injected into the subagent; exit 2 stderr is shown in the subagent's transcript only. `command`/`http`/`mcp_tool` only |
| `SubagentStop` | agent type | `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `session_crons` | Same as `Stop`: "Returning `decision: "block"` with a `reason` keeps the subagent running and delivers `reason` to the subagent as its next instruction. A hook that blocks by exiting 2 delivers its stderr message the same way." `hookSpecificOutput.additionalContext` with `hookEventName` `"SubagentStop"`. A `Stop` hook in subagent frontmatter is converted to `SubagentStop` |
| `TaskCreated` | none | `task_id`, `task_subject`, optional `task_description`, `teammate_name`, `team_name` | Exit 2 or `decision: "block"` deletes the task and returns the message as the tool error; `continue: false` ignored |
| `TaskCompleted` | none | same fields as `TaskCreated` | Exit 2: not marked completed, stderr fed back to the model. `{"continue": false, "stopReason"}` stops a teammate that triggered it by finishing its turn; ignored when `TaskUpdate` triggered it |
| `Stop` | none | `stop_hook_active`, `last_assistant_message`, `background_tasks[]`, `session_crons[]` | `decision: "block"` + `reason` (required) prevents stopping and "Tells Claude why it should continue"; exit 2 does the same with stderr; `hookSpecificOutput.additionalContext` continues the conversation as "Stop hook feedback"; `continue: false` stops entirely. Cap of 8 consecutive blocks. Prompt/agent hooks: `{"ok": false, "reason"}` feeds the reason back; `"impossible": true` lets the stop through. Details in 4.1 |
| `StopFailure` | error type (`rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error`, `unknown`) | `error`, optional `error_details`, optional `last_assistant_message` (the API error text) | None: "Output and exit code are ignored, except `terminalSequence`". `command`/`http`/`mcp_tool` only |
| `TeammateIdle` | none | `teammate_name`, `team_name` | Exit 2: the teammate "receives the stderr message as feedback and continues working instead of going idle"; `{"continue": false, "stopReason"}` stops it |
| `InstructionsLoaded` | load reason: `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact` | not extracted here (H, "InstructionsLoaded input") | None; exit code ignored. `command`/`http`/`mcp_tool` only |
| `ConfigChange` | `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills` | `source`, optional `file_path` | Exit 2 or `decision: "block"` keeps the change from applying, except `policy_settings`; `reason` "Accepted but never shown"; `systemMessage` and `continue` discarded. `command`/`http`/`mcp_tool` only |
| `CwdChanged` | none | `old_cwd`, `new_cwd` | Cannot block; `watchPaths`; `systemMessage` as a brief terminal notification; `continue` discarded; `CLAUDE_ENV_FILE` |
| `DirectoryAdded` | `slash_command`, `register_repo_root` | `directory`, `source` | Cannot block; runs in the background with the 600 s default. `systemMessage` reaches Claude as context on the next turn (`slash_command`) or only the debug log (`register_repo_root`) |
| `FileChanged` | literal filenames split on `\|` (the value is also the watch list) | `file_path`, `event` (`change`, `add`, `unlink`) | Cannot block; `watchPaths`; `systemMessage` as a terminal notification; `CLAUDE_ENV_FILE` |
| `WorktreeCreate` | none | `name` (worktree slug) | Replaces `git worktree`: a command hook prints the worktree path as the last non-empty stdout line (HTTP: `hookSpecificOutput.worktreePath`); "Any non-zero exit code causes worktree creation to fail"; `systemMessage`/`continue` discarded. Fires for `--worktree`, `isolation: "worktree"` subagents, and "for a background session that Claude Code isolates in its own worktree" |
| `WorktreeRemove` | none | `worktree_path` | Exit code decides: non-zero with the directory still present fails the removal; JSON discarded |
| `PreCompact` | `manual`, `auto` | `trigger`, `custom_instructions` (`null` for `auto`, or when `/compact` had no argument) | Exit 2 or `decision: "block"` blocks compaction (for `/compact` the stderr is shown to the user); `systemMessage`/`continue` discarded. Blocking a recovery compaction after a context-limit error makes the current request fail. `command`/`http`/`mcp_tool` only |
| `PostCompact` | `manual`, `auto` | `trigger`, `compact_summary` | None; exit 2 shows stderr to the user only; `systemMessage`/`continue` discarded. `command`/`http`/`mcp_tool` only |
| `PreModelSwitch` | canonical name of the target model | `from_model`, `to_model`, `requested_model`, `source` (`command`, `picker`, `sdk`), `context_tokens`, `prompt_cache_warm`, `cache_ttl`, `estimated_cache_write_usd`, `pricing` | Exit 2, `decision: "block"`, or `hookSpecificOutput.permissionDecision` `allow`/`deny`/`ask`; timeout (default 30 s) blocks; `ask` works only in an interactive `/model`. v2.1.251+. `command`/`http`/`mcp_tool` only |
| `PostModelSwitch` | canonical model name | as `PreModelSwitch`, plus `source` values `auto` and `resume` | Cannot block; plain stdout or `additionalContext` is delivered with the next request. v2.1.251+. `command`/`http`/`mcp_tool` only |
| `Elicitation` | MCP server name | `mcp_server_name`, `message`, optional `mode` (`form`/`url`), `url`, `elicitation_id`, `requested_schema` | `hookSpecificOutput.action` `accept`/`decline`/`cancel` + `content`; exit 2 denies (stderr not shown); `systemMessage`/`continue` discarded. `command`/`http`/`mcp_tool` only |
| `ElicitationResult` | MCP server name | `mcp_server_name`, `action`, optional `mode`, `elicitation_id`, `content` | `hookSpecificOutput.action`/`content` override the user's response; exit 2 turns the action into `decline`. `command`/`http`/`mcp_tool` only |
| `SessionEnd` | why the session ended: `clear`, `resume`, `logout`, `prompt_input_exit`, `other` | `reason` | None: "can't block session termination"; JSON fields discarded; exit 2 shows stderr to the user only. Hooks share a 1.5 s budget (raised to the highest configured per-hook `timeout`, up to 60 s; `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`). `command`/`http`/`mcp_tool` only |

Cadence (H, "Hook lifecycle"): "per session: `SessionStart` and `SessionEnd`; per turn: `UserPromptSubmit`, `Stop`, and `StopFailure`; on every tool call inside the agentic loop: `PreToolUse` and `PostToolUse`", with `EndConversation` calls skipping both tool events.

## 4. Answers to the ticket

### 4.1 Stop

**Payload.** "In addition to the common input fields, Stop hooks receive `stop_hook_active`, `last_assistant_message`, `background_tasks`, and `session_crons`." `transcript_path` is a common field, so yes, with the lag caveat in section 1; `last_assistant_message` "contains the text content of Claude's final response, so hooks can access it without parsing the transcript file". `background_tasks` and `session_crons` "let hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it back up'" (H, "Stop input").

Documented example input:

```json
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_hook_active": true,
  "last_assistant_message": "I've completed the refactoring. Here's a summary...",
  "background_tasks": [ { "id": "task-001", "type": "shell", "status": "running", "description": "tail logs", "command": "tail -f /var/log/syslog" } ],
  "session_crons": [ { "id": "cron-001", "schedule": "0 9 * * 1-5", "recurring": true, "prompt": "check the build" } ]
}
```

**`stop_hook_active`.** "The `stop_hook_active` field is `true` when Claude Code is already continuing as a result of a stop hook. Check this value or process the transcript to avoid blocking on a condition that will never resolve. Claude Code overrides the hook and ends the turn after 8 consecutive blocks." (H, "Stop input"). G adds: "Claude keeps working instead of stopping, then ends the turn with a warning that the Stop hook blocked too many consecutive times." The cap is `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (default 8; `0` disables it; applies to Stop and SubagentStop) (EV).

**Block with a reason, and what the session does next.** Yes. Top-level fields (H, "Stop decision control"):

| Field | Description (quoted) |
|---|---|
| `decision` | "`"block"` prevents Claude from stopping. Omit to allow Claude to stop" |
| `reason` | "Required when `decision` is `"block"`. Tells Claude why it should continue" |
| `hookSpecificOutput.additionalContext` | "Non-error feedback for Claude. The conversation continues so Claude can act on it, but unlike `decision: "block"` it is shown in the transcript as hook feedback rather than a hook error" |

```json
{ "decision": "block", "reason": "Must be provided when Claude is blocked from stopping" }
```

Exit 2: "Prevents Claude from stopping, continues the conversation" (per-event table) and "A hook that blocks by exiting 2 routes the same way as `reason`: Claude receives the stderr message as the explanation for why it should continue."

The docs describe the delivered text as an instruction. For SubagentStop, the same mechanism: "Returning `decision: "block"` with a `reason` keeps the subagent running and delivers `reason` to the subagent as its next instruction" (H). For prompt-type Stop hooks: "the reason is fed back to Claude as its next instruction and the turn continues" (H, "Response schema"); G: "Claude keeps working and uses the `reason` as its next instruction". `additionalContext` on Stop lands "at the end of the turn. The conversation continues so Claude can act on the feedback" and "keeps the conversation going through the same loop protections as `decision: "block"`, namely the `stop_hook_active` input and the 8-consecutive-continuation cap, but the transcript labels it `Stop hook feedback` and no hook error notification is shown".

So the native nudge exists: a command hook on `Stop` that prints `{"decision":"block","reason":"<handover instructions>"}` (or `additionalContext`, which reads as feedback rather than an error) makes the session continue with that text as its next instruction, in interactive, `-p` and background sessions alike as far as the docs distinguish (section 4.5). What is not free is the gate: `Stop` fires after every response, so the hook has to decide when the handover is still owed (for example, `stop_hook_active` false and `last_assistant_message` lacking a sentinel) and exit 0 otherwise; a hook that blocks unconditionally is overridden after 8 blocks. The exact transport of `reason` (user turn versus system reminder) is not specified beyond the quotations above.

`continue: false` with `stopReason` "stops processing entirely" and "Takes precedence over any event-specific decision fields" (H, "JSON output"). The `/goal` command "is a built-in shortcut for a session-scoped prompt-based Stop hook". Stop supports all five hook types; agent hooks get 60 s and up to 50 tool-use turns (G).

**Once per turn or end of conversation.** Per turn. "Runs when the main Claude Code agent has finished responding. Does not run if the stoppage occurred due to a user interrupt. API errors fire StopFailure instead." (H). "`Stop` hooks fire whenever Claude finishes responding, not only at task completion. They don't fire on user interrupts." (G, "Limitations"). The end-of-conversation event is `SessionEnd`.

### 4.2 Notification

`notification_type` values and timing (H, "Notification"; the same table is in G):

| Type | Fires when (quoted) | Version |
|---|---|---|
| `permission_prompt` | "Claude needs you to approve a tool use or a sandboxed command's network request, and the prompt has waited about six seconds". "The timer starts when the permission prompt appears, and each keystroke defers it." In SDK-hosted sessions (Claude Desktop, VS Code): about six seconds, no keystroke deferral, not run if answered sooner; `CLAUDE_CODE_DISABLE_PERMISSION_PROMPT_NOTIFY_HOOKS=1` turns it off there | sandbox network requests: v2.1.246; SDK-hosted: v2.1.233 |
| `idle_prompt` | "Claude finished responding about 60 seconds ago and you haven't typed since". "Expect `idle_prompt` about 60 seconds after Claude finishes responding, and only if you haven't typed since. Claude Code doesn't send `idle_prompt` while it waits for a claude.ai usage limit to reset." | |
| `auth_success` | "Authentication completes" | |
| `elicitation_dialog` | "An MCP server opens an elicitation form and you haven't typed for about six seconds" | |
| `elicitation_url_dialog` | "An MCP server asks you to open a browser URL and you haven't typed for about six seconds" | |
| `elicitation_complete` | "An MCP server reports that a URL-mode elicitation is complete" | |
| `elicitation_response` | "An MCP elicitation response is sent back to the server" | |
| `agent_needs_input` | "A background session starts waiting on your input while agent view is open in a terminal, or the current session asks you an agent team teammate's terminal setup question and you haven't typed for about six seconds" | v2.1.198 (teammate case v2.1.248) |
| `agent_completed` | "A background session finishes or fails. Fires only while agent view is open in a terminal" | v2.1.198 |
| `quota_auto_resume_fired` | Claude Code continues a task after a claude.ai usage limit paused it | v2.1.234 |
| `quota_auto_resume_stale` | the limit reset while the machine slept for more than about 30 minutes; Claude Code waits for Enter | v2.1.234 |
| `quota_auto_resume_disabled` | Claude Code ends its wait without continuing | v2.1.234 |

"The `permission_prompt`, `idle_prompt`, `elicitation_dialog`, and `elicitation_url_dialog` types share their timing with desktop notifications, so in terminal sessions you only see them when you appear to be away from the terminal." Hooks fire even with desktop notifications off: "the `preferredNotifChannel` setting, including `notifications_disabled`, changes only how you're alerted, not whether your hook runs."

Payload: "`message` with the notification text, an optional `title`, and `notification_type`". No decision control (section 3).

In SDK sessions, and therefore `-p` (SDK): "Claude Code runs this hook for the following notification types: `permission_prompt` once a permission request has waited about six seconds on your `canUseTool` callback ... `elicitation_complete` and `elicitation_response` for user-prompt elicitation flows. Claude Code emits the other types, such as `idle_prompt`, `auth_success`, and `elicitation_dialog`, from interactive UI that SDK sessions don't run." (SDK, "Forward notifications to Slack"). `agent_needs_input` and `agent_completed` fire in the session that has agent view open, about background sessions, not inside them (AV: agent view "fire[s] the `Notification` hook with the `agent_needs_input` or `agent_completed` type").

### 4.3 SessionEnd and SessionStart

**SessionEnd** (H). Input field is `reason`:

| `reason` | Description (quoted) |
|---|---|
| `clear` | "Session cleared with `/clear` command" |
| `resume` | "Session switched via interactive `/resume`" |
| `logout` | "User logged out" |
| `prompt_input_exit` | "User exited while prompt input was visible" |
| `other` | "Other exit reasons" |
| `bypass_permissions_disabled` | "Removed in v2.1.234; Claude Code doesn't send it. Drop it from your `SessionEnd` matchers" |

"SessionEnd hooks have no decision control. They can't block session termination but can perform cleanup tasks. Claude Code discards their JSON output fields, such as `systemMessage`." Default budget 1.5 s shared by all SessionEnd hooks, raised to the highest per-hook `timeout` in settings files up to 60 s (plugin hook timeouts do not raise it); `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` overrides. In a `-p` run stopped with SIGTERM, "Claude Code then runs `SessionEnd` hooks and exits. While exiting, Claude Code starts no new tool call, sends no new model request, and runs no hook other than `SessionEnd`." (HL). Which `reason` a normal `-p` exit, or `claude stop <id>` on a background session, reports is **unverified** (not stated; `other` is the catch-all).

**SessionStart** (H). `source` values and triggers:

| `source` | Fires for (quoted) |
|---|---|
| `startup` | "New session" |
| `resume` | "`--resume`, `--continue`, or `/resume`" |
| `clear` | "`/clear`" |
| `compact` | "Auto or manual compaction" |
| `fork` | "A new session forked from an existing one: `--fork-session` with `--resume` or `--continue`, the `/fork` background copy, or `/branch`". "Before v2.1.214, forked sessions reported source `"resume"`" |

Payload and outputs: section 3. "SessionStart runs on every session, so keep these hooks fast. Only `type: "command"` and `type: "mcp_tool"` hooks are supported." After `/clear` in an interactive session the hooks run in the background and "Claude's first response still waits for the hooks to finish". `claude --init-only` runs Setup hooks and SessionStart hooks with the `startup` matcher, then exits.

### 4.4 UserPromptSubmit, PreCompact, PostCompact, SubagentStop

**UserPromptSubmit** (H). Input: `prompt`. Output: plain stdout or `hookSpecificOutput.additionalContext` reaches Claude "as a system reminder that starts with the hook's name" with no visible transcript entry; `{"decision": "block", "reason": "..."}` "prevents the prompt from being processed and erases it from context", the reason "Shown to the user ... Not added to context"; `sessionTitle`; `suppressOriginalPrompt`. Exit 2 blocks the same way. "`UserPromptSubmit`: can't replace the prompt; it only injects `additionalContext` alongside it." Default timeout 30 s for `command`/`http`/`mcp_tool`; "a stuck hook stalls the session"; a timed-out hook's output is discarded and "The prompt still reaches Claude without that context." No matcher. Prompt hooks returning `ok: false` end the turn with the reason as a warning line.

**PreCompact** (H). Matcher/`trigger`: `manual` (`/compact`) or `auto`; `custom_instructions` carries the `/compact` argument, `null` otherwise. "Exit with code 2 to block compaction. For a manual `/compact`, the stderr message is shown to the user. You can also block by returning JSON with `"decision": "block"`." Blocking a proactive auto-compaction skips it; blocking one "triggered to recover from a context-limit error already returned by the API" makes "the current request fail". `systemMessage` and `continue` discarded.

**PostCompact** exists (H). Same matcher values; input `trigger` and `compact_summary` ("the conversation summary generated by the compact operation"). "PostCompact hooks have no decision control." `systemMessage` and `continue` discarded. TypeScript SDK yes, Python SDK no (SDK table).

**SubagentStop** (H). "Runs when a Claude Code subagent has finished responding." Input: `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path` (the subagent's own transcript under a nested `subagents/` folder; `transcript_path` is the parent's), `last_assistant_message`, `background_tasks` and `session_crons` (parent-scoped). Output identical to Stop (4.1); the block cap applies. "To inject context into the parent session after a subagent returns, use a `PostToolUse` hook on the `Agent` tool instead." Hooks from settings files also fire for tool events inside subagents, with `agent_id`/`agent_type` set.

### 4.5 Do hooks run in `--bg` sessions and in `-p` sessions?

**`-p`: yes, documented.**

- "`-p` or SDK session: Claude Code never shows the dialog and treats the folder as trusted, so hooks committed in a repository's `.claude/settings.json` run in a folder you've never trusted" (H, "Workspace trust").
- "Without `--bare`, a `-p` session runs the hooks in a project's `.claude/settings.json` and connects the servers in its `.mcp.json`, even in a folder you've never trusted." (HL)
- P's "What runs before you trust a folder" table: hooks in settings files and a project skill's frontmatter hooks are "Used" under `claude -p`; frontmatter hooks in a project subagent are "Not used".
- Hook lifecycle events are visible with `claude -p --output-format stream-json --verbose --include-hook-events`; "`SessionStart` and `Setup` hook events are always included"; "`Notification`, `SessionEnd`, `PreCompact`, and `PostCompact` never produce a `hook_started` event" (C).
- `-p` specifics: `terminalSequence` ignored; async hooks still running at teardown are killed with outcome `cancelled`; `MessageDisplay` fires once per message; only `permission_prompt`, `elicitation_complete`, `elicitation_response` notifications (4.2); `PreToolUse` `defer` exists only here; `SessionStart` `initialUserMessage` creates the first turn; `Setup` fires with `--init`/`--maintenance`; `PermissionRequest` hooks run for background subagents that cannot prompt "and if no hook returns a decision, it denies the tool call"; with `--permission-prompts none` "Anything that would prompt is denied unless a `PermissionRequest` hook allows it" (HL).
- Off switches: `--bare` "skip[s] auto-discovery of hooks, skills, custom commands, subagents, plugins, MCP servers, auto memory, and CLAUDE.md" ("A hook in a teammate's `~/.claude` or an MCP server in the project's `.mcp.json` won't run, because bare mode never reads them") (HL, C); `--safe-mode` disables hooks except policy-configured ones (C); `--restricted` "loads only managed settings and `--settings`" (C).

**`--bg`: documented only indirectly.** `--bg` "Can't be combined with `-p`/`--print`" (C, HL), so a background session is an interactive-type process under the background-session service, not a print run. No sentence says "hooks run in background sessions"; the facts that establish it:

- "A background session reads its settings from the directory it runs in, the same as if you had started `claude` there." (AV)
- AV changelog v2.1.248: "A background session waiting on a permission decision while a `PermissionRequest` or `PreToolUse` hook printed an invalid answer names the hook event and the schema error on its row", and the peek panel shows "`hook output invalid:`" for such a session — those hooks fire inside background sessions.
- AV changelog v2.1.251: a background session starting during a marketplace refresh "could start without any of that marketplace's skills, agents, hooks, and MCP servers" before the fix — plugin hooks load in background sessions.
- `WorktreeCreate` runs "for a background session that Claude Code isolates in its own worktree"; `WorktreeRemove` "when you delete a background session" (H). "Every background session, whether started from agent view, `/bg`, or `claude --bg`, starts in your working directory. Before editing files, Claude moves the session into an isolated git worktree under `.claude/worktrees/`" (AV).
- `--settings` reaches them: `claude agents` "Accepts `--settings`, `--add-dir`, `--plugin-dir`, and `--mcp-config` like the top-level `claude` command" (C); when an interactive session is backgrounded with `/bg`, "Configuration flags from the original launch carry through to the backgrounded session", listing `--mcp-config`, `--strict-mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`, `--fallback-model`, `--allow-dangerously-skip-permissions` (AV).
- The attention signals for a background session are `agent_needs_input`/`agent_completed` in the agent-view session and `claude agents --json` (`state`: `working`, `blocked`, `done`, `failed`, `stopped`; `status`: `busy`, `waiting`, `idle`; `waitingFor`: `permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open`) (AV).

**Unverified for `--bg`:** whether `idle_prompt` fires inside a detached background session (its definition is "you haven't typed since", and the docs route background-session idleness through agent view instead); whether `Stop`, `SessionEnd`, `Notification` or `terminalSequence` behave differently there; the `SessionEnd` `reason` on `claude stop`.

### 4.6 Where hooks are configured; injecting them with `--settings`

Locations (H, "Hook locations"):

| Location | Scope |
|---|---|
| `~/.claude/settings.json` | all projects on the machine |
| `.claude/settings.json` | one project, committable |
| `.claude/settings.local.json` | one project, "gitignored when Claude Code saves a setting to it" |
| managed policy settings | organization-wide |
| plugin `hooks/hooks.json` | while the plugin is enabled |
| skill frontmatter | "The rest of the session once the skill is invoked" (`once: true` removes after the first successful run) |
| subagent frontmatter | while that subagent runs; `Stop` becomes `SubagentStop` |

Key precedence (S, "Settings precedence"): managed > command line (`--settings`) > `.claude/settings.local.json` > `.claude/settings.json` > `~/.claude/settings.json`. For the `hooks` key specifically: "Hook entries merge across settings levels rather than replacing each other: user, project, and local settings add their own hooks without removing managed ones" (H); SR `hooks`: "Scope: Any file. Hooks merge across files rather than replacing each other, and hooks from managed settings can't be removed from other files." Same handler in several files runs once.

`--settings <file-or-json>` (C): "Path to a settings JSON file or an inline JSON string. Values you set here override the same keys in your `settings.json` files for this session. Keys you omit keep their file-based values. The file must be a regular file no larger than 2 MiB." (S): "Claude Code applies it above your user, project, and local files and below managed settings. It can set any key your user settings file can set; it can't set `Managed` or `Global config` keys." "`--settings` lasts one session and doesn't write to any file." A file path "must point to an existing file; Claude Code exits with a `Settings file not found` error if it doesn't" (AV).

Conclusion for injection: `hooks` is an "Any file" key, `--settings` sets any user-file key for one session without writing a file, and hooks merge rather than replace, so a `hooks` block in a `--settings` file adds Baton's hooks alongside whatever the repo defines, without touching `~/.claude/settings.json` or the repo's `.claude/` files. No official example shows a `hooks` block passed through `--settings`; the closest is the documented `--settings '{"disableAllHooks": true}'`, which "takes precedence over project and local settings" (H, P). Which source label (`User Settings`, `Project Settings`, `Local Settings`, `Plugin Hooks`, `Session Hooks`) the `/hooks` menu gives a `--settings` hook is not documented. **Unverified:** whether `--settings` still applies when `--setting-sources` omits every source (the docs describe `--setting-sources` as filtering `user`, `project`, `local` files and describe `--restricted` as loading "only managed settings and `--settings`", which suggests independence, but it is not stated).

Keeping the target repo's own hooks out: `--setting-sources user` ("so Claude Code reads neither the project's settings files nor its `.mcp.json`", P); `--bare`; or `--settings '{"disableAllHooks": true}'`, which also disables hooks from `--settings` itself (SR: outside managed settings it "disables user, project, local, and plugin hooks"), so it cannot be combined with injected hooks. `disableAllHooks` is read "after settings precedence applies, so a `"disableAllHooks": false` in a project's `.claude/settings.json` overrides a `true` in your user settings" (H).

Other configuration facts: settings files are watched, and "Direct edits to hooks in settings files are normally picked up automatically by the file watcher" (H); each detected change fires `ConfigChange`, which can block it (S, H). Interactive sessions hold back every settings-file hook, including `~/.claude/settings.json`, until the workspace trust dialog is accepted (H, "Workspace trust"). `allowManagedHooksOnly` (managed) blocks user, project, local and plugin hooks (H). Structure: `hooks` → event name → array of `{ "matcher", "hooks": [handler...] }` groups (SR). `/hooks` is a read-only browser of configured hooks (H).

### 4.7 Matcher syntax, timeout, async

**Matcher** (H, "Matcher patterns"):

| Matcher value | Evaluated as |
|---|---|
| `"*"`, `""`, or omitted | match all |
| only letters, digits, `_`, `-`, spaces, `,`, `\|` | "Exact string, or list of exact strings separated by `\|` or `,` with optional surrounding whitespace" (`,` and whitespace tolerance v2.1.191+; hyphens in the exact set v2.1.195+) |
| any other character | "JavaScript regular expression, unanchored", tested with `RegExp.prototype.test`; anchor with `^...$` for whole-string matches |

Matchers are case-sensitive (G). `FileChanged` and `StopFailure` use a narrower exact set (letters, digits, `_`, `|`). A `matcher` on an event without matcher support "is silently ignored". What each event matches on is in the section 3 table; for tool events it is `tool_name`, and MCP tools match as `mcp__<server>__<tool>` (`mcp__memory__.*` for a whole server; `mcp__memory` alone matches nothing). Tool events additionally accept a per-handler `if` field holding exactly one permission rule, such as `"Bash(git *)"` or `"Edit(*.ts)"`; on other events "a hook with `if` set never runs"; the Bash `if` match is best-effort and runs the hook when the command cannot be analysed.

**Handler fields** (H, "Hook handler fields"): `type` (`command`, `http`, `mcp_tool`, `prompt`, `agent`), `if`, `timeout`, `statusMessage`, `once` (skill frontmatter only). Command hooks: `command`, `args` (exec form: no shell, `${CLAUDE_PROJECT_DIR}` substituted as a plain string), `async`, `asyncRewake`, `shell`. Shell form runs `sh -c` on macOS/Linux. HTTP: `url`, `headers`, `allowedEnvVars`. MCP tool: `server`, `tool`, `input`. Prompt/agent: `prompt` with `$ARGUMENTS`, `model`, and for prompt hooks `continueOnBlock`.

**Timeout** (H, "Common fields"): "Seconds before canceling. Claude Code doesn't enforce it on a command hook you run with `async: true`. Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`. Claude Code lowers the `command`, `http`, and `mcp_tool` default to 30 on `UserPromptSubmit`, `PreModelSwitch`, and `PostModelSwitch`, and to 10 on `MessageDisplay`. `SessionEnd` hooks share a 1.5-second budget; if your settings set a longer per-hook `timeout`, Claude Code raises the budget to match, up to 60 seconds". Effect of a timeout: section 2.

**Async** (H, "Run hooks in the background"): `"async": true` is "only available on `type: "command"` hooks". "Async hooks can't block or control Claude's behavior: response fields like `decision`, `permissionDecision`, and `continue` have no effect". "After the background process exits, Claude Code delivers the `additionalContext` and `systemMessage` fields from the hook's JSON response to Claude on the next conversation turn. Unlike a synchronous hook's `systemMessage`, neither field is shown to you." "If the session is idle, the response waits until the next user interaction. Exception: an `asyncRewake` hook that exits with code 2 wakes Claude immediately even when the session is idle" — `asyncRewake: true` "runs in the background and wakes Claude on exit code 2. The hook's stderr, or stdout if stderr is empty, is shown to Claude as a system reminder"; `timeout` is still enforced for `asyncRewake`. "In non-interactive mode with the `-p` flag, Claude Code kills any async hook still running at teardown and finalizes it with outcome `cancelled`." Completion notifications are hidden unless verbose. Separately, the lifecycle diagram classes `WorktreeCreate`, `WorktreeRemove`, `Notification`, `ConfigChange`, `InstructionsLoaded`, `CwdChanged`, `FileChanged`, `DirectoryAdded` and `PostModelSwitch` as standalone async events, and `DirectoryAdded` "runs in the background" by design.

**Debugging** (H, "Debug hooks"): `claude --debug` writes `~/.claude/debug/<session-id>.txt` (nothing to the terminal); `claude --debug-file <path>`; `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` adds matcher counts. `claude --debug-file <path> --init-only` confirms Setup/SessionStart hooks ran.

## 5. Not verified

- `idle_prompt` inside a detached `--bg` session (4.5).
- Behaviour of `Stop`, `SessionEnd`, `Notification` and `terminalSequence` inside `--bg` sessions beyond what 4.5 quotes; the `SessionEnd` `reason` on `claude stop`.
- The `SessionEnd` `reason` reported when a `-p` run ends normally.
- Whether a `hooks` block inside a `--settings` file runs under `--bare` (the flag "skip[s] auto-discovery of hooks" and lists `--settings` as an explicit context source; the combination is not described).
- Whether `--settings` survives a `--setting-sources` filter (4.6).
- The transport of a Stop `reason` (user turn versus system reminder); the docs only call it an instruction and place it "at the end of the turn".
- Whether a Stop-hook continuation counts as an agentic turn for `--max-turns`.

## 6. Local observations (`claude --help`, 2.1.268)

- Lists `--settings <file-or-json>` ("Path to a settings JSON file or a JSON string to load additional settings from"), `--setting-sources <sources>`, `--bg, --background`, `-p, --print` ("Settings files that fail validation are silently ignored in this mode"), `--include-hook-events`, `--permission-prompts <target>`, `--restricted` ("ignores user, project and local settings files (managed settings and --settings still apply)"), `--bare` ("skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery"), `--safe-mode` (hooks among the customizations disabled), `--debug`, `--debug-file`, `--session-id`, `--resume`, `--continue`, `--fork-session`, `--no-session-persistence`, `--max-budget-usd`, and the commands `agents`, `attach`, `logs`, `stop|kill`, `rm`, `respawn`.
- Does not list `--init-only`, `--init`, `--maintenance`, `--max-turns`, `--exec`, or `--permission-prompt-tool` as options (the last appears only inside the `--permission-prompts` description), although C and H document them. Whether 2.1.268 accepts them as hidden options is unverified; nothing was run to test it.
- `~/.claude/settings.json` on this machine has no `hooks` key; neither `/Users/danny/Documents/Apps/Reclaim/.claude/settings.json` nor `/Users/danny/Documents/Apps/Baton/.claude/settings.json` exists.
