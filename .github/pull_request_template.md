## Summary

<!-- What does this PR change, and why? -->

## User-visible effect

<!-- How does this change behavior for someone using nshell? -->

## Checklist

- [ ] Added or updated tests under `t/`
- [ ] `nix flake check` passes locally
- [ ] For OS-interactive changes, the non-sandboxed integration suite passes
- [ ] Tests are hermetic (no dependence on cwd, terminal size, or environment)
- [ ] Updated `CHANGELOG.md` under `[Unreleased]`
- [ ] Followed the layering in [docs/src/project/contributing.md](../docs/src/project/contributing.md) (domain has no I/O)

## Related issues

<!-- e.g. Closes #123 -->
