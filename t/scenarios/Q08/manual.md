# Q08: Preserve input state after a key-handler error

## Procedure

1. From the candidate repository root, create a disposable source copy, temporary homes, and a normal build:

   ```sh
   source_tree=$(pwd -P)
   scratch=$(mktemp -d)
   mkdir -p "$scratch/normal-home" "$scratch/debug-home"
   nix build . --out-link "$scratch/normal-result"
   mkdir "$scratch/source"
   tar --exclude=.git --exclude=.jj --exclude=.hg --exclude=.svn -C "$source_tree" -cf - . | tar -C "$scratch/source" -xf -
   ```

   In the copy's `src/presentation/repl.lisp`, temporarily make `%process-input-event` signal `Q08_TEST_CONDITION` immediately before its call to `reduce-input-state`, only when the event is `Ctrl-f`. Do not change `*input-state*` before signaling. Build with `nix build "path:$scratch/source" --out-link "$scratch/debug-result"` and run `"$scratch/debug-result/bin/nshell"`. Keep the injection out of the normal build.
2. Start the debug shell in a PTY with `env -i HOME="$scratch/debug-home" TERM=xterm-256color "$scratch/debug-result/bin/nshell" --no-config`. Type `echo Q08_`, press `Ctrl-f` once, and capture the diagnostic.
3. Type `OK` and press Enter. Check that nshell executes the intact line and prints `Q08_OK`.
4. Remove the temporary fault injection from the disposable copy after the check. Start the normal executable built in step 1 in a PTY with `env -i HOME="$scratch/normal-home" TERM=xterm-256color "$scratch/normal-result/bin/nshell" --no-config`, press `Ctrl-f`, and confirm it does not signal `Q08_TEST_CONDITION`.
5. Record the debug and normal results, then remove the scratch directory.

## Pass condition

The handler failure is contained and reported without exposing a debugger or structure dump. The input buffer and cursor remain valid, and the shell accepts and executes the marker command.
