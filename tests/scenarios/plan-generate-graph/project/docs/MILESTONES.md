# Milestones

Three milestones, one per fresh session. This file is the plan file: the table below is what
`baton plan Fixture` parses.

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status |
|---|---|---|---|---|---|---|
| M01 | Read the fixture note | – | opus | medium | | done |
| M02 | Say what the note said | M01, M09 | opus | medium | | |
| M00-plan | Write the plan over again | M02 | opus | medium | | |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| the note is approved | M02 | |

The gate above holds M02 until somebody approves the note.
