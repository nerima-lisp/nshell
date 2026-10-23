# T01: Install with Nix on macOS and Linux

## Procedure

1. Use hosts for the Nix systems listed in `flake.nix`: `aarch64-darwin` and `x86_64-linux`. Choose either the candidate source tree or a published release flake reference that provides both systems, set `FLAKE_REF` to that choice, and use the same reference on both hosts.
2. Create a fresh temporary directory with `profile_dir=$(mktemp -d)` and set `profile="$profile_dir/profile"`.
3. Run `nix profile install --profile "$profile" "$FLAKE_REF#default"` from the source tree when `FLAKE_REF=.` or from any directory when it is a published reference.
4. Run `"$profile/bin/nshell" --version` and record its exit status and output on each host.
5. Record any conflict between the published support statement and the systems declared in `flake.nix` as a documentation mismatch.

## Pass condition

Installation exits successfully on both operating systems, the profile contains `bin/nshell`, and the installed command reports the package version. Keep the profile under the temporary directory.
