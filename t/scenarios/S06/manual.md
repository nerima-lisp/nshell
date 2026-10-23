# S06: Classify S-expression proposals

## Procedure

1. Use a temporary home and an authenticated test provider. Press `Ctrl-]`, request the exact harmless proposal `(^printf S06_SAFE_OK)`, and press Enter to submit the request.
2. Verify that nshell displays an executable safety classification. Press Enter to approve it and confirm that `S06_SAFE_OK` appears.
3. Create a temporary directory and a marker file inside it. Request a recursive delete of that exact marker directory, substituting its full temporary path into `(^rm -rf /temporary/test/path)`. Inspect the classification and stop the task without approving it. Never execute this proposal; if it runs accidentally, its target must be only the marker directory created for this check.

## Pass condition

The shell parses and classifies the harmless S-expression form, then executes it only after approval. It marks the scoped recursive-delete form as blocked before approval, does not run it, and leaves the marker file intact.
