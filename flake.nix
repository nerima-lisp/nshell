{
  description = "Modern interactive shell in Common Lisp";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org flake preset. Everything this file used to spell out by hand --
    # the `.asd` version extraction, `forAllSystems`, the treefmt eval wired to
    # both `formatter` and `checks.formatting`, the mkdocs package plus its
    # check, the run-tests.lisp gate, the `apps.default`/`apps.nshell` pair, and
    # the hand-written `save-lisp-and-die` that delivered the binary -- is one
    # `mkPackageFlake` call below. Pinned to a release TAG, never to the
    # branch: a bare `github:nerima-lisp/cl-nix-forge` follows that
    # repository's default branch and would change this build without warning.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sibling packages are ALWAYS pinned to a release tag. A bare
    # `github:nerima-lisp/cl-prolog-kit` follows that repo's default branch, which
    # means an upstream push to main breaks this repo's CI without warning.
    #
    # cl-prolog-kit and cl-weave are consumed as flakes, because nshell wants
    # cl-weave's built CLI for the dev shell and not only its source; both
    # therefore carry the mandatory `inputs.nixpkgs.follows`, without which
    # each would drag in its own nixpkgs, inflating flake.lock and rebuilding
    # the same derivations.
    cl-prolog-kit = {
      url = "github:nerima-lisp/cl-prolog-kit/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cl-weave is the testing framework behind both suites.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # paredit-cli is a development-only structure editor. Keeping it outside
    # the runtime registry makes the delivered shell independent of the
    # refactoring tool while making the repository's preferred Lisp workflow
    # reproducible.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The rest of the nerima-lisp toolkit family. We only need each one's
    # source tree (built as an SBCL lisp library by `lispDependencies` below),
    # so consume them as non-flake sources. `flake = false` reaches the same
    # goal `inputs.nixpkgs.follows` exists for, and reaches it more completely:
    # a non-flake input has no inputs of its own, so it cannot contribute a
    # second nixpkgs to flake.lock at all. It also works uniformly for a
    # checkout that ships no flake.nix.
    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.1.1";
      flake = false;
    };
    cl-dataflow-kit = {
      url = "github:nerima-lisp/cl-dataflow-kit/v1.2.0";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      flake = false;
    };
    cl-cli = {
      url = "github:nerima-lisp/cl-cli/v1.3.0";
      flake = false;
    };
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.6.1";
      flake = false;
    };
    # cl-process-kit consolidates timeout-guarded process launch; it sits on
    # cl-boundary-kit (clock/sleeper) and cl-log-kit (structured logging).
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.2.0";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v3.2.0";
      flake = false;
    };
    # cl-history-kit backs the command-history store, search, and recall
    # navigation cursor; nshell itself keeps only the tokenizer-coupled
    # `!$`/Alt-. last-argument extraction on top of it.
    cl-history-kit = {
      url = "github:nerima-lisp/cl-history-kit/v1.0.4";
      flake = false;
    };
    # cl-host-kit replaces uiop for this repository's host operations
    # (environment variables, working directory, pathname predicates, directory
    # listings, string splitting) as of the 2026-08-01 org migration. It is
    # SBCL-only and depends on nothing but the sb-posix contrib, so it needs no
    # `lispDependencies` of its own below.
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
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
      cl-nix-forge,
      cl-prolog-kit,
      cl-weave,
      paredit-cli,
      cl-parser-kit,
      cl-dataflow-kit,
      cl-host-kit,
      cl-boundary-kit,
      cl-cli,
      cl-tty-kit,
      cl-log-kit,
      cl-process-kit,
      cl-history-kit,
      cl-codec-kit,
      cl-concurrent-kit,
      cl-date-kit,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # x86_64-linux is what CI gates; aarch64-darwin is the development
      # machine. Every per-system output -- packages, checks, apps AND devShells
      # -- comes from this one list, so leaving aarch64-darwin out takes `nix
      # build` and `nix develop` off the development machine as well. That trade
      # was made on 2026-08-01 and reverted on 2026-08-02; aarch64-darwin carries
      # no CI gate, which PACKAGE_STANDARD.md's "systems" section accepts
      # explicitly. aarch64-linux and x86_64-darwin are nobody's verification and
      # are not declared.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      meta = {
        description = "Modern, fish-inspired interactive shell written in Common Lisp";
        homepage = "https://github.com/nerima-lisp/nshell";
        license = lib.licenses.mit;
        platforms = systems;
        mainProgram = "nshell";
      };

      # treefmt's check creates a temporary Git repository before comparing
      # the formatter's output. A linked worktree carries a `.git` pointer,
      # not a repository, so passing the raw worktree to that check makes the
      # check fail before treefmt runs. Keep the formatter's source complete
      # while removing repository metadata that has no formatting semantics.
      formatSource = builtins.path {
        path = ./.;
        name = "nshell-format-source";
        filter = path: type: builtins.baseNameOf path != ".git";
      };

      # The toolkit family, each built from its pinned checkout as an SBCL lisp
      # library. Built here rather than taken from each sibling's own
      # `packages.<system>` (which is what cl-cowsay and cl-cmatrix do) because
      # the tags this repository pins predate those repositories' migration to
      # cl-nix-forge: at these tags they publish nixpkgs `buildASDFSystem`
      # derivations, which a `lispDependencies` entry would have to be wrapped
      # for one by one. Building the source with `lispDerivation` is the same
      # library doing the same job, and it keeps every dependency's ASDF
      # registry -- including the transitive ones -- computed in one place.
      #
      # A function of `ctx` because a derivation is per-system: the preset
      # spans systems and hands each callback the system it is building for.
      # Called from three arguments below; identical arguments produce an
      # identical derivation, so the sibling is built once.
      siblingsFor =
        ctx:
        let
          sibling =
            {
              name,
              source,
              dependencies ? [ ],
              patches ? [ ],
            }:
            ctx.cl.lispDerivation {
              pname = name;
              # Read out of the sibling's own .asd, never written here. The
              # previously hand-written version strings had silently drifted
              # (cl-log-kit's real 1.0.0 was labelled "1.6.0",
              # cl-process-kit's 1.0.0 was "0.2.0"), and a number nobody
              # updates is worse than no number.
              version = ctx.cl.fromAsdSystem "${source}/${name}.asd";
              src = source;
              lispSystem = name;
              lispDependencies = dependencies;
              inherit patches;
            };
        in
        rec {
          clProlog = sibling {
            name = "cl-prolog-kit";
            source = cl-prolog-kit;
          };
          clWeave = sibling {
            name = "cl-weave";
            source = cl-weave;
          };
          clParserKit = sibling {
            name = "cl-parser-kit";
            source = cl-parser-kit;
          };
          clDataflow = sibling {
            name = "cl-dataflow-kit";
            source = cl-dataflow-kit;
            dependencies = [
              clProlog
              clConcurrentKit
            ];
          };
          clDateKit = sibling {
            name = "cl-date-kit";
            source = cl-date-kit;
          };
          clHostKit = sibling {
            name = "cl-host-kit";
            source = cl-host-kit;
          };
          clCodecKit = sibling {
            name = "cl-codec-kit";
            source = cl-codec-kit;
          };
          clBoundaryKit = sibling {
            name = "cl-boundary-kit";
            source = cl-boundary-kit;
            dependencies = [ clHostKit ];
          };
          clConcurrentKit = sibling {
            name = "cl-concurrent-kit";
            source = cl-concurrent-kit;
            dependencies = [
              clBoundaryKit
              clDateKit
            ];
          };
          clLogKit = sibling {
            name = "cl-log-kit";
            source = cl-log-kit;
            dependencies = [
              clConcurrentKit
              clDateKit
              clHostKit
            ];
          };
          clCli = sibling {
            name = "cl-cli";
            source = cl-cli;
            dependencies = [ clHostKit ];
          };
          clTtyKit = sibling {
            name = "cl-tty-kit";
            source = cl-tty-kit;
            dependencies = [
              clCodecKit
              clConcurrentKit
            ];
          };
          clProcessKit = sibling {
            name = "cl-process-kit";
            source = cl-process-kit;
            dependencies = [
              clBoundaryKit
              clLogKit
              clCodecKit
            ];
            # v3.2.0 defines %monotonic-seconds in both parameters.lisp and
            # fd-readiness.lisp. Upstream main is still identical; remove this
            # patch when a release containing the upstream fix is available.
            patches = [ ./nix/patches/cl-process-kit-no-duplicate-monotonic-seconds.patch ];
          };
          clHistoryKit = sibling {
            name = "cl-history-kit";
            source = cl-history-kit;
          };
        };

      # The delivered binary plus its human-readable release metadata.
      # `overrideAttrs` on the delivery,
      # not a second derivation wrapping it: `mkExecutable` returns a
      # `runCommand`, so appending to its build command installs the man page
      # into that same output instead of leaving two copies of a 40MB
      # executable in the store. The man page is referenced as a path literal
      # rather than read out of the package source, because `mkLispSource`
      # allowlists Lisp files and nshell.1 is deliberately not one of them.
      #
      # Unconditional, where the derivation this replaced tested `[ -f
      # man/nshell.1 ]` first: the file is tracked, and a missing one is now an
      # evaluation error naming it instead of a binary that silently ships
      # without its man page.
      deliveryFor =
        ctx:
        ctx.executable.overrideAttrs (previous: {
          buildCommand = previous.buildCommand + ''
            mkdir -p "$out/share/man/man1" "$out/LICENSES"
            cp ${./README.md} "$out/README.md"
            cp ${./LICENSE} "$out/LICENSE"
            cp ${ctx.pkgs.sbcl}/share/doc/sbcl/COPYING "$out/LICENSES/SBCL-COPYING"
            cp ${ctx.pkgs.zstd.src}/LICENSE "$out/LICENSES/ZSTD-LICENSE"
            cp ${cl-prolog-kit}/LICENSE "$out/LICENSES/CL-PROLOG-KIT-LICENSE"
            cp ${cl-parser-kit}/LICENSE "$out/LICENSES/CL-PARSER-KIT-LICENSE"
            cp ${cl-dataflow-kit}/LICENSE "$out/LICENSES/CL-DATAFLOW-KIT-LICENSE"
            cp ${cl-host-kit}/LICENSE "$out/LICENSES/CL-HOST-KIT-LICENSE"
            cp ${cl-boundary-kit}/LICENSE "$out/LICENSES/CL-BOUNDARY-KIT-LICENSE"
            cp ${cl-cli}/LICENSE "$out/LICENSES/CL-CLI-LICENSE"
            cp ${cl-tty-kit}/LICENSE "$out/LICENSES/CL-TTY-KIT-LICENSE"
            cp ${cl-log-kit}/LICENSE "$out/LICENSES/CL-LOG-KIT-LICENSE"
            cp ${cl-process-kit}/LICENSE "$out/LICENSES/CL-PROCESS-KIT-LICENSE"
            cp ${cl-history-kit}/LICENSE "$out/LICENSES/CL-HISTORY-KIT-LICENSE"
            cp ${cl-codec-kit}/LICENSE "$out/LICENSES/CL-CODEC-KIT-LICENSE"
            cp ${cl-date-kit}/LICENSE "$out/LICENSES/CL-DATE-KIT-LICENSE"
            cp ${cl-concurrent-kit}/LICENSE "$out/LICENSES/CL-CONCURRENT-KIT-LICENSE"
            cp ${./man/nshell.1} "$out/share/man/man1/nshell.1"
          '';
        });

      # `packages.releaseBundle`: a relocatable artifact for users without
      # Nix, as opposed to `deliveryFor`'s `$out/bin/nshell`, which is a
      # `makeWrapper` script that execs a Lisp core through paths under the
      # Nix store that built it and cannot run anywhere else.
      # `scripts/verify-release-bundle.pl` is this function's other half --
      # it was introduced alongside the derivation this restores (see the
      # 2026-08-08 "add public readiness tooling" history) and every check
      # it makes on Linux (no `/nix/store` byte sequence anywhere in the
      # bundle, a real ELF interpreter, a license file for every runtime
      # library actually shipped) is a property this build establishes. A
      # later merge kept the checker and silently dropped the derivation
      # that satisfied it, which is what this restores; it was never
      # exercised by CI even before that (docs/src/project/public-readiness.md
      # still records Linux release evidence as outstanding), so treat this
      # port as unverified until `build release binary` (ci.yml, ubuntu-latest
      # only) is green on it.
      #
      # Linux only: cl-nix-forge's `mkExecutable` (v0.5.0,
      # lib/batteries/app.nix) falls back, for SBCL on Darwin, to a bare
      # non-executable `.core` plus a `sbcl --core` wrapper -- there is no
      # Mach-O `nshell` binary on that path to relocate the way the Linux
      # branch below relocates one, and `ci.yml`'s "build release binary"
      # job runs on `ubuntu-latest` only (its own comment records that the
      # macos-14 leg was deliberately deleted, not merely disabled). So a
      # portable Darwin bundle has no gate proving it right, and `delivery`
      # -- unconditionally buildable on every system `mkExecutable` supports
      # -- keeps `nix build .#releaseBundle` working on the development
      # machine, the property cedf775 restored deliberately, without
      # asserting a portability claim `scripts/verify-release-bundle.pl`
      # would reject on Darwin and nothing exercises there.
      releaseBundleFor =
        ctx:
        let
          pkgs = ctx.pkgs;
          delivery = deliveryFor ctx;
        in
        if !pkgs.stdenv.hostPlatform.isLinux then
          delivery
        else
          let
            # `${ctx.executable}/bin/nshell.cl-nix-forge-unwrapped` -- not
            # `ctx.package` -- is the dumped, `:compression t` image:
            # `ctx.package` is the plain ASDF system build, without the
            # `program-op` dump `mkExecutable` performs internally before
            # wrapping it. That internal build writes the image to
            # `$out/<programPath>` and then `mv`s it to this exact
            # `<pname>.cl-nix-forge-unwrapped` path before installing the
            # wrapper in its place -- an internal naming convention, not a
            # published contract, so this coupling breaks silently on a
            # cl-nix-forge upgrade; re-read `mkExecutable` in app.nix if
            # this derivation starts failing right after one.
            builtImage = "${ctx.executable}/bin/nshell.cl-nix-forge-unwrapped";
          in
          pkgs.runCommand "nshell-${ctx.version}-release-${ctx.system}"
            {
              nativeBuildInputs = [
                pkgs.perl
                pkgs.binutils
                pkgs.patchelf
              ];
            }
            ''
              mkdir -p $out/bin $out/libexec $out/lib
              cp -R ${delivery}/README.md ${delivery}/LICENSE ${delivery}/LICENSES ${delivery}/share $out/

              cp ${builtImage} $out/libexec/nshell
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

              # SBCL records source locations in its appended core. Dynamic
              # dependencies have already been made relative above, so only
              # these non-runtime metadata strings remain. Keep the prefix
              # length unchanged to preserve binary offsets and layouts.
              find $out -type f -exec \
                perl -0777 -pi -e 's{/nix/store/}{/non/store/}g' {} +
              chmod +x $out/bin/nshell $out/libexec/nshell $out/lib/ld-linux-x86-64.so.2
              perl ${./scripts/verify-release-bundle.pl} $out --no-smoke
            '';
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # instance this function is *taken from* contributes nothing but the
    # function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit systems nixpkgs meta;
      self = formatSource;
      pname = "nshell";

      # Single source of truth for the package version: the `:version` form in
      # nshell.asd. A release only ever edits the .asd file, every derivation
      # carrying a version follows automatically, and release.yml refuses to
      # publish a tag that disagrees with it.
      asd = ./nshell.asd;

      # Path literal, not `self`: `lib.fileset` refuses a flake's string-like
      # `self`. `./.` is the same directory.
      root = ./.;

      lispDependencies =
        ctx: with siblingsFor ctx; [
          clProlog
          clParserKit
          clDataflow
          clBoundaryKit
          clCli
          clTtyKit
          clProcessKit
          clHistoryKit
          clHostKit
          clCodecKit
          clConcurrentKit
          clDateKit
        ];

      # cl-weave is a dependency of `nshell/test` and `nshell/weave` only (see
      # nshell.asd), so it is a CHECK dependency: it must not enter the
      # delivered binary's closure. cl-prolog-kit/weave, which the nshell/weave
      # suite also loads, needs nothing extra -- it is a secondary system of
      # cl-prolog-kit, whose whole source tree is already on the registry above.
      lispCheckDependencies = ctx: [ (siblingsFor ctx).clWeave ];

      # Drives the test checks from this one number, so the contributor-facing
      # gate and CI cannot drift apart. Bounded so a hung suite fails in half an hour
      # rather than occupying a runner until GitHub's six-hour job ceiling.
      timeoutSeconds = 1800;

      # The delivered `nshell` binary: `packages.default`, `apps.default` and
      # `apps.nshell`, all built from the same `lispDerivation` arguments as
      # `packages.nshell`. Nothing here repeats what nshell.asd already
      # declares -- `:build-operation "program-op"`, `:build-pathname "nshell"`
      # and `:entry-point "nshell:main"` live in the system definition, as does
      # the `:perform` that dumps the image with `:compression t` (the one
      # thing `mkExecutable` cannot pass, and the reason that method exists).
      #
      # `installSource = false`: nshell runs only what was dumped into the
      # image -- its `source` builtin reads shell scripts, and no code path
      # loads an ASDF system at run time -- so shipping the source closure
      # beside the binary would buy nothing and cost the whole closure.
      #
      # `programPath = "src/nshell"`: cl-nix-forge's `mkExecutable` defaults
      # to checking `$out/<lispSystem>` (i.e. `$out/nshell`) for the dumped
      # image, but ASDF's `:build-pathname "nshell"` resolves relative to
      # this system's own `:pathname "src"`, so `program-op` actually writes
      # it to `$out/src/nshell` -- confirmed by the `fixupPhase` RPATH-shrink
      # log naming that exact path. Left at the default, `mkExecutable`
      # looks in the wrong place and fails with "ASDF program-op did not
      # create executable nshell" even though the build succeeded; this is
      # exactly the ASDF-specific detail `programPath`'s own docstring in
      # cl-nix-forge says to make explicit at this boundary.
      executable = {
        installSource = false;
        programPath = "src/nshell";
      };

      # docs/mkdocs.yml + docs/src/, built with `--strict` so a broken link or
      # a page missing from the nav is a build failure. `checks.docs` comes
      # with it. The fileset is spelled out rather than taking all of ./docs,
      # because docs/notes/ is working material that mkdocs never reads: left
      # in, it would enter the store and make an edit to a note rebuild the
      # site.
      docs = {
        root = ./docs;
        fileset = lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
      };

      # ONE treefmt evaluation drives `nix fmt` and the `checks.formatting`
      # gate, so the formatter and CI can never disagree about what
      # "formatted" means. Scope is Nix only: nixfmt (RFC-style) is a
      # zero-footgun, low-diff formatter, whereas YAML formatters mangle the
      # GitHub Actions `on:` key and Markdown reformatting would churn the
      # whole docs tree.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # The cl-weave CLI, which the suites' reporters are documented against.
      # Interactive only: the registry the shell exports already carries every
      # system, check dependencies included.
      devShellPackages = ctx: [
        cl-weave.packages.${ctx.system}.default
        paredit-cli.packages.${ctx.system}.default
      ];

      overrideOutputs =
        ctx:
        let
          delivery = deliveryFor ctx;
          app = ctx.cl.mkApp { drv = delivery; };
        in
        {
          packages.default = delivery;
          apps.default = app;
          apps.nshell = app;
          apps.test = {
            type = "app";
            meta = {
              description = "Run the complete nshell test suite";
            };
            program = "${
              ctx.pkgs.writeTextFile {
                name = "nshell-test";
                executable = true;
                destination = "/bin/nshell-test";
                text =
                  builtins.replaceStrings
                    [
                      (builtins.fromJSON ''"\u0024{CL_SOURCE_REGISTRY:+:\u0024CL_SOURCE_REGISTRY}"'')
                      ":/nix/store/"
                    ]
                    [
                      ""
                      "//:/nix/store/"
                    ]
                    (builtins.readFile ctx.generated.apps.test.program)
                  + "\n";
              }
            }/bin/nshell-test";
          };

          # The generated shell, plus the aliases this repository's loop is
          # written in terms of. Appended to the preset's own shellHook rather
          # than replacing it, so the CL_SOURCE_REGISTRY it exports (the
          # derivation's own resolved registry, including check dependencies)
          # is kept.
          devShells.default = ctx.generated.devShells.default.overrideAttrs (previous: {
            shellHook = previous.shellHook + ''
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
          });
        };

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml. The
      # two jobs ci.yml does add are the ones this sandbox cannot host: the
      # real-PTY integration run and the started-binary check on each runner
      # OS.
      extraOutputs =
        ctx:
        let
          delivery = deliveryFor ctx;
          bin = "${delivery}/bin/nshell";
        in
        {
          # The release workflows use an explicit artifact name while the
          # contributor-facing default package remains unchanged. This is an
          # additive output, so it belongs in extraOutputs. Unlike
          # `packages.default` (`delivery`, a Nix-store-relative wrapper),
          # `releaseBundle` is `releaseBundleFor`'s relocatable, portable
          # repackaging of the same dumped image -- see its definition for
          # why the two cannot be the same derivation.
          packages.releaseBundle = releaseBundleFor ctx;

          checks = {
            # The focused cl-weave completion suite (nshell/weave), through the
            # same script a developer runs locally. `checks.default` covers
            # run-tests.lisp and is generated.
            weave = ctx.cl.mkScriptCheck {
              drv = ctx.package;
              entryPoint = "scripts/weave.lisp";
              name = "nshell-weave-suite";
              timeoutSeconds = 1800;
            };

            # Generate the sb-cover report and enforce the configured source
            # expression minimum. The report also records the distance from
            # the aspirational 100% target without making an unsupported
            # claim that structural sb-cover forms are executable.
            coverage = ctx.cl.mkScriptCheck {
              drv = ctx.package;
              entryPoint = "scripts/coverage.lisp";
              name = "nshell-src-coverage";
              timeoutSeconds = 1800;
            };

            # Verify the delivered package compiles and the image dumps.
            build = delivery;

            # Smoke test: the dumped image runs real shell operations. This is
            # the in-sandbox half; ci.yml's `binary` job repeats it outside the
            # sandbox, where a genuine terminal exists.
            smoke-test = ctx.pkgs.runCommand "nshell-smoke-test" { buildInputs = [ delivery ]; } ''
              set -euo pipefail

              echo "=== nshell smoke test ==="

              run_nshell() {
                "${ctx.pkgs.coreutils}/bin/timeout" --foreground --kill-after=30s 180s "${bin}"
              }

              # Verify binary exists and is executable
              test -x "${bin}" || {
                echo "FAIL: binary not found or not executable at ${bin}"
                exit 1
              }
              echo "PASS: binary exists and is executable"

              # Test 1: echo a string
              echo "echo hello" | run_nshell > output 2>&1
              grep -q hello output || {
                echo "FAIL: 'echo hello' - expected 'hello' in output"
                echo "got: $(cat output)"
                exit 1
              }
              echo "PASS: echo hello"

              # Test 2: pipeline
              echo "echo hello world | grep world" | run_nshell > output2 2>&1
              grep -q world output2 || {
                echo "FAIL: pipeline grep - expected 'world' in output"
                echo "got: $(cat output2)"
                exit 1
              }
              echo "PASS: pipeline with grep"

              # Test 3: cd and pwd (verify pwd output is correct, not matching prompt echo)
              echo "cd /tmp ; pwd" | run_nshell > output3 2>&1
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
          };
        };
    };
}
