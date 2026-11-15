@AGENTS.md

## Claude Code specifics

- Start each session by reading `docs/design/README.md` and the task file you were asked to work on.
- Use plan mode for any task marked "規模 大" or touching more than one layer; show the plan before editing.
- Run the narrowest relevant check first. Require CI to pass the full suite before opening a PR.
- If the task branch has no PR, trigger CI with `gh workflow run ci.yml -R <owner>/<repo> --ref <branch>` and wait for it to finish.
- When a task is done, tick its checkbox in `docs/design/tasks/P*.md` in the same commit.
