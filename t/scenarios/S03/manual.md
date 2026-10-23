# S03: Explain the previous failure

## Procedure

1. Start nshell interactively with an authenticated test assistant provider and a temporary home.
2. Run `false` and confirm the prompt indicates a failed command.
3. Press `Ctrl-]` at the next prompt to request an explanation of the last failure. Review the response and any suggested next step, then dismiss the panel without accepting a suggestion.
4. Confirm that no additional command ran and that the shell accepts a new harmless command.

## Pass condition

The explanation identifies `false` and its nonzero status. The shell returns to normal input after the panel is dismissed, and no suggestion executes without an explicit user action.
