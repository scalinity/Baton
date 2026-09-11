# Baton embeds no model call

Baton carries a build from one Claude Code session to the next, and the open question was whether
it should also judge: a long-lived Claude session as conductor, or a bounded model call at events.
Baton is a relay — deterministic code that runs once per tick and decides nothing a session or a
person should. The rule is one of placement, not of ceiling: **Baton embeds no model call.
Judgement is dispatched as a session and returns as an artifact; it is never made inline in the
tick.** A session is a model call with the whole project in context, a transcript a person can
attach to, the Stop gate, and an artifact at the end, so anything that needs judgement later — a
morning summary of the night, re-allocating models after a milestone lands, a fix when main breaks
after two lanes merge — is dispatched, not computed in the relay. Every design that seated a Claude
session as orchestrator reports needing nudges, waiting for input and misreporting state, and a
question that a session with the whole project in context still chose to ask is not one a smaller
call with less context answers better. What is left is the person's, answered by any means they
choose.

## Reversal condition

If the dispatch log shows the same judgement point recurring — one a session cannot pre-decide and
a person tires of answering — that is the named moment for a bounded model call inline in the
tick, and it gets its own ticket then.

## Consequences

- No quota is spent on supervision, and the relay is testable without an API key.
- A new need for judgement is met by a ruling in the kickoff prompt, a rule in the relay, or a
  dispatched session that returns an artifact — never by a model call in the tick.
