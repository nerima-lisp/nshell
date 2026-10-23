# A03: Login shell startup

Use a disposable account because `chsh` changes that account's login shell.

Prerequisite: the test account can log in locally, the built nshell executable is available, and its exact path is already listed in `/etc/shells`. If the path is not listed or the account cannot select it, record the check as not run. Do not edit `/etc/shells` as part of this procedure.

1. Record the account's current login shell and the exact nshell executable path.
2. Run `chsh -s /absolute/path/to/nshell test-account` for the disposable account.
3. Log out and start a fresh login session as that account.
4. Run `printf 'A03_LOGIN_OK\n'`, then run `exit`.
5. Restore the account's original login shell with `chsh`.

Pass when the login starts in nshell, the command prints its marker, the session exits cleanly, and the original login shell is restored.
