# Reaching a person away from the Mac — Claude Code 2.1.268

Research for ticket 06 (`.scratch/baton/issues/06-reaching-you-away-from-the-mac.md`).
Date: 2026-09-11. Sources are the official Claude Code documentation, Apple documentation,
and read-only inspection of this machine. No Claude session was started, stopped, attached
to or resumed. Anything not confirmed by a cited document or a local check is marked
**unverified**.

## Machine facts (verified locally, read-only)

| Fact | Value | How checked |
|---|---|---|
| Claude Code | 2.1.268 at `/Users/danny/.local/bin/claude` | `claude --version` |
| macOS | 27.0 (build 26A5421a) | `sw_vers` |
| Login | `loggedIn: true`, `authMethod: claude.ai`, `subscriptionType: max`, `apiProvider: firstParty` | `claude auth status` |
| `DISABLE_TELEMETRY` | `export DISABLE_TELEMETRY=1` at `/Users/danny/.zshrc:10`; present in the shell environment | grep of rc files; `auth status` reports `analyticsDisabled: true` |
| Other Remote Control blockers (`DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, Bedrock/Vertex flags) | all unset | shell env |
| `~/.claude/settings.json` | `env` block holds only `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; none of `preferredNotifChannel`, `agentPushNotifEnabled`, `inputNeededNotifEnabled`, `remoteControlAtStartup`, `disableRemoteControl`, `dialogExpiry`; no `Notification` hook in user or Baton project settings | grep |
| Claude desktop app | `/Applications/Claude.app`, version 1.52386.0 | `ls`, `defaults read` |
| `terminal-notifier` | not installed | `which` |
| `osascript`, `shortcuts` | `/usr/bin/osascript`, `/usr/bin/shortcuts`; `/System/Applications/Shortcuts.app` present | `which`, `ls` |
| Shortcuts on this Mac | `shortcuts list` returns 0 shortcuts | `shortcuts list` |
| Messages scripting | `send` command takes text or file, `to` a `participant` (synonym `buddy`) or a `chat`; service types `SMS`, `iMessage`, `RCS` | `sdef /System/Applications/Messages.app` |
| Mail scripting | `outgoing message` class and `send` command exist | `sdef /System/Applications/Mail.app` |
| `display notification` | parameters: body text, `with title`, `subtitle`, `sound name` — nothing else | `sdef /System/Library/ScriptingAdditions/StandardAdditions.osax` |

## Summary: what each channel gives a phone

| Channel | Reaches a phone | Person can act | Needs | Cost |
|---|---|---|---|---|
| Remote Control + Claude app push | Yes: push on the phone, full transcript in the Claude app / claude.ai/code | **Yes** — answer permission prompts and `AskUserQuestion`, send messages, stop a turn, change model/effort/permission mode | claude.ai login on Pro/Max (met), `DISABLE_TELEMETRY` unset for that process (currently set), the Claude iOS/Android app signed in, an interactive session (not `-p`), the `claude` process kept running, outbound HTTPS to `api.anthropic.com` | Included in the plan; no separate charge documented |
| Channels: official iMessage plugin | Yes: an iMessage in the self-chat, plus permission prompts relayed as text | **Yes for tool approvals** — reply `yes <id>` / `no <id>`; `AskUserQuestion` relay not documented | Bun runtime, the `imessage@claude-plugins-official` plugin, Full Disk Access and Automation permission for the terminal, Messages signed in, session started with `--channels` (research preview) | Free |
| iMessage via `osascript` → Messages | Yes: message appears on every device with Messages in iCloud; whether iOS *alerts* for a message sent to yourself from another device is **unverified** | No (one-way) | Messages signed in to iMessage on the Mac, one-time Automation approval for the calling app | Free |
| Mail via `osascript` → Mail.app | Yes, as ordinary email push on the phone's mail client | No (one-way) | Mail.app with a configured sending account (**unverified** on this Mac) | Free |
| `osascript -e 'display notification'` | No: Mac Notification Center only | No: no buttons, no reply field | Script Editor allowed in Notifications settings | Free |
| Shortcuts `Show Notification` via `shortcuts run` | No: Mac-local | No | A shortcut built in the Shortcuts app (none exist on this Mac) | Free |
| Shortcuts `Send Message` via `shortcuts run` | Yes, via Messages (same delivery caveats as iMessage above) | No (one-way) | A shortcut built in the Shortcuts app; silent send depends on a "Show When Run" toggle that is **unverified** (community-reported only) | Free |
| Terminal bell / `preferredNotifChannel` | No | No | — | Free |
| Claude desktop app | Only for sessions the desktop app runs itself; a CLI session is invisible to it unless moved in with `/desktop` | Via Remote Control on a desktop session; Dispatch pushes "needs your go-ahead" to the phone, approval-from-phone **unverified** | Desktop app running (present, 1.52386.0) | Included in the plan |

## 1. Remote Control

Source: https://code.claude.com/docs/en/remote-control (all quotes in this section unless noted).

### What it is

"Remote Control connects claude.ai/code or the Claude app for iOS and Android to a Claude
Code session running on your machine." "Claude keeps running locally the entire time, so your
code execution and filesystem access stay on your machine." "The web and mobile interfaces
are a window into that local session." Filesystem, MCP servers, tools and project
configuration stay available; the conversation stays in sync across terminal, browser and
phone; photos and files can be attached from the phone.

### Flags and commands (verified against `claude --help`)

- `--remote-control [name]` (alias `--rc`): "Start an interactive session with Remote Control
  enabled (optionally named)". Docs: "a full interactive session in your terminal that you can
  also control from claude.ai or the Claude app."
- `--remote-control-session-name-prefix <prefix>`: "Prefix for auto-generated Remote Control
  session names (default: hostname)", producing names like `myhost-graceful-unicorn`. Env
  equivalent `CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX`.
  (CLI reference: https://code.claude.com/docs/en/cli-reference)
- `claude remote-control` (server mode): the process "stays running in your terminal in
  server mode, waiting for remote connections", shows a session URL and (spacebar) a QR
  code; flags `--name`, `--spawn same-dir|worktree|session`, `--capacity N` (default 32),
  `--[no-]create-session-in-dir`, `--permission-mode`, `--continue`, `--session-id`. Flags
  placed *before* `remote-control` are not carried into the sessions it creates and most
  make it refuse to start. First run asks `Enable Remote Control? (y/n)` once.
- `/remote-control` (alias `/rc`) inside a running session: "starts a Remote Control session
  that carries over your current conversation history." First use shows a one-time
  **Enable Remote Control** confirmation dialog.
- `remoteControlAtStartup: true` in `~/.claude/settings.json`: "connect automatically when
  each interactive session starts"; a `true` in project/local settings is ignored; a `false`
  there turns it off. `/config` label: **Enable Remote Control for all sessions**.
  (https://code.claude.com/docs/en/settings-reference#remotecontrolatstartup)
- `disableRemoteControl: true` refuses all of the above.

Session title order: name passed to `--name`/`--remote-control`/`/remote-control`, then
`/rename`, then the last meaningful message, then the auto-generated `<prefix>-adjective-noun`.

### Driven from a phone

Yes. "Open claude.ai/code or the Claude app and find the session by name in the session
list. In the Claude mobile app, tap **Code** in the navigation to reach the session list.
Remote Control sessions show a computer icon with a green status dot when online." Or scan
the QR code, or open the session URL. `/mobile` prints an app-download QR code.
Mobile page: https://code.claude.com/docs/en/mobile — "a client for Claude Code sessions
rather than a place where code runs".

### Permission prompts and AskUserQuestion from the phone

Yes, both.

- Limitations section: "Claude Code keeps permission prompts and `AskUserQuestion` questions
  open until you answer them." Other forwarded dialogs (for example the model-choice prompt
  after a safety refusal) close after `dialogExpiry` (default `"5m"`; `"60s"`, `"10m"`,
  `"never"`); the settings reference confirms "Permission prompts and `AskUserQuestion`
  questions use their own flows and aren't governed by this deadline."
  (https://code.claude.com/docs/en/settings-reference#dialogexpiry)
- "While the connection is rebuilding, Claude Code queues messages, permission prompts, and
  status updates ... and delivers them once the connection recovers."
- A terminal reminder titled **Approve tool calls from your phone** appears after repeated
  permission prompts.
- Push: `inputNeededNotifEnabled` — "Get a push notification on your phone when a permission
  prompt or question is waiting for your input. Claude Code sends these only while Remote
  Control is connected." `/config` label **Push when actions required**. Default `false`.
  `agentPushNotifEnabled` — push "when it decides one is worth sending, for example when a
  long task finishes"; `/config` label **Push when Claude decides**; default `false`. Both
  require the Claude mobile app signed in with the same account and OS notification
  permission; `/config` shows **No mobile registered** until the app has registered a push
  token. (https://code.claude.com/docs/en/settings-reference#inputneedednotifenabled,
  #agentpushnotifenabled; https://code.claude.com/docs/en/remote-control#mobile-push-notifications)
- Pushes are skipped "while you are typing in or focused on the connected terminal";
  `CLAUDE_CLIENT_PRESENCE_FILE=<path>` extends the skip to any time the file exists (v2.1.181+).
- Permission modes selectable from the app for a Remote Control session: Manual, Accept
  edits, Plan. Not Bypass permissions, not Auto. (https://code.claude.com/docs/en/mobile#limitations)
- Commands that work from the phone: `/compact`, `/clear`, `/context`, `/usage`, `/exit`,
  `/model <name>`, `/effort <level>`, `/fast`, `/rename`, `/mcp`, `/config key=value`,
  `/autocompact`, `/advisor`. Local-only: `/plugin`, `/resume`, `/reload-plugins` (needs an
  interactive terminal).
- The Fable usage-credits consent prompt is *not* forwarded: "When the session runs in a
  terminal and nobody there answers before Claude Code closes the prompt, the turn ends
  without sending the request."

### Combination with `--bg`

**Not documented either way** — unverified.

- `--bg` "Start the session in the background and return immediately" (`claude --help`);
  background sessions are interactive sessions run by a supervisor process, so "you can close
  agent view, close your shell, or start a new interactive session and your dispatched work
  keeps going" (https://code.claude.com/docs/en/agent-view). That page contains no mention
  of Remote Control, the phone, or claude.ai (checked by search of its text).
- The only documented flag conflict is `--bg` with `-p`/`--print`
  (https://code.claude.com/docs/en/errors, "`--bg` and `--print` conflict"; agent-view:
  "Claude Code rejects `--bg` combined with `-p` or `--print` before any session is created,
  because `--print` never starts the interactive session that `claude agents` attaches to").
- One sentence on the Remote Control page implies a Remote Control session can be a
  background one: a rename from the phone is applied "to the session name shown on the prompt
  bar, and in the `claude agents` listing when the session runs in the background."
- The changelog through 2.1.268 has no entry pairing Remote Control with `--bg`
  (https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md).
- What would settle it: in a scratch directory, `claude --bg --remote-control test` and check
  whether the session appears at claude.ai/code with a green dot; then `claude attach <id>`
  and `/remote-control` for the switch-on-later case. Not run here (no sessions started).

### Combination with `-p` / headless

Remote Control is tied to an interactive session (`--remote-control` "starts an interactive
session"; `/remote-control` is a slash command). No document mentions Remote Control with
`-p`. In `-p` mode the only path for a person to answer a permission prompt or
`AskUserQuestion` is a permission host: "an Agent SDK app with a `canUseTool` callback, or an
MCP tool you pass with `--permission-prompt-tool`. Without the flag, your run waits for that
host to answer each permission request." With `--permission-prompts none` "Claude Code removes
the tools that need an answer from a person, such as `AskUserQuestion`". In "a `-p` run with
no host, these requests are denied either way."
(https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs)
Baton driving sessions headless therefore has no phone path unless Baton is itself the host.

### What it needs

- **Subscription and login**: "available on Pro, Max, Team, and Enterprise plans. API keys are
  not supported." Long-lived tokens from `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN`
  "can only make model requests, so they can't establish Remote Control sessions." This
  Mac: claude.ai login, Max — eligible.
- **Feature-flag evaluation**: "`DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, and `DISABLE_GROWTHBOOK` each disable the
  feature-flag evaluation that Remote Control availability depends on. Unset the variable
  wherever it's set, in your shell environment or in the `env` block of a `settings.json`
  file, to use Remote Control." This Mac exports `DISABLE_TELEMETRY=1` in `~/.zshrc:10`, so
  any session launched from a login shell fails Remote Control with "Remote Control requires
  feature-flag evaluation" until the variable is absent from that process's environment.
  `claude doctor` "Run `claude doctor` to see which individual eligibility check failed"
  (not run here).
- **API endpoint**: `api.anthropic.com` only; no gateway/proxy `ANTHROPIC_BASE_URL`, no
  Bedrock/Vertex/Foundry. Met.
- **Workspace trust**: "run `claude` in your project directory at least once to accept the
  workspace trust dialog"; never start from the home directory.
- **Network**: "outbound HTTPS requests only and never opens inbound ports on your machine";
  "registers with the Anthropic API and polls for work"; "requires access to the Anthropic API
  on port 443". Extended outage: interactive sessions keep retrying and reconnect; server mode
  gives up after ~10 minutes. "if your laptop sleeps or your network drops, Claude Code
  reconnects automatically when your machine comes back online."
- **The desktop app is not required**: CLI or VS Code extension start it; the desktop app has
  its own toggle (**Settings > Claude Code > Enable remote control by default**).
- **Local process must keep running**: "If you close the terminal, quit VS Code, or otherwise
  stop the `claude` process, the session goes offline ... To keep a session running on a
  remote machine after you disconnect from SSH, start it inside `tmux` or `screen`."
- **Data**: "While Remote Control is connected, the session transcript, including your
  messages, Claude's responses, and tool activity, is stored on Anthropic servers."
- **Trusted Devices** (device enrolment, 18-hour re-auth): Team and Enterprise only; not
  applicable on Max.

### Switching it on for a session that is already running

Yes, from inside the session: `/remote-control [name]` "carries over your current
conversation history"; the `/rc active` indicator and `/remote-control` status panel
(session URL, QR code, disconnect) follow. From *outside* the session there is no documented
control. Resuming the conversation in a second terminal "leaves Remote Control off there
instead of taking the session away from the first"; `/remote-control` in the second terminal
moves it. For a `--bg` session, `claude attach <id>` then `/remote-control` is the plausible
route — unverified.

### Cost

No separate price is documented; "available on all plans" gated by subscription. Push
notifications have no documented cost.

## 2. Notifications from a script without third-party packages

### 2.1 `osascript -e 'display notification ...'`

Apple: https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/DisplayNotifications.html
— "Notifications are shown as alerts or banners, depending on the user's settings";
parameters `with title`, `subtitle`, `sound name`; "Clicking the Show button in an
alert-style notification opens the app that displayed the notification."

Limits (verified from the StandardAdditions dictionary): the command accepts only the body
text, `with title`, `subtitle` and `sound name`. There is no parameter for action buttons,
a reply field, a URL, or a callback, and the command returns nothing. It is Mac Notification
Center only; Apple's Notifications settings guide
(https://support.apple.com/guide/mac-help/mchl205da693/mac) lists no option to forward Mac
notifications to an iPhone (negative result — no such Apple document was found).

Permission: "`osascript` routes notifications through the built-in Script Editor app. If
Script Editor doesn't have notification permission, the command fails silently, and macOS
won't prompt you to grant it. Run this in Terminal once to make Script Editor appear in your
notification settings: `osascript -e 'display notification "test"'`"
(https://code.claude.com/docs/en/hooks-guide#get-notified-when-claude-needs-input). The
official example for a `Notification` hook is
`osascript -e 'display notification "Claude Code needs your attention" with title "Claude Code"'`.

### 2.2 Shortcuts

- Command line: `shortcuts run "<name>"`, `shortcuts list`, exit `0`/`1`. "Although you can
  run nearly any shortcut from the command line, the most efficient shortcuts are ones that
  don't show alerts or ask for input. When a shortcut asks for input, the command line process
  pauses, awaiting user input."
  (https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac)
  `man shortcuts`: "To create or edit a shortcut, use the Shortcuts application" — a
  shortcut cannot be authored from a script. This Mac has none (`shortcuts list` → 0).
- **Show Notification** action: "creates a system notification" with title, text and rich
  preview; runs instantly. Mac-local, same reach as `display notification`.
  (https://support.apple.com/guide/shortcuts-mac/use-the-show-notification-action-apd2175adcab/mac)
- **Send Message** action: Apple's Mac guide names it only in the intro example ("Send
  Message automatically sends the GIF to your recipients",
  https://support.apple.com/guide/shortcuts-mac/intro-to-shortcuts-apdf22b0444c/mac). No
  Apple page documents its parameters. Community threads describe a per-action **Show When
  Run** toggle that, when off, sends without opening Messages, and report cases where
  Messages still opened for confirmation — **unverified**
  (https://discussions.apple.com/thread/256119828, https://discussions.apple.com/thread/8555597).
  Delivery to the phone then has the same properties as the iMessage path in §3.1.
- **Automations on Mac**: the Shortcuts User Guide for Mac table of contents (version 7.0,
  macOS 26, https://support.apple.com/guide/shortcuts-mac/toc) contains no automation
  entries (checked by text search on 2026-09-11). Third-party guides describe an Automation
  sidebar with triggers such as time of day, folder changes, app launch, message and email
  in macOS 26 (https://macmost.com/an-introduction-to-shortcuts-automation-in-macos-tahoe.html)
  — **unverified** against Apple documentation. A Folder trigger watching a file Baton
  writes would be the relevant shape if it exists.

### 2.3 The Claude desktop app

Source: https://code.claude.com/docs/en/desktop.

- Terminal sessions are not visible in the desktop app: "Claude sees only the sessions the
  desktop app runs itself: local, SSH, and WSL sessions in the Code tab. Claude doesn't see
  cloud sessions, or sessions you started from the terminal CLI or the VS Code extension".
  So a CLI-started Baton session and its prompts do not appear there.
- `/desktop` in a terminal session "saves your session and opens it in the desktop app, then
  exits the CLI" (macOS and x64 Windows, claude.ai subscription).
- "The desktop app sends an OS notification when a Code session finishes a task and you
  aren't currently viewing that session." Mac-local.
- Desktop sessions can carry Remote Control (toggle **Enable remote control by default**;
  changelog 2.1.261 "Remote Control clients that join a Claude Desktop or VS Code session").
- **Dispatch** (Cowork tab, Pro/Max): a task messaged from the phone can spawn a desktop
  Code session; "You get a push notification on your phone when it finishes or needs your
  approval." The help article (https://support.claude.com/en/articles/13947068) says "You'll
  get a push notification on your phone when a task is done or when Claude needs your
  go-ahead"; whether the go-ahead can be given from the phone is not stated —
  **unverified**. Requires the desktop app open and the machine awake. Sessions are created
  by Dispatch, not by a script, so this does not fit a Baton-launched session.

### 2.4 Claude Code's built-in notification settings and hook

- `preferredNotifChannel` (`/config` **Local notifications**): `"auto"` (default; desktop
  notification in iTerm2, Ghostty, Kitty; bell in Terminal.app only when its audible bell is
  off; nothing elsewhere), `"terminal_bell"`, `"iterm2"`, `"iterm2_with_bell"`, `"kitty"`,
  `"ghostty"`, `"notifications_disabled"`.
  (https://code.claude.com/docs/en/settings-reference#preferrednotifchannel) All Mac-local.
  Inside tmux, `set -g allow-passthrough on` is needed for these to reach the outer terminal
  (https://code.claude.com/docs/en/terminal-config#configure-tmux).
- `Notification` hook (the hooks ticket owns the design; the facts a script needs are here):
  input JSON carries `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `message`,
  `title`, `notification_type`. Types and timing: `permission_prompt` — "the prompt has waited
  about six seconds" with no typing; `idle_prompt` — "Claude finished responding about 60
  seconds ago and you haven't typed since"; `agent_needs_input` / `agent_completed` — a
  background session waiting or finishing, "only while agent view is open in a terminal";
  `elicitation_*`, `auth_success`, `quota_auto_resume_*`. "Notification hooks can't block or
  modify notifications ... intended for side effects such as forwarding the notification to
  an external service." Hooks fire even with `notifications_disabled`.
  (https://code.claude.com/docs/en/hooks#notification) There is no notification type
  specific to `AskUserQuestion`; a question ends the turn, so `idle_prompt` is the type that
  follows it — inference, **unverified**.
- Mobile push (`agentPushNotifEnabled`, `inputNeededNotifEnabled`) is the only built-in
  channel that leaves the Mac, and it works only while Remote Control is connected (§1).

## 3. What reaches a phone with nothing installed

### 3.1 iMessage via `osascript` to Messages

- Dictionary (verified): `send <text | file> to <participant | chat>`; participants have
  `handle`, `account`; accounts have a `service type` of `SMS`, `iMessage` or `RCS`.
- Form used by Anthropic's own iMessage plugin (server.ts, verified):
  `tell application "Messages" to send (item 1 of argv) to chat id (item 2 of argv)`, run as
  `osascript - <text> <chatGuid>` with the chat GUID read from `~/Library/Messages/chat.db`.
  Its README: "The first outbound reply triggers an **Automation** permission prompt
  ('Terminal wants to control Messages'). Click OK." and "AppleScript can send messages but
  not tapback, edit, or thread".
  (https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/external_plugins/imessage/README.md)
- Sending to a handle instead of a chat, e.g.
  `tell application "Messages" to send "…" to participant "+15551234567" of account 1`,
  is the dictionary's other addressing form; not executed here — **unverified** on macOS 27.
- Needs: Messages signed in — "sign in to your Apple Account, turn on iMessage, and set up
  iCloud for Messages" (https://support.apple.com/guide/messages/icht35827/mac); a one-time
  Automation approval for the app that owns the calling process
  (https://support.apple.com/guide/mac-help/mchl108e1718/mac; managed under System Settings >
  Privacy & Security > Automation, https://support.apple.com/guide/mac-help/mchl07817563/mac).
  Which app the prompt names when Baton, rather than Terminal, spawns `osascript` depends on
  the process's responsible app — **unverified**. Whether Messages is signed in on this Mac
  was not checked.
- Reaches the phone: with Messages in iCloud, "if you send, receive, or delete a message on one
  device, those updates appear everywhere"
  (https://support.apple.com/guide/icloud/what-you-can-do-with-icloud-and-messages-mma17ed475f7/icloud;
  Mac setup: https://support.apple.com/guide/messages/use-messages-in-icloud-icht5b5d1e63/mac).
  A message sent to the person's own handle therefore shows in the self-chat on the phone.
  Whether iOS raises a banner/sound for a message the same account *sent* from another
  device is **unverified**; no Apple document found states it either way. Sending to a
  handle the Mac account does not own (a second phone number or address) would arrive as an
  incoming message — **unverified**.
- Act: no. The message is one-way. Two-way iMessage requires the channel plugin below.
- Cost: none.

### 3.2 Two-way iMessage: the official `imessage` channel plugin (not "nothing installed")

Source: https://code.claude.com/docs/en/channels, https://code.claude.com/docs/en/channels-reference.

- "The iMessage channel reads your Messages database directly and sends replies through
  AppleScript. It requires macOS and needs no bot token or external service." Each plugin
  "requires Bun". Install `/plugin install imessage@claude-plugins-official`, grant Full Disk
  Access to the terminal (for `chat.db`), restart with
  `claude --channels plugin:imessage@claude-plugins-official`, then "Text yourself" — the
  self-chat "bypasses access control". A self-chat must already exist ("Send yourself an
  iMessage to create one", server.ts).
- Permission relay: the plugin declares `claude/channel/permission` (server.ts line 554,
  verified; Telegram and Discord plugins likewise). "Relay covers tool-use approvals like
  `Bash`, `Write`, and `Edit`. Project trust and MCP server consent dialogs don't relay." The
  prompt arrives with a five-letter `request_id`, `tool_name`, `description`, `input_preview`;
  the reply `yes <id>` or `no <id>` is the verdict; "Both stay live: you can answer in the
  terminal or on your phone, and Claude Code applies whichever answer arrives first."
  `AskUserQuestion` is not mentioned anywhere in the channels reference — relay of questions
  is **not documented**.
- "Events only arrive while the session is open, so for an always-on setup you run Claude in
  a background process or persistent terminal." "When you run channels in non-interactive
  mode with `-p`, tools that need terminal input, such as multiple-choice questions and plan
  mode approval, are disabled so the session never stalls."
- Status: research preview; Pro/Max users "opt in per session with `--channels`"; the flag is
  not listed in `claude --help` (confirmed: absent from the 2.1.268 help output) but works.
- Cost: none beyond Bun (a third-party runtime) and the plugin.

### 3.3 Mail via `osascript` to Mail.app

- Dictionary (verified): `outgoing message` class and `send` command exist. The standard
  script shape is `make new outgoing message with properties {subject:…, content:…}`, add a
  `to recipient`, then `send` — not executed here, **unverified** on this Mac.
- Needs: Mail.app with a configured sending account (**unverified** on this Mac) and the same
  one-time Automation approval as Messages.
- Reaches the phone as an ordinary incoming email on whatever mail client the phone runs,
  with that client's push/fetch behaviour. A *draft* (unsent) reaches the phone only if the
  account syncs drafts (IMAP/iCloud) and the person opens the Drafts folder — **unverified**;
  sending is the reliable form.
- Act: no (one-way). Cost: none.

### 3.4 Nothing

`display notification`, the terminal bell, `preferredNotifChannel`, the Shortcuts
`Show Notification` action and the desktop app's OS notification all stop at the Mac.

## 4. Implications for an unattended Baton session

- The only documented path where the person both *hears* on the phone and *answers*
  a permission prompt or `AskUserQuestion` is Remote Control with `inputNeededNotifEnabled`
  on and the Claude app signed in. On this Mac it is blocked by `DISABLE_TELEMETRY=1` in
  `~/.zshrc` until the variable is absent from the session's environment; login and plan
  already qualify.
- Remote Control requires an interactive session; whether that includes `--bg` sessions is
  unverified (§1). Headless `-p` sessions have no phone path except a permission host that
  Baton itself provides.
- The channel plugin path (iMessage) answers tool approvals by text reply but needs Bun, a
  plugin, Full Disk Access, and `--channels` at session start; it does not document
  `AskUserQuestion` relay.
- Everything else is one-way: iMessage or Mail through `osascript` can carry the hook's
  `message`/`title`/`notification_type` to the phone, after which the person must reach the
  Mac (or a Remote Control link included in the message) to act.

## 5. Unverified items, collected

1. `claude --bg` together with `--remote-control` (or `/remote-control` after `claude attach`).
2. Remote Control eligibility on this Mac once `DISABLE_TELEMETRY` is unset (`claude doctor`
   not run).
3. iOS alert behaviour for an iMessage the same account sent to itself from the Mac.
4. `participant`-addressed `send` syntax on macOS 27; which app the Automation prompt names
   when Baton spawns `osascript`.
5. Mail.app account configuration on this Mac; draft sync to the phone.
6. Shortcuts automations on macOS 26/27 (absent from Apple's Mac guide TOC); the Send
   Message action's "Show When Run" behaviour.
7. Dispatch approval from the phone.
8. `AskUserQuestion` relay through channels (undocumented); `idle_prompt` as the hook type
   that follows a question.

## Sources

- https://code.claude.com/docs/en/overview
- https://code.claude.com/docs/en/remote-control
- https://code.claude.com/docs/en/cli-reference
- https://code.claude.com/docs/en/mobile
- https://code.claude.com/docs/en/agent-view
- https://code.claude.com/docs/en/errors
- https://code.claude.com/docs/en/headless
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/terminal-config
- https://code.claude.com/docs/en/settings-reference
- https://code.claude.com/docs/en/desktop
- https://code.claude.com/docs/en/channels
- https://code.claude.com/docs/en/channels-reference
- https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/external_plugins/imessage/README.md
- https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/external_plugins/imessage/server.ts
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- https://support.claude.com/en/articles/13947068
- https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/DisplayNotifications.html
- https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac
- https://support.apple.com/guide/shortcuts-mac/use-the-show-notification-action-apd2175adcab/mac
- https://support.apple.com/guide/shortcuts-mac/intro-to-shortcuts-apdf22b0444c/mac
- https://support.apple.com/guide/shortcuts-mac/toc
- https://support.apple.com/guide/messages/icht35827/mac
- https://support.apple.com/guide/messages/use-messages-in-icloud-icht5b5d1e63/mac
- https://support.apple.com/guide/icloud/what-you-can-do-with-icloud-and-messages-mma17ed475f7/icloud
- https://support.apple.com/guide/mac-help/mchl108e1718/mac
- https://support.apple.com/guide/mac-help/mchl07817563/mac
- https://support.apple.com/guide/mac-help/mchl205da693/mac
- Local: `claude --help`, `claude --version`, `claude auth status`, `man osascript`,
  `man shortcuts`, `sdef` of Messages.app, Mail.app and StandardAdditions.osax,
  `shortcuts list`, `ls /Applications`, `which terminal-notifier`, `~/.zshrc`,
  `~/.claude/settings.json`.
