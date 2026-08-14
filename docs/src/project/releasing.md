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

- `nix build .#releaseBundle --print-build-logs` produces the executable,
  man page, README, and dependency license texts in `./result`.
- `perl scripts/verify-release-bundle.pl result` checks the bundle's file
  manifest, store-reference hygiene, platform library closure, and smoke
  startup. Do not replace this with a check of the unbundled default package.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the documentation
  and shipped behaviour.
- Release tarballs contain `nshell`, `README.md`, `LICENSE`, the man page, and
  the `LICENSES/` directory produced by `releaseBundle`; each checksum
  verifies with `shasum -a 256 -c`.
- Release notes are drafted. Read `git log <previous-tag>..HEAD` and select
  entries by "does a user of nshell have to change anything". After the
  workflow goes green, paste them in and publish the draft:

  ```sh
  gh release edit vX.Y.Z --notes-file <file> --draft=false
  ```

  A draft appears neither under "Latest release" nor in the default output of
  `gh release list`, so a release whose notes were forgotten never reaches
  downstream.

## Updating locked dependencies

The scheduled `flake.lock` workflow updates the flake inputs and opens or
refreshes a pull request. For a manual refresh or review:

1. Inspect `git diff -- flake.lock` and confirm that only the intended
   dependency graph changed.
2. Run `nix flake check --print-build-logs` on Linux. On macOS, run the checks
   available for the pinned dependency set.
3. Keep the lock-file refresh separate from behaviour or release-version
   changes.

Merge a lock-file refresh only after reviewing the generated diff and the
check results, because the lock file is part of the release input.

When triggering the workflow manually rather than by tag push, pass the tag as
the `tag` input so checkout, artefact naming, and the GitHub Release target all
use it consistently. Do not build a branch ref while publishing a tag release.
