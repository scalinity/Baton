# Milestones

Six eligible milestones, one of them clean and five carrying defects a dispatch would refuse; plus
a done row, a held row, a waiting row and a row an uncleared gate holds, none of which the
precondition report may speak for.

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status | Real files changed? |
|---|---|---|---|---|---|---|---|
| M01 | Foundation | – | opus | | | done | No |
| M02 | Every precondition met | M01 | opus | high | | | No |
| M03 | A heading with no fenced block | M01 | opus | | | | No |
| M04 | Three independent defects | M01 | opus | | | | No |
| M05 | No brief at all | M01 | opus | | | | No |
| M06 | Held by hand | M01 | sonnet | | | held | No |
| M07 | Waiting on the held one | M06 | opus | | | | No |
| M08 | Held by an uncleared gate | M01 | fable | | | | No |
| M09 | A brief with no such heading | M01 | opus | | | | No |
| M10 | A brief on disk and not on main | M01 | opus | | | | No |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| v1 ships | M08 | |
