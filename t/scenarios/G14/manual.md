# G14: User key binding

This procedure checks the documented editing-action binding. G14 also lists optional Lisp-command bindings. Check the public help and documentation at the tested revision for a Lisp-command binding form. If one is documented, follow its documented setup to bind another key to a harmless zero-argument Lisp command that prints a unique marker, press that key from an empty prompt, and verify the marker appears. In a fresh `--no-config` session, verify the binding is absent. If no form is documented, record the optional Lisp-command binding as unsupported and do not infer syntax from private implementation details.

1. In an isolated session, run `bind ctrl-k` and record the default action.
2. Run `bind ctrl-k clear-input` to assign the key to a different documented editing action.
3. Type `touch G14_SHOULD_NOT_EXIST`, press `Ctrl-k`, then press Enter. Confirm the file was not created.
4. In a fresh `--no-config` session, run `bind ctrl-k` again and compare it with the recorded default action.

Pass the documented editing-action portion when the bound action clears the input without executing it and a fresh session without the binding retains the recorded default action. Pass the optional Lisp-command portion only when its documented form prints the marker and is absent from a fresh `--no-config` session; otherwise record it as unsupported.
