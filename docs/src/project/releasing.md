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

1. Resolves the tag to one commit, verifies every `nshell.asd` version matches,
   and stops before building anything if either check fails.
2. Runs `nix flake check --print-build-logs` against that resolved commit.
3. Builds and natively validates the portable bundle for `x86_64-linux` and
   `aarch64-darwin`, including launching it through a symlink, then packages
   each target reproducibly as a tarball with a SHA-256 checksum. CI creates
   the archive twice and requires byte-for-byte equality.
4. Waits for the complete set of target artifacts before publishing anything,
   re-resolves the remote tag to reject a tag moved after verification, and
   creates a GitHub artifact attestation for each tarball.
5. Extracts the `## [X.Y.Z]` section from `CHANGELOG.md` as the release body,
   failing if that section is missing.

## Manual checklist before tagging

Verify the public artefacts from a clean checkout:

- `nix flake check --print-build-logs` passes on Linux and macOS.
- The non-sandboxed integration suite passes for PTY, subprocess, terminal,
  signal, and job-control coverage:

  ```sh
  nix develop --command sbcl --script run-tests.lisp
  ```

- `nix build --print-build-logs` produces `./result/bin/nshell`.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the documentation
  and shipped behaviour.
- Release tarballs contain `bin/nshell`, the required runtime files under
  `lib/`, the applicable notices under `LICENSES/`, `README.md`, `LICENSE`, and
  the man page. Linux additionally contains `libexec/nshell` and its dynamic
  loader; Darwin runs the bundled executable directly from `bin/nshell`.
  Each checksum verifies with
  `shasum -a 256 -c`, and the complete target set passes validation before the
  publish job creates artifact attestations and the GitHub Release.
- `CHANGELOG.md` has a non-empty section for the release, and `[Unreleased]`
  makes no stale claims about already-shipped behaviour.

When triggering the workflow manually rather than by tag push, pass the tag as
the `tag` input so checkout, artefact naming, and the GitHub Release target all
use it consistently. Do not build a branch ref while publishing a tag release.
