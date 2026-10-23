# T06: Verify the Linux release bundle

## Procedure

1. On `x86_64-linux`, build the bundle with `nix build .#releaseBundle --out-link result`.
2. Run `perl scripts/verify-release-bundle.pl result` and `perl scripts/test-release-pty.pl result`.
3. Set `scratch=$(mktemp -d)`, create `"$scratch/copied-bundle"`, resolve the `result` symlink to its bundle directory, and copy the bundle contents into `copied-bundle`.
4. Create temporary `HOME` and `TMPDIR` paths inside `scratch`. In an `env -i` environment with those paths, `PATH=/usr/bin:/bin`, and `TERM=xterm`, run `"$scratch/copied-bundle/bin/nshell" --version`.
5. Run `perl scripts/test-release-pty.pl "$scratch/copied-bundle"` and confirm a marker command succeeds.

## Pass condition

The bundle verifier and both PTY checks succeed. The copied executable starts without the source tree or developer environment, and the marker command runs. Record the bundle output path and verifier results with the release candidate.
