# S04: Approve agent steps individually

## Procedure

1. Use a test provider configured to return `(^touch S04_FIRST)` and then `(^touch S04_SECOND)` as two separate steps.
2. Start the task in a temporary working directory. Verify the first proposal is displayed and the `S04_FIRST` file is absent before approval.
3. Press Enter to approve the first step. Verify that `S04_FIRST` exists, `S04_SECOND` is absent, and nshell presents the second step separately.
4. Press `s` to skip the second proposal. Verify that `S04_SECOND` remains absent and the shell returns to a usable prompt.

## Pass condition

Each proposed command is presented as its own approval decision. Approving one step does not execute a later step, and skipping the second leaves its side effect absent.
