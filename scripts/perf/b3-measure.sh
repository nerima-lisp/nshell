#!/usr/bin/env bash
# Measure per-key cost of the interactive REPL path of an nshell source tree.
#
# Usage: scripts/perf/b3-measure.sh <nshell-source-tree> <out.json>
#
# Loads the nshell system from <nshell-source-tree>, plus t/perf/key-cost.lisp
# from the checkout this script lives in, runs every scenario of
# key-cost.lisp, and writes:
#
#   {"scenarios":[{"name":..., "keys":N,
#                  "bytes_consed_per_key":{"mean":..,"p50":..,"p95":..},
#                  "stat_per_key":x, "file_io_per_key":x, "spawn_per_key":x,
#                  "io_gate":true|false}],
#    "uptime":"<uptime output>"}
#
# "io_gate":false marks a scenario whose I/O counts depend on wall-clock cache
# TTLs (path-20k-type-warm); compare its consing, not its I/O counts.
#
# A per-scenario summary, including the libc and Lisp entry points behind each
# count and the median wall time per key, goes to stderr.
#
# Required environment:
#   B3_SBCL             SBCL executable (>= 2.6.0, < 2.6.10).
#   CL_SOURCE_REGISTRY  ASDF source registry for nshell's dependencies, e.g.
#                       "/path/to/deps//" with the toolkit checkouts pinned in
#                       flake.nix (patched as nix/patches/ does). The source tree
#                       under test is registered ahead of it.
# Optional environment:
#   B3_FASL_DIR         Compiled-output directory, reused across runs. Default:
#                       a fresh temporary directory (a full recompile).
#   CC                  C compiler for the libc counter. Default: cc.
#   B3_SAMPLES          Measured keys per scenario and pass. Default: 30.
#   B3_WARMUP           Unmeasured keys before each pass. Default: 3.
#   B3_HISTORY_COUNT    Records in the persisted history file. Default: 10000.
#   B3_BIG_ENTRIES      Entries in the large directory. Default: 20000.
#   B3_SCENARIOS        Comma-separated scenario names. Default: all.
#   B3_SESSION_PATH     PATH inside the measured session, fixed so stat counts
#                       do not depend on the caller's PATH.
#                       Default: /usr/bin:/bin:/usr/sbin:/sbin.
#
# macOS only: the libc counter is injected with DYLD_INSERT_LIBRARIES.
set -euo pipefail

die() {
  printf 'b3-measure: %s\n' "$*" >&2
  exit 2
}

[ "$#" -eq 2 ] || die "usage: $0 <nshell-source-tree> <out.json>"
[ "$(uname -s)" = Darwin ] || die "only macOS is supported (the libc counter uses dyld interposing)"

tree=$(cd "$1" && pwd) || die "source tree not found: $1"
[ -f "$tree/nshell.asd" ] || die "no nshell.asd in $tree"
out_dir=$(cd "$(dirname "$2")" && pwd) || die "output directory not found: $(dirname "$2")"
output="$out_dir/$(basename "$2")"

[ -n "${B3_SBCL:-}" ] || die "set B3_SBCL to the SBCL executable"
[ -x "$B3_SBCL" ] || die "B3_SBCL is not executable: $B3_SBCL"
[ -n "${CL_SOURCE_REGISTRY:-}" ] || die "set CL_SOURCE_REGISTRY to the directory tree holding nshell's dependencies"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checkout=$(cd "$script_dir/../.." && pwd)
key_cost="$checkout/t/perf/key-cost.lisp"
[ -f "$key_cost" ] || die "missing $key_cost"

work=$(mktemp -d "${TMPDIR:-/tmp}/nshell-b3.XXXXXX")
trap 'rm -rf "$work"' EXIT

"${CC:-cc}" -dynamiclib -O2 -Wall -Wextra -Werror \
  -o "$work/libb3-libc-counter.dylib" "$script_dir/b3-libc-counter.c" \
  || die "compiling the libc counter failed"

fasl_dir=${B3_FASL_DIR:-$work/fasl}
mkdir -p "$fasl_dir" "$work/home" "$work/config" "$work/data" "$work/state" "$work/cache"

uptime_text=$(uptime)

# The whole SBCL process runs with an isolated HOME and XDG tree; the measured
# session additionally gets its own fixture tree from key-cost.lisp.
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/config"
export XDG_DATA_HOME="$work/data"
export XDG_STATE_HOME="$work/state"
export XDG_CACHE_HOME="$work/cache"
export NSHELL_AI_COMMAND=/nonexistent
export PATH="${B3_SESSION_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
export B3_SOURCE_TREE="$tree"
export B3_KEY_COST_SOURCE="$key_cost"
export B3_FASL_DIR="$fasl_dir"
export B3_OUTPUT="$output"
export B3_UPTIME="$uptime_text"
# Set for SBCL alone and not through /usr/bin/env, whose start drops DYLD_*
# variables. The counter removes it from SBCL's environment on load, so
# processes SBCL starts run without it.
DYLD_INSERT_LIBRARIES="$work/libb3-libc-counter.dylib" \
  "$B3_SBCL" --noinform --no-sysinit --no-userinit --disable-debugger \
  --load "$script_dir/b3-measure.lisp"
