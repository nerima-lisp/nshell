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
      url = "github:nerima-lisp/cl-prolog-kit/v1.7.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-ollama-kit = {
      url = "github:nerima-lisp/cl-ollama-kit/v3.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-codec-kit.follows = "cl-codec-kit";
      inputs.cl-concurrent-kit.follows = "cl-concurrent-kit";
      inputs.cl-date-kit.follows = "cl-date-kit";
      inputs.cl-deflate-kit.follows = "cl-deflate-kit";
      inputs.cl-hpack-codec-kit.follows = "cl-hpack-codec-kit";
      inputs.cl-host-kit.follows = "cl-host-kit";
      inputs.cl-http-kit.follows = "cl-http-kit";
      inputs.cl-http-message-kit.follows = "cl-http-message-kit";
      inputs.cl-json-kit.follows = "cl-json-kit";
      inputs.cl-resilience-kit.follows = "cl-resilience-kit";
      inputs.cl-sse-kit.follows = "cl-sse-kit";
    };

    # cl-weave is the testing framework behind both suites.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
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
      url = "github:nerima-lisp/cl-cli/v1.4.1";
      flake = false;
    };
    cl-tty-kit = {
      url = "github:nerima-lisp/cl-tty-kit/v1.8.0";
      flake = false;
    };
    cl-process-kit = {
      url = "github:nerima-lisp/cl-process-kit/v3.4.4";
      flake = false;
    };
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v2.2.0";
      flake = false;
    };
    cl-regex-kit = {
      url = "github:nerima-lisp/cl-regex-kit/v2.2.0";
      flake = false;
    };
    # cl-history-kit backs the command-history store, search, and recall
    # navigation cursor; nshell itself keeps only the tokenizer-coupled
    # `!$`/Alt-. last-argument extraction on top of it.
    cl-history-kit = {
      url = "github:nerima-lisp/cl-history-kit/v1.1.0";
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
      url = "github:nerima-lisp/cl-codec-kit/v0.6.0";
      flake = false;
    };
    cl-deflate-kit = {
      url = "github:nerima-lisp/cl-deflate-kit/v0.4.0";
      flake = false;
    };
    cl-hpack-codec-kit = {
      url = "github:nerima-lisp/cl-hpack-codec-kit/v1.1.2";
      flake = false;
    };
    cl-http-kit = {
      url = "github:nerima-lisp/cl-http-kit/v0.5.1";
      flake = false;
    };
    cl-http-message-kit = {
      url = "github:nerima-lisp/cl-http-message-kit/v2.0.1";
      flake = false;
    };
    cl-resilience-kit = {
      url = "github:nerima-lisp/cl-resilience-kit/v2.0.0";
      flake = false;
    };
    cl-sse-kit = {
      url = "github:nerima-lisp/cl-sse-kit/v1.2.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.8.0";
      flake = false;
    };
    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.3.0";
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
      cl-ollama-kit,
      cl-weave,
      paredit-cli,
      cl-parser-kit,
      cl-dataflow-kit,
      cl-host-kit,
      cl-boundary-kit,
      cl-cli,
      cl-tty-kit,
      cl-process-kit,
      cl-log-kit,
      cl-regex-kit,
      cl-history-kit,
      cl-codec-kit,
      cl-concurrent-kit,
      cl-json-kit,
      cl-date-kit,
      cl-deflate-kit,
      cl-hpack-codec-kit,
      cl-http-kit,
      cl-http-message-kit,
      cl-resilience-kit,
      cl-sse-kit,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;
      loginEnvironment = ''
        nshell_login_environment() {
          nshell_saved_user_set=''${USER+x}
          nshell_saved_user=''${USER-}
          nshell_saved_shell_set=''${SHELL+x}
          nshell_saved_shell=''${SHELL-}
          nshell_saved_shlvl=$SHLVL
          nix_darwin_environment=

          # Login profiles may call system commands before they finish setting PATH.
          PATH="''${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
          export PATH

          if [ -r /etc/zshenv ]; then
            while IFS= read -r line; do
              case "$line" in
                *". /nix/store/"*-set-environment)
                  candidate=''${line#*". "}
                  case "$candidate" in
                    /nix/store/*-set-environment)
                      nix_darwin_environment=$candidate
                      break
                      ;;
                  esac
                  ;;
              esac
            done < /etc/zshenv
          fi
          if [ -n "''${nix_darwin_environment-}" ] && [ -r "$nix_darwin_environment" ]; then
            . "$nix_darwin_environment" >/dev/null 2>&1
          fi
          if [ -r /etc/profile ]; then
            . /etc/profile >/dev/null 2>&1
          fi

          if [ -n "''${USER-}" ] && [ -r "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
            . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" >/dev/null 2>&1
          elif [ -n "''${HOME-}" ] && [ -r "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
            . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" >/dev/null 2>&1
          fi
          if [ -n "''${HOME-}" ] && [ -r "$HOME/.profile" ]; then
            . "$HOME/.profile" >/dev/null 2>&1
          fi

          if [ "$nshell_saved_user_set" = x ]; then
            USER=$nshell_saved_user
            export USER
          fi
          if [ "$nshell_saved_shell_set" = x ]; then
            SHELL=$nshell_saved_shell
            export SHELL
          fi
          SHLVL=$nshell_saved_shlvl
          export SHLVL
        }
      '';
      deliveryRun = lib.escapeShellArg ''
        case "''${1-}" in
          -c)
            exec /bin/sh "$@"
            ;;
        esac

        ${loginEnvironment}
        case "''${1-}" in
          -lc)
            nshell_login_environment
            shift
            set -- -c "$@"
            exec /bin/sh "$@"
            ;;
          -ilc)
            nshell_login_environment
            ;;
          -l|--login)
            nshell_login_environment
            if [ "''${2-}" = -c ]; then
              shift
              exec /bin/sh "$@"
            fi
            ;;
          -i)
            case "''${2-}" in
              -l|--login) nshell_login_environment ;;
            esac
            ;;
        esac
      '';

      # Scenario checks cover Linux and Apple Silicon macOS; release checks
      # remain on Ubuntu x86_64.
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
              system ? name,
              dependencies ? [ ],
              patches ? [ ],
            }:
            ctx.cl.lispDerivation {
              pname = name;
              # Read out of the sibling's own .asd, never written here. The
              # previously hand-written version strings had silently drifted,
              # and a number nobody updates is worse than no number.
              version = ctx.cl.fromAsdSystem "${source}/${name}.asd";
              src = source;
              lispSystem = system;
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
          clOllamaKit = sibling {
            name = "cl-ollama-kit";
            source = cl-ollama-kit;
            dependencies = [
              clHttpKit
              clHttpMessageKit
              clSseKit
              clCodecKit
              clConcurrentKit
              clJsonKit
            ];
          };
          clDeflateKit = sibling {
            name = "cl-deflate-kit";
            source = cl-deflate-kit;
          };
          clHpackCodecKit = sibling {
            name = "cl-hpack-codec-kit";
            source = cl-hpack-codec-kit;
          };
          clHttpMessageKit = sibling {
            name = "cl-http-message-kit";
            source = cl-http-message-kit;
            dependencies = [ clHpackCodecKit ];
          };
          clHttpKit = sibling {
            name = "cl-http-kit";
            system = "cl-http-kit/client";
            source = cl-http-kit;
            dependencies = [
              clHttpMessageKit
              clHpackCodecKit
              clCodecKit
              clDeflateKit
            ];
          };
          clResilienceKit = sibling {
            name = "cl-resilience-kit";
            source = cl-resilience-kit;
            dependencies = [
              clConcurrentKit
              clDateKit
            ];
          };
          clSseKit = sibling {
            name = "cl-sse-kit";
            source = cl-sse-kit;
            dependencies = [
              clCodecKit
              clHttpMessageKit
              clResilienceKit
            ];
          };
          clParserKit = sibling {
            name = "cl-parser-kit";
            source = cl-parser-kit;
            patches = [ ./nix/patches/cl-parser-kit-prolog-kit-name.patch ];
          };
          clDataflow = sibling {
            name = "cl-dataflow-kit";
            source = cl-dataflow-kit;
            patches = [ ./nix/patches/cl-dataflow-kit-writable-snapshot-fixture.patch ];
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
            patches = [ ./nix/patches/cl-boundary-kit-prolog-kit-name.patch ];
            dependencies = [ clHostKit ];
          };
          clConcurrentKit = sibling {
            name = "cl-concurrent-kit";
            source = cl-concurrent-kit;
            dependencies = [ clDateKit ];
          };
          clJsonKit = sibling {
            name = "cl-json-kit";
            source = cl-json-kit;
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
          clRegexKit = sibling {
            name = "cl-regex-kit";
            source = cl-regex-kit;
            dependencies = [
              clConcurrentKit
              clParserKit
            ];
          };
          clHistoryKit = sibling {
            name = "cl-history-kit";
            source = cl-history-kit;
          };
        };

      ptyBootstrapFor =
        ctx:
        ctx.pkgs.stdenv.mkDerivation {
          pname = "nshell-pty-bootstrap";
          version = ctx.cl.fromAsdSystem "${./nshell.asd}";
          dontUnpack = true;
          buildPhase = ''
            runHook preBuild
            $CC -std=c11 -O2 -Wall -Wextra -Werror ${./src/infrastructure/acl/pty-exec-bootstrap.c} -o nshell-pty-bootstrap
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 nshell-pty-bootstrap "$out/bin/nshell-pty-bootstrap"
            runHook postInstall
          '';
        };

      ptyBootstrapPathFor = ctx: "${ptyBootstrapFor ctx}/bin/nshell-pty-bootstrap";

      ptyBootstrapEnvironmentFor =
        ctx:
        ctx.pkgs.lib.optionalAttrs ctx.pkgs.stdenv.hostPlatform.isDarwin {
          NSHELL_PTY_BOOTSTRAP = ptyBootstrapPathFor ctx;
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
            wrapProgram "$out/bin/nshell" --inherit-argv0 \
              --run ${deliveryRun} \
              ${ctx.pkgs.lib.optionalString ctx.pkgs.stdenv.hostPlatform.isDarwin "--set NSHELL_PTY_BOOTSTRAP ${ptyBootstrapPathFor ctx}"}
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
            cp ${cl-history-kit}/LICENSE "$out/LICENSES/CL-HISTORY-KIT-LICENSE"
            cp ${cl-codec-kit}/LICENSE "$out/LICENSES/CL-CODEC-KIT-LICENSE"
            cp ${cl-date-kit}/LICENSE "$out/LICENSES/CL-DATE-KIT-LICENSE"
            cp ${cl-concurrent-kit}/LICENSE "$out/LICENSES/CL-CONCURRENT-KIT-LICENSE"
            cp ${cl-json-kit}/LICENSE "$out/LICENSES/CL-JSON-KIT-LICENSE"
            cp ${cl-regex-kit}/LICENSE "$out/LICENSES/CL-REGEX-KIT-LICENSE"
            cp ${cl-ollama-kit}/LICENSE "$out/LICENSES/CL-OLLAMA-KIT-LICENSE"
            cp ${cl-http-kit}/LICENSE "$out/LICENSES/CL-HTTP-KIT-LICENSE"
            cp ${cl-http-message-kit}/LICENSE "$out/LICENSES/CL-HTTP-MESSAGE-KIT-LICENSE"
            cp ${cl-sse-kit}/LICENSE "$out/LICENSES/CL-SSE-KIT-LICENSE"
            cp ${cl-resilience-kit}/LICENSE "$out/LICENSES/CL-RESILIENCE-KIT-LICENSE"
            cp ${cl-deflate-kit}/LICENSE "$out/LICENSES/CL-DEFLATE-KIT-LICENSE"
            cp ${cl-hpack-codec-kit}/LICENSE "$out/LICENSES/CL-HPACK-CODEC-KIT-LICENSE"
            cp ${./man/nshell.1} "$out/share/man/man1/nshell.1"
          '';
        });

      # Script-mode probes run with one closed PATH. Stub `last` so host login
      # records cannot vary the PATH-first compatibility case.
      specBinEnvFor =
        ctx:
        let
          lastStub = ctx.pkgs.writeShellScriptBin "last" ''
            printf '%s\n' 'nshell-spec-last'
          '';
        in
        ctx.pkgs.buildEnv {
          name = "nshell-spec-bin";
          paths = [
            ctx.pkgs.coreutils
            ctx.pkgs.bash
            ctx.pkgs.findutils
            lastStub
          ];
          pathsToLink = [ "/bin" ];
        };

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
            # `ctx.package` -- is the dumped, `:compression nil` image:
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
              chmod -R u+w $out
              cp ${builtImage} $out/libexec/nshell
              chmod u+w $out/libexec/nshell
              # patchelf rewrites the ELF layout and discards SBCL's appended
              # core. Patch only PT_INTERP through a temporary patchelf copy,
              # preserving the delivered image byte-for-byte otherwise.
              cp $out/libexec/nshell $out/libexec/nshell-interp
              interpreter=/lib64/ld-linux-x86-64.so.2
              patchelf --set-interpreter "$interpreter" \
                $out/libexec/nshell-interp
              read -r target_offset_hex target_size_hex <<EOF
              $(readelf -lW $out/libexec/nshell | awk '$1 == "INTERP" { print $2, $5 }')
              EOF
              read -r source_offset_hex source_size_hex <<EOF
              $(readelf -lW $out/libexec/nshell-interp | awk '$1 == "INTERP" { print $2, $5 }')
              EOF
              target_offset=$((target_offset_hex))
              target_size=$((target_size_hex))
              source_offset=$((source_offset_hex))
              source_size=$((source_size_hex))
              test -n "$target_offset" -a -n "$target_size" \
                -a -n "$source_offset" -a -n "$source_size"
              interpreter_size=$(printf '%s' "$interpreter" | wc -c)
              test $((interpreter_size + 1)) -le "$target_size" || {
                echo "PT_INTERP segment is too small for $interpreter" >&2
                exit 1
              }
              dd if=$out/libexec/nshell-interp of=$out/libexec/nshell \
                bs=1 skip="$source_offset" seek="$target_offset" \
                count="$target_size" conv=notrunc status=none
              rm $out/libexec/nshell-interp
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
              export PATH="$root/bin:$PATH"
              ${loginEnvironment}
              if [ -z "''${BASH_VERSION-}" ] \
                && [ -z "''${ZSH_VERSION-}" ] \
                && [ -z "''${KSH_VERSION-}" ]; then
                shlvl="''${SHLVL-0}"
                case "$shlvl" in
                  *[!0-9]*) shlvl=0 ;;
                esac
                while [ "$shlvl" != "''${shlvl#0}" ]; do
                  shlvl="''${shlvl#0}"
                done
                [ -n "$shlvl" ] || shlvl=0
                SHLVL=$((shlvl + 1))
                export SHLVL
              fi
              case "''${1-}" in
                -c)
                  exec /bin/sh "$@"
                  ;;
                -lc)
                  nshell_login_environment
                  shift
                  set -- -c "$@"
                  exec /bin/sh "$@"
                  ;;
                -ilc)
                  nshell_login_environment
                  ;;
                -l|--login)
                  nshell_login_environment
                  if [ "''${2-}" = -c ]; then
                    shift
                    exec /bin/sh "$@"
                  fi
                  ;;
                -i)
                  case "''${2-}" in
                    -l|--login) nshell_login_environment ;;
                  esac
                  ;;
              esac
              exec "$root/lib/ld-linux-x86-64.so.2" \
                --library-path "$root/lib" --argv0 "$root/libexec/nshell" \
                "$root/libexec/nshell" "$@"
              EOF

              # SBCL records source locations in its appended core. Dynamic
              # dependencies have already been made relative above, so only
              # these non-runtime metadata strings remain. Keep the prefix
              # length unchanged to preserve binary offsets and layouts.
              find $out -type f -exec \
                perl -0777 -pi -e 's{/nix/store/}{/non/store/}g' {} +
              chmod +x $out/bin/nshell \
                $out/libexec/nshell $out/lib/ld-linux-x86-64.so.2
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
      # Read by the builtin inventory and error-code page consistency tests,
      # the bug-report golden test, the response envelope schema
      # conformance test, and the machine --json golden tests, which read
      # the examples from the two design documents.
      # Language conformance tests also read the v0.7 probe fixture.
      sourceInclude = [
        ./docs/src/reference/builtins.md
        ./docs/src/reference/error-codes.md
        ./docs/design/conformance/language-probes-v0.7.0.json
        ./t/golden/bug-report.txt
        ./docs/design/conformance/envelope.schema.json
        ./docs/design/proposal/02-machine-interface.md
        ./docs/design/ux/U6-response-envelope.md
      ];

      lispDependencies =
        ctx: with siblingsFor ctx; [
          clProlog
          clParserKit
          clDataflow
          clBoundaryKit
          clCli
          clTtyKit
          clRegexKit
          clHistoryKit
          clHostKit
          clCodecKit
          clConcurrentKit
          clDateKit
          clJsonKit
          clOllamaKit
        ];

      # cl-weave is a dependency of `nshell/test` and `nshell/weave` only (see
      # nshell.asd), so it is a CHECK dependency: it must not enter the
      # delivered binary's closure. cl-prolog-kit/weave, which the nshell/weave
      # suite also loads, needs nothing extra -- it is a secondary system of
      # cl-prolog-kit, whose whole source tree is already on the registry above.
      lispCheckDependencies = ctx: [ (siblingsFor ctx).clWeave ];

      packageArgs =
        ctx:
        {
          nativeBuildInputs = [
            ctx.pkgs.coreutils
          ]
          ++ ctx.pkgs.lib.optionals ctx.pkgs.stdenv.hostPlatform.isDarwin [
            (ptyBootstrapFor ctx)
          ];
        }
        // ptyBootstrapEnvironmentFor ctx;

      # Drives the test checks from this one number, so the contributor-facing
      # gate and CI cannot drift apart. Bounded so a hung suite fails in half an hour
      # rather than occupying a runner until GitHub's six-hour job ceiling.
      timeoutSeconds = 1800;

      # The delivered `nshell` binary: `packages.default`, `apps.default` and
      # `apps.nshell`, all built from the same `lispDerivation` arguments as
      # `packages.nshell`. Nothing here repeats what nshell.asd already
      # declares -- `:build-operation "program-op"`, `:build-pathname "nshell"`
      # and `:entry-point "nshell:main"` live in the system definition, as does
      # the `:perform` that dumps the image with `:compression nil` (the one
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
      devShellPackages =
        ctx:
        [
          cl-weave.packages.${ctx.system}.default
          paredit-cli.packages.${ctx.system}.default
        ]
        # The dependency gate rejects skipped real-shell verification tests.
        ++ lib.optionals ctx.pkgs.stdenv.hostPlatform.isLinux (
          with ctx.pkgs;
          [
            bash
            zsh
            fish
            ghq
            mandoc
            nushell
            powershell
            elvish
          ]
        );

      overrideOutputs =
        ctx:
        let
          delivery = deliveryFor ctx;
          specBinEnv = specBinEnvFor ctx;
          app = ctx.cl.mkApp { drv = delivery; };
          testApp = ctx.pkgs.writeShellApplication {
            name = "nshell-test";
            runtimeInputs = ctx.pkgs.lib.optionals ctx.pkgs.stdenv.hostPlatform.isDarwin [
              (ptyBootstrapFor ctx)
            ];
            text = ''
              ${ctx.pkgs.lib.optionalString ctx.pkgs.stdenv.hostPlatform.isDarwin "export NSHELL_PTY_BOOTSTRAP=${ptyBootstrapPathFor ctx}"}
              exec ${ctx.generated.apps.test.program} "$@"
            '';
          };
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
            program = "${testApp}/bin/nshell-test";
          };

          checks.default = ctx.generated.checks.default.overrideAttrs (
            previous:
            {
              # git: the machine --json golden tests run it in a temporary repository.
              nativeBuildInputs = (previous.nativeBuildInputs or [ ]) ++ [
                ctx.pkgs.coreutils
                ctx.pkgs.git
              ];
              NSHELL_BIN = "${delivery}/bin/nshell";
              postCheck =
                (ctx.pkgs.lib.optionalString
                  ((previous.postCheck or null) != null)
                  "${previous.postCheck}\n")
                + ''
                  export PATH="${specBinEnv}/bin"
                  printf 'NSHELL_CHECK_PATH=%s\n' "$PATH"
                  ${ctx.pkgs.sbcl}/bin/sbcl --noinform --non-interactive \
                    --eval '(require :asdf)' \
                    --eval '(load "scripts/asdf-runtime.lisp")' \
                    --eval '(nshell-configure-writable-asdf-output)' \
                    --eval '(let* ((root (uiop:pathname-directory-pathname (truename "nshell.asd")))
                                   (parent (uiop:pathname-parent-directory-pathname root)))
                              (if (uiop:getenv "CL_SOURCE_REGISTRY")
                                  (progn (asdf:clear-source-registry)
                                         (asdf:initialize-source-registry))
                                  (asdf:initialize-source-registry
                                   `(:source-registry
                                     (:directory ,root)
                                     (:tree ,parent)
                                     :inherit-configuration))))' \
                    --eval '(setf asdf:*compile-file-warnings-behaviour* :warn asdf:*compile-file-failure-behaviour* :warn)' \
                    --eval '(asdf:load-asd (truename "nshell.asd"))' \
                    --eval '(asdf:test-system "nshell/spec")'
                '';
            }
            // ptyBootstrapEnvironmentFor ctx
          );

          # The generated shell, plus the aliases this repository's loop is
          # written in terms of. Appended to the preset's own shellHook rather
          # than replacing it, so the CL_SOURCE_REGISTRY it exports (the
          # derivation's own resolved registry, including check dependencies)
          # is kept.
          devShells.default = ctx.generated.devShells.default.overrideAttrs (
            previous:
            {
              TZDIR = "${ctx.pkgs.tzdata}/share/zoneinfo";
              # cl-dataflow-kit/test and cl-cli/test/shell-verification need process-kit and its log-kit dependency.
              NSHELL_DEPENDENCY_SOURCE_REGISTRY = "${cl-process-kit}//:${cl-log-kit}//";
              shellHook = previous.shellHook + ''
                export NSHELL_ROOT=$PWD
                alias test='cd "$NSHELL_ROOT" && sbcl --script "$NSHELL_ROOT/run-tests.lisp"'
                alias test-fast='cd "$NSHELL_ROOT" && sbcl --script "$NSHELL_ROOT/scripts/test-fast.lisp"'
                alias cov='cd "$NSHELL_ROOT" && NSHELL_COVERAGE_DIR="$NSHELL_ROOT/coverage" sbcl --script "$NSHELL_ROOT/scripts/coverage.lisp"'
                alias weave='cd "$NSHELL_ROOT" && sbcl --script "$NSHELL_ROOT/scripts/weave.lisp"'
                echo ""
                echo "nshell development environment"
                echo "  test  - Run the full nshell suite (cl-weave, nshell/test)"
                echo "  test-fast - Run unit, main and static checks, excluding slow tests"
                echo "  weave - Run the focused completion suite (nshell/weave)"
                echo "  cov     - Run the test suite and write HTML coverage to coverage/"
                echo "  sbcl  - Interactive Common Lisp (with cl-weave)"
                echo ""
              '';
            }
            // ptyBootstrapEnvironmentFor ctx
          );

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
          q08FaultSource =
            ctx.pkgs.runCommand "nshell-q08-fault-source"
              {
                nativeBuildInputs = [
                  ctx.pkgs.python3
                  paredit-cli.packages.${ctx.system}.default
                ];
              }
              ''
                python3 ${./t/scenarios/Q08/prepare-fault-source.py} ${ctx.src} "$out"
              '';
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

          # Q03 uses a real storage-condition without imposing a process-wide
          # address-space limit. Keep its small dynamic space in a separate
          # executable so the default deliverable retains its normal capacity.
          packages.q03 = ctx.cl.mkExecutable {
            args = ctx.lispDerivationArgs;
            dynamicSpaceSize = 256;
            programPath = "src/nshell";
          };

          packages.q08-fault-injected = ctx.cl.mkExecutable {
            args = ctx.lispDerivationArgs // {
              pname = "nshell-q08-fault-injected";
              src = q08FaultSource;
            };
            programPath = "src/nshell";
          };

          devShells.scenarios = ctx.pkgs.mkShell {
            nativeBuildInputs = with ctx.pkgs; [
              python3
              sbcl
              tmux
              coreutils
              bash
              git
            ];
            NSHELL_SCENARIO_EXTRA_PATH = ctx.pkgs.lib.makeBinPath [
              ctx.pkgs.tmux
              ctx.pkgs.coreutils
              ctx.pkgs.bash
              ctx.pkgs.git
            ];
          };

          checks = {
            # The focused cl-weave completion suite (nshell/weave), through the
            # same script a developer runs locally. `checks.default` covers
            # run-tests.lisp and is generated.
            weave =
              (ctx.cl.mkScriptCheck {
                drv = ctx.package;
                entryPoint = "scripts/weave.lisp";
                name = "nshell-weave-suite";
                timeoutSeconds = 1800;
              }).overrideAttrs
                (_: ptyBootstrapEnvironmentFor ctx);

            # Generate the sb-cover report and enforce the configured source
            # expression minimum. The report also records the distance from
            # the aspirational 100% target without making an unsupported
            # claim that structural sb-cover forms are executable.
            coverage =
              (ctx.cl.mkScriptCheck {
                drv = ctx.package;
                entryPoint = "scripts/coverage.lisp";
                name = "nshell-src-coverage";
                timeoutSeconds = 1800;
              }).overrideAttrs
                (
                  previous:
                  {
                    # The machine --json golden tests run git in a temporary repository.
                    nativeBuildInputs = (previous.nativeBuildInputs or [ ]) ++ [ ctx.pkgs.git ];
                  }
                  // ptyBootstrapEnvironmentFor ctx
                );

            # Keep every Lisp source structurally readable before the more
            # expensive ASDF checks run. This is the same paredit executable
            # used by the contributor workflow, applied one file at a time so
            # a malformed form cannot disappear in an empty selector.
            syntax =
              ctx.pkgs.runCommand "nshell-lisp-syntax"
                {
                  nativeBuildInputs = [ paredit-cli.packages.${ctx.system}.default ];
                }
                ''
                  set -euo pipefail

                  file_count=0
                  while IFS= read -r file; do
                    TERM=dumb paredit inspect check --file "$file"
                    file_count=$((file_count + 1))
                  done < <(find ${formatSource}/src ${formatSource}/t ${formatSource}/scripts \
                    -type f -name '*.lisp' -print)

                  test "$file_count" -gt 0
                  printf '%s\n' "$file_count Lisp sources passed paredit syntax check"
                  touch "$out"
                '';

            # Verify the delivered package compiles and the image dumps.
            build = delivery;

            # Batch scenarios run inside the Nix sandbox; PTY scenarios need
            # a controlling terminal and run in the non-sandboxed CI workflow.
            scenarios-batch =
              ctx.pkgs.runCommand "nshell-scenarios-batch"
                {
                  buildInputs = [ delivery ];
                  nativeBuildInputs = [
                    ctx.pkgs.python3
                    ctx.pkgs.coreutils
                    ctx.pkgs.bash
                  ];
                  NSHELL_SCENARIO_EXTRA_PATH = ctx.pkgs.lib.makeBinPath [
                    ctx.pkgs.coreutils
                    ctx.pkgs.bash
                  ];
                }
                ''
                  set -euo pipefail

                  python3 ${self}/scripts/test-run-scenarios.py
                  python3 ${self}/scripts/run-scenarios.py --binary ${bin} --mode batch
                  python3 ${self}/scripts/run-scenarios.py --binary ${bin} --mode source
                  touch "$out"
                '';

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
