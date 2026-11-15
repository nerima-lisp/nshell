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
# Exit status: 0 when the noise file has an entry for every gated metric,
# 3 when the measurement produced no results or the noise file lacks a gated
# metric (compare.sh judges such a metric inconclusive), 2 on usage errors.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

# need_value OPTION "$@": exit 2 unless OPTION is followed by a nonempty value.
need_value() {
  if [[ $# -lt 3 || -z $3 ]]; then
    printf 'noise.sh: %s needs a value\n' "$1" >&2
    exit 2
  fi
}

args=(--noise-mode)
while [[ $# -gt 0 ]]; do
  case $1 in
    --out) need_value "$1" "$@"; args+=(--out "$2"); shift 2 ;;
    --src) need_value "$1" "$@"; args+=(--base-src "$2" --cand-src "$2"); shift 2 ;;
    --quick) args+=(--quick); shift ;;
    --harness-arg) need_value "$1" "$@"; args+=(--harness-arg "$2"); shift 2 ;;
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
