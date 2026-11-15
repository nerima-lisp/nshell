#!/usr/bin/env bash
# Measure same-binary (A vs A) variation and write a noise file for compare.sh.
#
# Usage:
#   scripts/perf/noise.sh [--out DIR] [--src DIR] [--quick] BINARY
#
# Runs the full compare.sh protocol with BINARY as both arms and writes
# DIR/noise.json. With --src, B3 is also run A vs A on that source tree.
# Run it under the shared lock:
#   lockf ~/.local/state/nshell-v08/locks/heavy.lock scripts/perf/noise.sh BINARY
#
# Exit status: 0 when the noise file was written, 3 when the measurement
# produced no results, 2 on usage errors.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
args=(--noise-mode)
while [[ $# -gt 0 ]]; do
  case $1 in
    --out) args+=(--out "${2:?--out needs a directory}"); shift 2 ;;
    --src) args+=(--base-src "${2:?--src needs a directory}" --cand-src "$2"); shift 2 ;;
    --quick) args+=(--quick); shift ;;
    --harness-arg) args+=(--harness-arg "${2:?--harness-arg needs a value}"); shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
    -*) printf 'noise.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [[ $# -ne 1 ]]; then
  printf 'usage: %s [--out DIR] [--src DIR] [--quick] BINARY\n' "$0" >&2
  exit 2
fi
exec "$script_dir/compare.sh" "${args[@]}" "$1" "$1"
