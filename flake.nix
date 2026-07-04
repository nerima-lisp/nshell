{
  description = "nshell - Modern interactive shell in Common Lisp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
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
        in
        {
          default = pkgs.sbcl.buildASDFSystem {
            pname = "nshell";
            version = "0.4.0";
            src = src;
            systems = [ "nshell" ];
            lispLibs = [];
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
            lispLibs = [ pkgs.sbclPackages.fiveam ];
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
      in {
        # Verify the default package compiles and builds successfully
        build = self.packages.${system}.default;

        # Run the full test suite
        test = pkgs.sbcl.buildASDFSystem {
          pname = "nshell-test-check";
          version = "0.4.0";
          src = src;
          systems = [ "nshell/test" ];
          lispLibs = [ pkgs.sbclPackages.fiveam ];
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
        in
        {
          default = pkgs.mkShell {
            packages = [
              (pkgs.sbcl.withPackages (ps: [ ps.fiveam ]))
            ];
            shellHook = ''
              export CL_SOURCE_REGISTRY=$PWD
              alias test='sbcl --noinform --eval "(require :asdf)" --eval "(push (truename \"./\") asdf:*central-registry*)" --eval "(asdf:test-system :nshell/test)" --quit'
              echo ""
              echo "nshell development environment"
              echo "  test  - Run the nshell test suite"
              echo "  sbcl  - Interactive Common Lisp (with fiveam)"
              echo ""
            '';
          };
        });
    };
}
