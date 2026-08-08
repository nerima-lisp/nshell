{
  description = "Modern interactive shell in Common Lisp";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Sibling packages are ALWAYS pinned to a release tag. A bare
    # `github:nerima-lisp/cl-prolog` follows that repo's default branch, which
    # means an upstream push to main breaks this repo's CI without warning.
    #
    # cl-prolog and cl-weave are source inputs. Their upstream flakes do not
    # publish packages for every nshell platform, so they are built locally
    # with the same nixpkgs package set as nshell.
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cl-weave is the testing framework behind both suites.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The rest of the nerima-lisp toolkit family. We only need each one's
    # source tree (built as an SBCL lisp library below via buildASDFSystem), so
    # consume them as non-flake sources. `flake = false` reaches the same goal
    # `inputs.nixpkgs.follows` exists for, and reaches it more completely: a
    # non-flake input has no inputs of its own, so it cannot contribute a
    # second nixpkgs to flake.lock at all. It also works uniformly for a
    # checkout that ships no flake.nix.
    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.0.0";
      flake = false;
    };
    cl-dataflow = {
      url = "github:nerima-lisp/cl-dataflow/v1.1.1";
      flake = false;
    };
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    # v0.6.0, not v1.0.0: cl-boundary-kit's .asd already says 1.0.0 but that
    # tag does not exist yet. Pin what is published, not what is intended.
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v0.6.0";
      flake = false;
    };
    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.3.0";
      flake = false;
    };
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.0.0";
      flake = false;
    };
    # cl-process-kit consolidates timeout-guarded process launch; it sits on
    # cl-boundary-kit (clock/sleeper) and cl-log-kit (structured logging).
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v1.0.0";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v1.0.0";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-prolog,
      cl-weave,
      cl-parser-kit,
      cl-dataflow,
      cl-host-kit,
      cl-boundary-kit,
      cl-cli,
      cl-tty-kit,
      cl-log-kit,
      cl-process-kit,
      cl-date-kit,
      cl-concurrent-kit,
      treefmt-nix,
      ...
    }:
    let
      # Only platforms that CI and release jobs verify natively. aarch64-linux
      # and x86_64-darwin are deliberately absent: nothing exercises them, and
      # declaring them would advertise support no run ever confirms.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Read an ASDF system's `:version` out of its .asd file. Nix regexes are
      # whole-string anchored and `.` never spans newlines, so the version is
      # extracted line-by-line rather than with one multi-line match.
      #
      # Applied to the dependencies as well as to nshell itself: the previously
      # hand-written version strings had silently drifted (cl-log-kit's real
      # 1.0.0 was labelled "1.6.0", cl-process-kit's 1.0.0 was "0.2.0"), and a
      # number nobody updates is worse than no number.
      asdVersionOf =
        file:
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile file);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # Single source of truth for the package version: the `:version` form in
      # nshell.asd. A release only ever edits the .asd file, and every Nix
      # package follows automatically; release.yml refuses to publish a tag
      # that disagrees with it.
      version = asdVersionOf ./nshell.asd;

      # Compiled Lisp artefacts must never enter the store: a stale .fasl from
      # a local REPL session would be preferred over the source beside it.
      sourceFor =
        pkgs:
        pkgs.lib.cleanSourceWith {
          src = ./.;
          filter =
            path: type:
            (pkgs.lib.cleanSourceFilter path type)
            && (
              let
                name = builtins.baseNameOf path;
              in
              !(
                pkgs.lib.hasSuffix ".fasl" name
                || pkgs.lib.hasSuffix ".cfasl" name
                || pkgs.lib.hasSuffix ".dfsl" name
                || pkgs.lib.hasSuffix ".ufasl" name
                || pkgs.lib.hasSuffix ".core" name
                || pkgs.lib.hasSuffix ".o" name
              )
            );
        };

      # CL_SOURCE_REGISTRY for every non-sandboxed entry point (dev shell) and
      # for the source-registry-based checks. Each .asd sits at the root of its
      # own tree. Defined once so a newly adopted dependency cannot be added to
      # the build but forgotten here -- exactly the gap that previously left
      # cl-log-kit and cl-process-kit out of the checks' registry.
      depSources = [
        cl-weave
        cl-prolog
        cl-parser-kit
        cl-dataflow
        cl-host-kit
        cl-boundary-kit
        cl-cli
        cl-tty-kit
        cl-log-kit
        cl-process-kit
        cl-date-kit
        cl-concurrent-kit
      ];
      depRegistry = nixpkgs.lib.concatMapStrings (dep: "${dep}//:") depSources;

      # Common Lisp dependencies built from source inputs with this flake's
      # nixpkgs. Named packages and the runtime library list live together so
      # package and dev-shell definitions cannot drift apart.
      lispPackagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          clProlog = pkgs.sbcl.buildASDFSystem {
            pname = "cl-prolog";
            version = asdVersionOf "${cl-prolog}/cl-prolog.asd";
            src = cl-prolog;
            systems = [ "cl-prolog" ];
          };
          clWeave = pkgs.sbcl.buildASDFSystem {
            pname = "cl-weave";
            version = asdVersionOf "${cl-weave}/cl-weave.asd";
            src = cl-weave;
            systems = [ "cl-weave" ];
          };
          clParserKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-parser-kit";
            version = asdVersionOf "${cl-parser-kit}/cl-parser-kit.asd";
            src = cl-parser-kit;
            systems = [ "cl-parser-kit" ];
          };
          clDateKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-date-kit";
            version = asdVersionOf "${cl-date-kit}/cl-date-kit.asd";
            src = cl-date-kit;
            systems = [ "cl-date-kit" ];
          };
          clDataflow = pkgs.sbcl.buildASDFSystem {
            pname = "cl-dataflow";
            version = asdVersionOf "${cl-dataflow}/cl-dataflow.asd";
            src = cl-dataflow;
            systems = [ "cl-dataflow" ];
            lispLibs = [
              clProlog
              clConcurrentKit
            ];
          };
          clHostKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-host-kit";
            version = asdVersionOf "${cl-host-kit}/cl-host-kit.asd";
            src = cl-host-kit;
            systems = [ "cl-host-kit" ];
          };
          clBoundaryKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-boundary-kit";
            version = asdVersionOf "${cl-boundary-kit}/cl-boundary-kit.asd";
            src = cl-boundary-kit;
            systems = [ "cl-boundary-kit" ];
            lispLibs = [ clLogKit ];
          };
          clConcurrentKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-concurrent-kit";
            version = asdVersionOf "${cl-concurrent-kit}/cl-concurrent-kit.asd";
            src = cl-concurrent-kit;
            systems = [ "cl-concurrent-kit" ];
            lispLibs = [
              clBoundaryKit
              clDateKit
            ];
          };
          clCli = pkgs.sbcl.buildASDFSystem {
            pname = "cl-cli";
            version = asdVersionOf "${cl-cli}/cl-cli.asd";
            src = cl-cli;
            systems = [ "cl-cli" ];
            lispLibs = [ clHostKit ];
          };
          clTtyKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-tty-kit";
            version = asdVersionOf "${cl-tty-kit}/cl-tty-kit.asd";
            src = cl-tty-kit;
            systems = [ "cl-tty-kit" ];
          };
          clLogKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-log-kit";
            version = asdVersionOf "${cl-log-kit}/cl-log-kit.asd";
            src = cl-log-kit;
            systems = [ "cl-log-kit" ];
          };
          clProcessKit = pkgs.sbcl.buildASDFSystem {
            pname = "cl-process-kit";
            version = asdVersionOf "${cl-process-kit}/cl-process-kit.asd";
            src = cl-process-kit;
            systems = [ "cl-process-kit" ];
            lispLibs = [
              clBoundaryKit
              clLogKit
            ];
          };
        in
        {
          inherit clProlog clWeave;
          lispLibs = [
            clProlog
            clParserKit
            clDataflow
            clHostKit
            clBoundaryKit
            clCli
            clTtyKit
            clProcessKit
            clDateKit
            clConcurrentKit
          ];
        };

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:`
      # key and Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          src = sourceFor pkgs;
          mkNshell =
            compression:
            pkgs.sbcl.buildASDFSystem {
              pname = "nshell";
              inherit version src;
              systems = [ "nshell" ];
              lispLibs = (lispPackagesFor system).lispLibs;
              buildScript = pkgs.writeText "build-nshell.lisp" ''
                (require :asdf)
                (setf asdf:*compile-file-warnings-behaviour* :warn)
                (setf asdf:*compile-file-failure-behaviour* :warn)
                (push (truename "./") asdf:*central-registry*)
                (asdf:load-system :nshell)
                (sb-ext:save-lisp-and-die "nshell"
                  :executable t
                  :compression ${if compression then "t" else "nil"}
                  ;; Stop the SBCL C runtime from intercepting --version/--help and
                  ;; other runtime flags before nshell:main runs.
                  :save-runtime-options t
                  :toplevel #'nshell:main)
              '';
              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin
                cp nshell $out/bin/
                if [ -f man/nshell.1 ]; then
                  mkdir -p $out/share/man/man1
                  cp man/nshell.1 $out/share/man/man1/nshell.1
                fi
                runHook postInstall
              '';
              meta = {
                description = "Modern, fish-inspired interactive shell written in Common Lisp";
                homepage = "https://github.com/nerima-lisp/nshell";
                license = pkgs.lib.licenses.mit;
                platforms = systems;
                mainProgram = "nshell";
              };
            };
        in
        rec {
          # The command image is latency-sensitive.  Compression substantially
          # increases warm-filesystem process startup, while release artifacts use
          # the uncompressed image.
          nshell = mkNshell false;
          default = nshell;

          releaseBundle =
            pkgs.runCommand "nshell-${version}-${system}"
              {
                nativeBuildInputs = [
                  pkgs.perl
                ]
                ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
                  pkgs.binutils
                  pkgs.patchelf
                ]
                ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.cctools ];
              }
              ''
                mkdir -p $out/bin $out/libexec $out/lib $out/share/man/man1 $out/LICENSES
                cp ${src}/README.md $out/README.md
                cp ${src}/LICENSE $out/LICENSE
                cp ${src}/man/nshell.1 $out/share/man/man1/nshell.1
                cp ${pkgs.sbcl}/share/doc/sbcl/COPYING $out/LICENSES/SBCL-COPYING
                cp ${pkgs.zstd.src}/LICENSE $out/LICENSES/ZSTD-LICENSE
                cp ${cl-prolog}/LICENSE $out/LICENSES/CL-PROLOG-LICENSE
                cp ${cl-parser-kit}/LICENSE $out/LICENSES/CL-PARSER-KIT-LICENSE
                cp ${cl-dataflow}/LICENSE $out/LICENSES/CL-DATAFLOW-LICENSE
                cp ${cl-host-kit}/LICENSE $out/LICENSES/CL-HOST-KIT-LICENSE
                cp ${cl-boundary-kit}/LICENSE $out/LICENSES/CL-BOUNDARY-KIT-LICENSE
                cp ${cl-cli}/LICENSE $out/LICENSES/CL-CLI-LICENSE
                cp ${cl-tty-kit}/LICENSE $out/LICENSES/CL-TTY-KIT-LICENSE
                cp ${cl-log-kit}/LICENSE $out/LICENSES/CL-LOG-KIT-LICENSE
                cp ${cl-process-kit}/LICENSE $out/LICENSES/CL-PROCESS-KIT-LICENSE
                cp ${cl-date-kit}/LICENSE $out/LICENSES/CL-DATE-KIT-LICENSE
                cp ${cl-concurrent-kit}/LICENSE $out/LICENSES/CL-CONCURRENT-KIT-LICENSE

                ${
                  if pkgs.stdenv.isLinux then
                    ''
                      cp ${nshell}/bin/nshell $out/libexec/nshell
                      patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
                        --set-rpath '$ORIGIN/../lib' $out/libexec/nshell
                      cp -L ${pkgs.stdenv.cc.libc}/lib/ld-linux-x86-64.so.2 $out/lib/
                      printf '%s\n' $out/libexec/nshell > $out/.elf-queue
                      while IFS= read -r object; do
                        for needed in $(patchelf --print-needed "$object"); do
                          if [ -e "$out/lib/$needed" ]; then
                            continue
                          fi
                          dependency=
                          for directory in \
                            ${pkgs.stdenv.cc.libc}/lib \
                            ${pkgs.zstd.out}/lib \
                            ${pkgs.stdenv.cc.cc.lib}/lib; do
                            if [ -e "$directory/$needed" ]; then
                              dependency="$directory/$needed"
                              break
                            fi
                          done
                          if [ -z "$dependency" ]; then
                            echo "unsupported release dependency: $needed (needed by $object)" >&2
                            exit 1
                          fi
                          cp -L "$dependency" "$out/lib/$needed"
                          printf '%s\n' "$out/lib/$needed" >> $out/.elf-queue
                        done
                      done < $out/.elf-queue
                      rm $out/.elf-queue
                      tar -xf ${pkgs.glibc.src}
                      cp glibc-*/COPYING.LIB $out/LICENSES/GLIBC-COPYING.LIB
                      tar -xf ${pkgs.stdenv.cc.cc.src}
                      cp gcc-*/COPYING3 $out/LICENSES/GCC-COPYING3
                      cp gcc-*/COPYING.RUNTIME $out/LICENSES/GCC-RUNTIME-LIBRARY-EXCEPTION
                      cat > $out/bin/nshell <<'EOF'
                      #!/bin/sh
                      case "$0" in
                        /*) self="$0" ;;
                        */*) self="$PWD/$0" ;;
                        *) self="$(command -v "$0")" ;;
                      esac
                      while [ -L "$self" ]; do
                        directory="$(CDPATH= cd -- "''${self%/*}" && pwd)"
                        target="$(readlink "$self")"
                        case "$target" in
                          /*) self="$target" ;;
                          *) self="$directory/$target" ;;
                        esac
                      done
                      root="$(CDPATH= cd -- "''${self%/*}/.." && pwd)"
                      exec "$root/lib/ld-linux-x86-64.so.2" \
                        --library-path "$root/lib" --argv0 "$0" \
                        "$root/libexec/nshell" "$@"
                      EOF
                    ''
                  else
                    ''
                      cp ${nshell}/bin/nshell $out/bin/nshell
                      zstd_dependency="$(
                        otool -L $out/bin/nshell |
                          perl -ne 'if (/^\s+(\/nix\/store\/\S+libzstd\S+\.dylib)\s/) { print $1; exit }'
                      )"
                      if [ -n "$zstd_dependency" ]; then
                        zstd_name="''${zstd_dependency##*/}"
                        cp -L "$zstd_dependency" "$out/lib/$zstd_name"
                        old="$zstd_dependency" new="@executable_path/../lib/$zstd_name" \
                          perl -0777 -pi -e '
                            die "replacement is longer than Mach-O load path\n"
                              if length($ENV{new}) > length($ENV{old});
                            $replacement = $ENV{new} . "\0" x (length($ENV{old}) - length($ENV{new}));
                            s/\Q$ENV{old}\E/$replacement/ or die "Mach-O load path not found\n";
                          ' $out/bin/nshell
                        install_name_tool -id "@rpath/$zstd_name" "$out/lib/$zstd_name"
                      fi
                      otool -L $out/bin/nshell > $out/.otool
                      if perl -ne 'next if $. == 1; exit 1 if m{/nix/store/}' $out/.otool; then :; else
                        cat $out/.otool >&2
                        exit 1
                      fi
                      rm $out/.otool
                    ''
                }
                # SBCL records source locations in its appended core. Dynamic
                # dependencies have already been made relative above, so only
                # these non-runtime metadata strings remain. Keep the prefix
                # length unchanged to preserve binary offsets and layouts.
                find $out -type f -exec \
                  perl -0777 -pi -e 's{/nix/store/}{/non/store/}g' {} +
                chmod +x $out/bin/nshell
                ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
                  chmod +x $out/libexec/nshell $out/lib/ld-linux-x86-64.so.2
                ''}
                perl ${src}/scripts/verify-release-bundle.pl $out --no-smoke
              '';

          # Rendered documentation site (Material for MkDocs).
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "nshell-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./docs;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for nshell";
              homepage = "https://github.com/nerima-lisp/nshell";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel, with
      # build caching. Add a check here rather than a job in ci.yml. The two
      # jobs ci.yml does add are the ones this sandbox cannot host: the real-PTY
      # integration run and the started-binary check on each runner OS.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          src = sourceFor pkgs;
          bin = "${self.packages.${system}.default}/bin/nshell";
          # Both suites resolve their dependencies from the raw source
          # checkouts: nshell/weave additionally needs cl-prolog/weave, which
          # lives inside the cl-prolog repository rather than its package.
          runSuite =
            name: script:
            pkgs.runCommand "nshell-${name}"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
              }
              ''
                cp -R ${src} source
                chmod -R u+w source
                cd source
                export HOME="$TMPDIR/home"
                export XDG_CACHE_HOME="$TMPDIR/cache"
                mkdir -p "$HOME" "$XDG_CACHE_HOME"
                export CL_SOURCE_REGISTRY="${depRegistry}$PWD//:"
                # Bounded so a hung suite fails in half an hour rather than
                # occupying a runner until GitHub's six-hour job ceiling.
                timeout 1800 sbcl --script ${script}
                touch $out
              '';
        in
        {
          # The primary regression suite, through the same run-tests.lisp entry
          # point a developer runs locally.
          default = runSuite "tests" "run-tests.lisp";

          # The focused cl-weave completion suite (nshell/weave).
          weave = runSuite "weave-suite" "scripts/weave.lisp";

          # Validate benchmark evidence schemas without running a timed
          # workload or imposing a machine-dependent performance threshold.
          benchmark-integrity =
            pkgs.runCommand "nshell-benchmark-integrity" { nativeBuildInputs = [ pkgs.perl ]; }
              ''
                perl -c ${src}/scripts/verify-benchmark-jsonl.pl
                perl -c ${src}/scripts/benchmark-competitors.pl
                perl ${src}/scripts/verify-benchmark-jsonl.pl --self-test
                touch $out
              '';

          # Keep the release validator's required-file contract executable:
          # removing a copied dependency license must fail the check.
          release-bundle-validator =
            pkgs.runCommand "nshell-release-bundle-validator"
              { nativeBuildInputs = [ pkgs.perl pkgs.coreutils ]; }
              ''
                cp -R ${self.packages.${system}.releaseBundle} bundle
                chmod -R u+w bundle
                rm bundle/LICENSES/CL-HOST-KIT-LICENSE
                if perl ${src}/scripts/verify-release-bundle.pl bundle --no-smoke; then
                  echo "release validator accepted a bundle with a missing license"
                  exit 1
                fi
                touch $out
              '';

          # Verify the default package compiles and the image dumps.
          build = self.packages.${system}.default;

          # Fails `nix flake check` when any tracked file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check src;

          # The docs package builds with `mkdocs --strict`, so a broken link or
          # a page missing from the nav fails the build. Without this the docs
          # are only ever built by the publish workflow, which runs after a
          # merge to main, meaning such a break surfaces as a failed deploy
          # rather than as a failed pull request.
          docs = self.packages.${system}.docs;

          # Smoke test: the dumped image runs real shell operations. This is
          # the in-sandbox half; ci.yml's `binary` job repeats it outside the
          # sandbox, where a genuine terminal exists.
          smoke-test =
            pkgs.runCommand "nshell-smoke-test"
              {
                nativeBuildInputs = [ pkgs.perl ];
                buildInputs = [ self.packages.${system}.default ];
              }
              ''
                set -euo pipefail

                echo "=== nshell smoke test ==="

                # Verify binary exists and is executable
                test -x "${bin}" || {
                  echo "FAIL: binary not found or not executable at ${bin}"
                  exit 1
                }
                echo "PASS: binary exists and is executable"

                # Verify the non-interactive CLI contract exposed by releases.
                "${bin}" --version > version-output
                perl -ne 'END { exit($found ? 0 : 1) } $found = 1 if /nshell v${version}/' version-output || {
                  echo "FAIL: --version did not report nshell v${version}"
                  exit 1
                }

                "${bin}" --help > help-output
                perl -ne 'END { exit($found ? 0 : 1) } $found = 1 if /^Usage: nshell /' help-output || {
                  echo "FAIL: --help did not print usage"
                  exit 1
                }

                "${bin}" -c 'echo command-mode' > command-output
                perl -0777 -ne 'exit($_ eq "command-mode\n" ? 0 : 1)' command-output || {
                  echo "FAIL: -c did not execute its command"
                  exit 1
                }

                if "${bin}" --definitely-invalid-option > invalid-option-output 2>&1; then
                  echo "FAIL: unknown option unexpectedly succeeded"
                  exit 1
                fi
                perl -ne 'END { exit($found ? 0 : 1) } $found = 1 if /^Usage: nshell /' invalid-option-output || {
                  echo "FAIL: unknown option did not print usage"
                  exit 1
                }
                echo "PASS: CLI options"

                # Test 1: echo a string
                echo "echo hello" | "${bin}" > output 2>&1
                grep -q hello output || {
                  echo "FAIL: 'echo hello' - expected 'hello' in output"
                  echo "got: $(cat output)"
                  exit 1
                }
                echo "PASS: echo hello"

                # Test 2: pipeline
                echo "echo hello world | grep world" | "${bin}" > output2 2>&1
                grep -q world output2 || {
                  echo "FAIL: pipeline grep - expected 'world' in output"
                  echo "got: $(cat output2)"
                  exit 1
                }
                echo "PASS: pipeline with grep"

                # Test 3: cd and pwd (verify pwd output is correct, not matching prompt echo)
                echo "cd /tmp ; pwd" | "${bin}" > output3 2>&1
                # pwd should output exactly /private/tmp (macOS) or /tmp (Linux)
                { grep "/tmp" output3 | grep -v "~" | grep -v ">" ; } || {
                  echo "FAIL: 'cd /tmp ; pwd' - expected /tmp in output"
                  echo "got: $(cat output3 | head -c 2000)"
                  exit 1
                }
                echo "PASS: cd && pwd"

                # All tests passed
                echo ""
                echo "All smoke tests passed successfully!"
                touch $out
              '';
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "nshell-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${depRegistry}${self}//:"
              cd "${self}"
              exec timeout 1800 sbcl --script run-tests.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/nshell";
            meta.description = "Run nshell";
          };
          test = {
            type = "app";
            program = "${test}/bin/nshell-test";
            meta.description = "Run the nshell test suite";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lispPackages = lispPackagesFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.sbcl
              lispPackages.clProlog
              lispPackages.clWeave
            ];
            shellHook = ''
              # Resolve every dependency from its source checkout: cl-weave,
              # cl-prolog (and the cl-prolog/weave system it ships), the rest of
              # the toolkit family, and nshell itself. Each .asd sits at the
              # root of its tree.
              export CL_SOURCE_REGISTRY="${depRegistry}$PWD//:''${CL_SOURCE_REGISTRY:-}"
              export NSHELL_ROOT=$PWD
              alias test='cd "$NSHELL_ROOT" && sbcl --script "$NSHELL_ROOT/run-tests.lisp"'
              alias coverage='cd "$NSHELL_ROOT" && NSHELL_COVERAGE_DIR="$NSHELL_ROOT/coverage" sbcl --script "$NSHELL_ROOT/scripts/coverage.lisp"'
              alias weave='cd "$NSHELL_ROOT" && sbcl --script "$NSHELL_ROOT/scripts/weave.lisp"'
              echo ""
              echo "nshell development environment"
              echo "  test  - Run the full nshell suite (cl-weave, nshell/test)"
              echo "  weave - Run the focused completion suite (nshell/weave)"
              echo "  coverage - Run the test suite and write HTML coverage to coverage/"
              echo "  sbcl  - Interactive Common Lisp (with cl-weave)"
              echo ""
            '';
          };
        }
      );
    };
}
