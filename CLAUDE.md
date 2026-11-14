@AGENTS.md

## Claude Code specifics

- Start each session by reading `docs/design/README.md` and the task file you were asked to work on.
- Use plan mode for any task marked "規模 大" or touching more than one layer; show the plan before editing.
- Run the narrowest tests first (the affected test file), then the full suite before opening a PR.
- When a task is done, tick its checkbox in `docs/design/tasks/P*.md` in the same commit.
