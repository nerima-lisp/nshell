# Releasing

nshell ships a binary as well as a source release, so its release checklist is
longer than the org default: a green test suite does not prove that the dumped
SBCL image starts on a user's machine.

The default Nix package and portable bundle use an uncompressed saved image.
This deliberately trades artifact size for lower warm-filesystem CLI startup
latency; compressed images are not a supported release variant.

## The invariant

The top-level `:version` form in `nshell.asd` is the release version source of
truth. Secondary systems repeat that version as ASDF metadata. `flake.nix`
reads it, and `release.yml` refuses to publish unless every `:version` form in
the file agrees with the tag. Bump every version in the `.asd` and nothing
else.

## What CI enforces on a tag push

Pushing a `v*.*.*` tag runs `release.yml`, which:

1. Verifies the tag matches `nshell.asd`'s `:version`, and stops before
   building anything if it does not.
2. Runs `nix flake check --print-build-logs` against the tagged tree.
3. Builds the binary for the `x86_64-linux` release target, confirms it
   starts, and packages a tarball plus a SHA-256 checksum. `aarch64-darwin` is
   also declared by `flake.nix` for development and platform-specific local
   checks, but is not a published binary target in this workflow.
4. Creates the GitHub Release as an empty **draft** with those files attached.
   It writes no release body: the GitHub Release description is the canonical
   history and there is no `CHANGELOG.md`.

## Manual checklist before tagging

Verify the public artefacts from a clean checkout:

- `nix flake check --print-build-logs` passes on `x86_64-linux`. On macOS, use
  the declared `aarch64-darwin` development environment and run the checks that
  are available for the pinned dependency set; some build checks may be
  unavailable when an upstream package has no Darwin build.
- The non-sandboxed integration suite passes for PTY, subprocess, terminal,
  signal, and job-control coverage:

  ```sh
  nix develop --command sbcl --script run-tests.lisp
  ```

- `nix build --print-build-logs` produces `./result/bin/nshell`.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the documentation
  and shipped behaviour.
- Release tarballs contain `nshell`, `README.md`, `LICENSE`, and the man page,
  and each checksum verifies with `shasum -a 256 -c`.
- Release notes are drafted. Read `git log <previous-tag>..HEAD` and select
  entries by "does a user of nshell have to change anything". After the
  workflow goes green, paste them in and publish the draft:

  ```sh
  gh release edit vX.Y.Z --notes-file <file> --draft=false
  ```

  A draft appears neither under "Latest release" nor in the default output of
  `gh release list`, so a release whose notes were forgotten never reaches
  downstream.

When triggering the workflow manually rather than by tag push, pass the tag as
the `tag` input so checkout, artefact naming, and the GitHub Release target all
use it consistently. Do not build a branch ref while publishing a tag release.
