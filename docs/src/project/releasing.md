# Releasing

nshell ships a binary as well as a source release, so its release checklist is
longer than the org default: a green test suite does not prove that the dumped
SBCL image starts on a user's machine.

## The invariant

The `:version` form in `nshell.asd` is the single source of truth. `flake.nix`
reads it, and `release.yml` refuses to publish a tag that disagrees with it.
Bump the `.asd` and nothing else.

## What CI enforces on a tag push

Pushing a `v*.*.*` tag runs `release.yml`, which:

1. Verifies the tag matches `nshell.asd`'s `:version`, and stops before
   building anything if it does not.
2. Runs `nix flake check --print-build-logs` against the tagged tree.
3. Builds the binary for `x86_64-linux` and `aarch64-darwin`, confirms each one
   starts, and packages a tarball plus a SHA-256 checksum.
4. Extracts the `## [X.Y.Z]` section from `CHANGELOG.md` as the release body,
   failing if that section is missing.

## Manual checklist before tagging

Verify the public artefacts from a clean checkout:

- `nix flake check --print-build-logs` passes on Linux and macOS.
- The non-sandboxed integration suite passes for PTY, subprocess, terminal,
  signal, and job-control coverage:

  ```sh
  nix develop --command sbcl --non-interactive \
    --eval '(require :asdf)' \
    --eval '(push (truename "./") asdf:*central-registry*)' \
    --eval '(asdf:test-system :nshell/test)'
  ```

- `nix build --print-build-logs` produces `./result/bin/nshell`.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the documentation
  and shipped behaviour.
- Release tarballs contain `nshell`, `README.md`, `LICENSE`, and the man page,
  and each checksum verifies with `shasum -a 256 -c`.
- `CHANGELOG.md` has a non-empty section for the release, and `[Unreleased]`
  makes no stale claims about already-shipped behaviour.

When triggering the workflow manually rather than by tag push, pass the tag as
the `tag` input so checkout, artefact naming, and the GitHub Release target all
use it consistently. Do not build a branch ref while publishing a tag release.
