# S02: Do not run a proposal before Enter

## Procedure

1. Use a temporary home and working directory with an authenticated test assistant provider or a test fixture configured to return exactly `(^touch S02_APPROVED)`.
2. Press `Ctrl-]`, enter a request for that command, and press Enter to submit the request.
3. When nshell displays the command proposal, verify that the `S02_APPROVED` file does not exist. Do not press Enter until this check is complete.
4. Press Enter to approve the proposal. If nshell asks for an additional confirmation, press Enter again to execute it, then verify that the marker file exists.

## Pass condition

The proposal has no side effect while it awaits approval. Enter approves it, and any requested confirmation is explicit before execution. Use only a disposable marker path.
