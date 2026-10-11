#!/usr/bin/env bash
# CL_SOURCE_REGISTRY is supplied by the pinned Nix check/dev environment.
# Run every suite in a separate image; never merge global cl-weave registries.
set -euo pipefail

dependency_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
dependency_sbcl=${SBCL:-sbcl}

if [[ ${1:-} == --list ]]; then
  "$dependency_sbcl" --noinform --script "$dependency_script_dir/test-dependencies.lisp" "$@"
  printf '%s\n' cl-process-kit/native-spawn-test
  exit 0
fi

if (( $# == 0 )); then
  dependency_systems=$("$dependency_sbcl" --noinform --script "$dependency_script_dir/test-dependencies.lisp" --list)
  while IFS= read -r dependency_system; do
    [[ -n $dependency_system ]] || continue
    set -- "$@" "$dependency_system"
  done <<< "$dependency_systems"
fi
(( $# > 0 )) || { echo 'No dependency suites selected' >&2; exit 1; }

dependency_needs_native=0
dependency_has_native=0
for dependency_system in "$@"; do
  case $dependency_system in
    cl-process-kit/test|cl-process-kit/pty-test) dependency_needs_native=1 ;;
    cl-process-kit/native-spawn-test) dependency_has_native=1 ;;
  esac
done
if (( dependency_needs_native && ! dependency_has_native )); then
  set -- "$@" cl-process-kit/native-spawn-test
fi

# A private cache avoids both read-only store writes and other sessions' caches.
dependency_cache=$(mktemp -d "${TMPDIR:-/tmp}/nshell-dependency-tests.XXXXXXXX")
export NSHELL_ASDF_OUTPUT_DIR="$dependency_cache/asdf/"
"$dependency_sbcl" --noinform --script "$dependency_script_dir/test-dependency-registry.lisp"
dependency_failed=0
dependency_passed=0
for dependency_system in "$@"; do
  if [[ $dependency_system == cl-process-kit/native-spawn-test ]]; then
    dependency_command=("$BASH" "$dependency_script_dir/test-native-spawn.sh")
  else
    dependency_command=("$dependency_sbcl" --noinform --script "$dependency_script_dir/test-dependencies.lisp" "$dependency_system")
  fi
  if "${dependency_command[@]}"; then
    dependency_passed=$((dependency_passed + 1))
  else
    dependency_exit=$?
    printf 'dependency-process system=%s exit=%s\n' "$dependency_system" "$dependency_exit" >&2
    dependency_failed=$((dependency_failed + 1))
  fi
done
printf 'dependency-suites selected=%s pass=%s failed=%s cache=%s\n' "$#" "$dependency_passed" "$dependency_failed" "$dependency_cache"
(( dependency_failed == 0 ))
