# Milestones

A plan that parses and makes nothing eligible: one milestone done, one held by hand, one waiting on
the held one, and one an uncleared gate holds. There is nothing for the precondition report to say,
and saying nothing is not the same as saying everything is ready.

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status | Real files changed? |
|---|---|---|---|---|---|---|---|
| M01 | Foundation | – | opus | | | done | No |
| M02 | Held by hand | M01 | opus | | | held | No |
| M03 | Waiting on the held one | M02 | opus | | | | No |
| M04 | Held by an uncleared gate | M01 | fable | | | | No |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| v1 ships | M04 | |
