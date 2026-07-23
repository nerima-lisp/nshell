{
  description = "nshell - Modern interactive shell in Common Lisp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # cl-weave is the testing framework behind both suites.  Its package ships
    # loadable ASDF source under share/common-lisp/source, and a `cl-weave`
    # CLI, both of which the suites and dev shell consume.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, cl-prolog, cl-weave }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      sourceFor = pkgs: pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          (pkgs.lib.cleanSourceFilter path type)
          && (let
            name = builtins.baseNameOf path;
          in
            !(pkgs.lib.hasSuffix ".fasl" name
              || pkgs.lib.hasSuffix ".cfasl" name
              || pkgs.lib.hasSuffix ".dfsl" name
              || pkgs.lib.hasSuffix ".ufasl" name
              || pkgs.lib.hasSuffix ".core" name
              || pkgs.lib.hasSuffix ".o" name));
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          src = sourceFor pkgs;
          clProlog = cl-prolog.packages.${system}.default;
          # cl-weave built as an ASDF lisp library from its source input, so
          # nshell/test (now cl-weave-based) can list it in lispLibs.
          clWeaveLib = pkgs.sbcl.buildASDFSystem {
            pname = "cl-weave";
            version = "0.8.0";
            src = cl-weave;
            systems = [ "cl-weave" ];
          };
        in
        {
          default = pkgs.sbcl.buildASDFSystem {
            pname = "nshell";
            version = "0.4.0";
            src = src;
            systems = [ "nshell" ];
            lispLibs = [ clProlog ];
            buildScript = pkgs.writeText "build-nshell.lisp" ''
              (require :asdf)
              (setf asdf:*compile-file-warnings-behaviour* :warn)
              (setf asdf:*compile-file-failure-behaviour* :warn)
              (push (truename "./") asdf:*central-registry*)
              (asdf:load-system :nshell)
              (sb-ext:save-lisp-and-die "nshell"
                :executable t
                :compression t
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
            meta = with pkgs.lib; {
              description = "Modern, fish-inspired interactive shell written in Common Lisp";
              homepage = "https://github.com/takeokunn/nshell";
              license = licenses.mit;
              platforms = systems;
              mainProgram = "nshell";
            };
          };

          test = pkgs.sbcl.buildASDFSystem {
            pname = "nshell-test";
            version = "0.4.0";
            src = src;
            systems = [ "nshell/test" ];
            lispLibs = [
              clProlog
              clWeaveLib
            ];
          };
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nshell";
        };
      });

      checks = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        src = sourceFor pkgs;
        bin = "${self.packages.${system}.default}/bin/nshell";
        clProlog = cl-prolog.packages.${system}.default;
        clWeave = cl-weave.packages.${system}.default;
        clWeaveLib = pkgs.sbcl.buildASDFSystem {
          pname = "cl-weave";
          version = "0.8.0";
          src = cl-weave;
          systems = [ "cl-weave" ];
        };
      in {
        # Verify the default package compiles and builds successfully
        build = self.packages.${system}.default;

        # Run the cl-weave suite (nshell/weave).  Point CL_SOURCE_REGISTRY at
        # the raw dependency checkouts: nshell/weave also needs cl-prolog/weave,
        # which lives in the cl-prolog repository, and every .asd (cl-weave.asd,
        # cl-prolog.asd, nshell.asd) sits at the root of its source tree.
        weave = pkgs.runCommand "nshell-weave-suite" {
          nativeBuildInputs = [ pkgs.sbcl ];
        } ''
          cp -R ${src} source
          chmod -R u+w source
          cd source
          export HOME="$TMPDIR/home"
          export XDG_CACHE_HOME="$TMPDIR/cache"
          mkdir -p "$HOME" "$XDG_CACHE_HOME"
          export CL_SOURCE_REGISTRY="${cl-weave}//:${cl-prolog}//:$PWD//:"
          sbcl --non-interactive \
            --eval '(require :asdf)' \
            --eval '(setf asdf:*compile-file-warnings-behaviour* :warn)' \
            --eval '(setf asdf:*compile-file-failure-behaviour* :warn)' \
            --eval '(let ((ok (handler-case (asdf:test-system :nshell/weave) (error (e) (format t "FATAL: ~a~%" e) nil)))) (unless ok (sb-ext:quit :unix-status 1)))'
          touch $out
        '';

        # Run the full test suite (cl-weave-backed)
        test = pkgs.sbcl.buildASDFSystem {
          pname = "nshell-test-check";
          version = "0.4.0";
          src = src;
          systems = [ "nshell/test" ];
          lispLibs = [
            clProlog
            clWeaveLib
          ];
          buildScript = pkgs.writeText "run-tests.lisp" ''
            (require :asdf)
            (setf asdf:*compile-file-warnings-behaviour* :warn)
            (setf asdf:*compile-file-failure-behaviour* :warn)
            (push (truename "./") asdf:*central-registry*)
            (let ((result (handler-case (asdf:test-system :nshell/test)
                            (error (e) (format t "FATAL: ~a~%" e) nil))))
              (unless result
                (sb-ext:quit :unix-status 1)))
          '';
        };

        # Smoke test: verify the binary works with basic shell operations
        smoke-test = pkgs.runCommand "nshell-smoke-test" {
          buildInputs = [ self.packages.${system}.default ];
        } ''
          set -euo pipefail

          echo "=== nshell smoke test ==="

          # Verify binary exists and is executable
          test -x "${bin}" || {
            echo "FAIL: binary not found or not executable at ${bin}"
            exit 1
          }
          echo "PASS: binary exists and is executable"

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
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          clWeave = cl-weave.packages.${system}.default;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.sbcl
              cl-prolog.packages.${system}.default
              clWeave
            ];
            shellHook = ''
              # Resolve every dependency from its source checkout: cl-weave,
              # cl-prolog (and the cl-prolog/weave system it ships), and nshell
              # itself.  Each .asd sits at the root of its tree.
              export CL_SOURCE_REGISTRY="${cl-weave}//:${cl-prolog}//:$PWD//:''${CL_SOURCE_REGISTRY:-}"
              export NSHELL_ROOT=$PWD
              alias test='cd "$NSHELL_ROOT" && sbcl --noinform --eval "(require :asdf)" --eval "(push (truename \"./\") asdf:*central-registry*)" --eval "(asdf:test-system :nshell/test)" --quit'
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
        });
    };
}
