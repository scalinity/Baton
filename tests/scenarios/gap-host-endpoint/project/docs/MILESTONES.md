# Milestones

The smallest plan that leaves nothing to dispatch once M02 is done: M03 is the one milestone M02
unblocks, and an uncleared gate holds it. The scenario is about the tick's own clock at step 7, so
nothing it asserts should depend on what a dispatch would have written.

## Order and dependencies

| ID | Title | Depends on | Model | Effort | Remote | Status |
|---|---|---|---|---|---|---|
| M01 | Foundation | – | opus | | | done |
| M02 | The second | M01 | opus | high | | done |
| M03 | The third | M02 | opus | | | |

## Gates

| Gate | Holds | Cleared |
|---|---|---|
| v0.1 ships | M03 | |
