# Releasing

nshell ships a binary as well as a source release. A green source test suite
does not prove that the dumped SBCL image starts on a user's machine.

The default Nix package and portable bundle use an uncompressed saved image.
This deliberately trades artifact size for lower warm-filesystem CLI startup
latency; compressed images are not a supported release variant.

## The invariant

The top-level `:version` form in `nshell.asd` is the release version source of
truth. Secondary systems repeat that version as ASDF metadata. `flake.nix`
reads it, and `release.yml` refuses to publish unless every `:version` form in
the file agrees with the tag. Bump every version in the `.asd` and update the
man page's version label. No separate version file is needed.

## What CI enforces on a tag push

Pushing a `v*.*.*` tag runs `release.yml`, which:

1. Verifies the tag matches `nshell.asd`'s `:version`, and stops before
   building anything if it does not.
2. Runs `nix flake check --print-build-logs` against the tagged tree.
3. Runs the non-sandboxed integration suite, dependency suites, and history
   storage regressions against the same resolved tagged commit.
4. Builds the binary for `x86_64-linux` and packages a tarball plus a SHA-256
   checksum. It checks the checksum, re-extracts the archive, verifies its
   manifest and runtime closure, and exercises the extracted executable with
   a real PTY. No other platform is declared or published by the current flake.
5. Creates the GitHub Release as an empty **draft** with those files attached.
   It writes no release body: the GitHub Release description is the canonical
   history and there is no `CHANGELOG.md`.

## Manual checklist before tagging

Verify the public artefacts from a clean checkout:

The bundle checks require Perl, Python 3, `readelf`, and the standard POSIX
tools on the Linux verification host.

- `nix flake check --print-build-logs` passes on `x86_64-linux`. Other hosts
  require an `x86_64-linux` builder for the release gate.
- The non-sandboxed integration suite passes for PTY, subprocess, terminal,
  signal, and job-control coverage:

  ```sh
  NSHELL_TEST_PTY=1 nix develop -c sbcl --script run-tests.lisp
  NSHELL_TEST_PTY=1 nix develop -c bash scripts/test-dependencies.sh
  nix develop -c sbcl --script scripts/test-history-storage.lisp
  ```

- `nix build .#releaseBundle --print-build-logs` produces the executable,
  man page, README, and dependency license texts in `./result`.
- `perl scripts/verify-release-bundle.pl result` checks the bundle's file
  manifest, store-reference hygiene, platform library closure, and smoke
  startup. Do not replace this with a check of the unbundled default package.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the documentation
  and shipped behaviour.
- Package the built bundle using GNU tar and gzip, as the release workflow
  does. Replace `vX.Y.Z` with the intended tag:

  ```sh
  name="nshell-vX.Y.Z-x86_64-linux"
  mkdir -p "dist/$name"
  cp -R result/. "dist/$name/"
  nix shell --inputs-from . nixpkgs#gnutar nixpkgs#gzip --command \
    bash -euo pipefail -c 'tar --sort=name --mtime="@0" --owner=0 --group=0 \
      --numeric-owner -cf - -C dist "$1" | gzip -n > "dist/$1.tar.gz"' bash "$name"
  (cd dist && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
  (cd dist && shasum -a 256 -c "$name.tar.gz.sha256")
  ```

  The archive includes `bin/nshell`, `README.md`, `LICENSE`, the man page,
  and the dependency texts in `LICENSES/`.
- Extract the checked archive into a private temporary directory and verify
  the extracted bundle, using the same `name` as above:

  ```sh
  extracted="$(mktemp -d)"
  tar -xzf "dist/$name.tar.gz" -C "$extracted"
  perl scripts/verify-release-bundle.pl "$extracted/$name"
  perl scripts/test-release-pty.pl "$extracted/$name"
  ```

  The PTY check exercises editing, Ctrl-C, Ctrl-Z/`bg`/`fg`, history across
  restart, and terminal restoration. A source-loaded suite is not a substitute.
- Release notes are drafted. Review changes since the previous tag and describe
  user-visible features, fixes, and any required migration. After the
  workflow goes green, paste them in and publish the draft:

  ```sh
  gh release edit vX.Y.Z --notes-file <file> --draft=false
  ```

  A draft is not a public release. `gh release list` can show drafts to an
  authenticated maintainer; that listing does not establish publication.

## Updating locked dependencies

The scheduled `flake.lock` workflow updates the flake inputs and opens or
refreshes a pull request. To review that update:

1. Inspect `git diff -- flake.lock` and confirm that only the intended
   dependency graph changed.
2. Run `nix flake check --print-build-logs` and the non-sandboxed commands above
   on `x86_64-linux`. A macOS host alone cannot execute the release target.
3. Keep the lock-file refresh separate from behaviour or release-version
   changes.

Merge a lock-file refresh only after reviewing the generated diff and the
check results, because the lock file is part of the release input.

When triggering `release.yml` manually rather than by tag push, pass the tag as
the `tag` input so checkout, artefact naming, and the GitHub Release target all
use it consistently. Do not build a branch ref while publishing a tag release.
