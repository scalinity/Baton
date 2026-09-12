# Milestones

Prose before the table, with a table that is not the plan:

| Item | Note |
|---|---|
| a | not a plan table |

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status | Real files changed? |
|---|---|---|---|---|---|---|---|
| M01 | Foundation | – | opus | | | done | No |
| M02 | The second | M01 | opus | high | | | No |
| M03 | The third | M02 | claude-opus-5 | | | done | No |
| M04 | Release | M01–M03 | fable | max | | | No |
| M05 | Held by hand | M01 | sonnet | | | held | No |
| M06 | Remote one | M01-M02, M05 | haiku | low | yes | | No |
| M07 | Escaped pipe in a title \| still one cell | M01 | opus | | | | No |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| v0.1 ships | M04 | |
| cleared gate | M07 | D-003 |
