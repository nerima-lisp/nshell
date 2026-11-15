#!/usr/bin/env bash
# Run the in-process benchmarks of bench/ (completion API fixtures and, when a
# binary is given, the process-launch benchmark) against one nshell source tree.
#
# Usage:
#   scripts/perf/legacy-bench.sh SOURCE_TREE OUT.jsonl [NSHELL_BINARY]
#
# The nshell system is loaded from SOURCE_TREE; the benchmark code is compiled
# from the bench/ directory of the checkout this script lives in, as
# b3-measure.sh does, so a tree whose own bench/ no longer loads can still be
# measured. Without NSHELL_BINARY only the completion benchmarks run.
#
# Needs SBCL (B3_SBCL, else sbcl on PATH) and CL_SOURCE_REGISTRY naming the
# toolkit dependencies. Compiled output and caches go to a temporary directory.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf 'usage: %s SOURCE_TREE OUT.jsonl [NSHELL_BINARY]\n' "$0" >&2
  exit 2
fi
tree=$(cd -- "$1" && pwd -P)
out_dir=$(cd -- "$(dirname -- "$2")" && pwd -P)
output=$out_dir/$(basename -- "$2")
binary=${3:-}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
checkout=$(cd -- "$script_dir/../.." && pwd -P)
sbcl=${B3_SBCL:-sbcl}

if ! command -v "$sbcl" >/dev/null 2>&1; then
  printf 'legacy-bench: %s not found; run inside nix develop or set B3_SBCL\n' "$sbcl" >&2
  exit 2
fi
if [[ -z ${CL_SOURCE_REGISTRY:-} ]]; then
  printf 'legacy-bench: set CL_SOURCE_REGISTRY to the toolkit dependencies\n' >&2
  exit 2
fi
if [[ ! -f $tree/nshell.asd ]]; then
  printf 'legacy-bench: no nshell.asd in %s\n' "$tree" >&2
  exit 2
fi
mode=warm
if [[ -n $binary ]]; then
  if [[ ! -x $binary ]]; then
    printf 'legacy-bench: not an executable file: %s\n' "$binary" >&2
    exit 2
  fi
  mode=all
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/nshell-legacy-bench.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p -- "$work/home" "$work/cache" "$work/config" "$work/data" "$work/state" "$work/fasl"
uptime
HOME=$work/home XDG_CACHE_HOME=$work/cache XDG_CONFIG_HOME=$work/config \
  XDG_DATA_HOME=$work/data XDG_STATE_HOME=$work/state NSHELL_AI_COMMAND=/nonexistent \
  NSHELL_BENCH_NSHELL_BIN=$binary NSHELL_BENCH_SOURCE_REVISION=${NSHELL_BENCH_SOURCE_REVISION:-$tree} \
  LEGACY_TREE=$tree LEGACY_CHECKOUT=$checkout LEGACY_FASL_DIR=$work/fasl \
  LEGACY_OUTPUT=$output LEGACY_MODE=$mode \
  "$sbcl" --script "$script_dir/legacy-bench.lisp"
uptime
