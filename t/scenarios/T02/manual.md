# T02: Document `/etc/shells` registration

## Procedure

1. Read `docs/src/getting-started.md` and locate its login-shell setup instructions. If it has no such section, record that omission.
2. Use the candidate executable from an existing build or temporary profile. If building, use the host's package output (`aarch64-darwin` or `x86_64-linux`). Record its exact path and verify it with `--version`; do not change the account's login shell.
3. Compare the guide's example path and steps with that executable path. Confirm that the guide explains how an administrator can add the exact path to `/etc/shells` and how to verify the entry.
4. Review any `chsh` instruction and check that it uses the same path. Do not edit the system file or change the account shell during this documentation check.

## Pass condition

A reader can identify the executable, register its exact path in `/etc/shells`, and verify the entry before changing login settings. The guide does not require guessing a store path or running a command with an unrelated path.
