#!/usr/bin/env bash
# Gate G3: compare a baseline and a candidate nshell binary on this machine.
#
# Usage:
#   scripts/perf/compare.sh [options] BASELINE_BINARY CANDIDATE_BINARY
#
# Options:
#   --noise FILE          Same-binary noise file from noise.sh; floors every
#                         threshold at 2x the A-vs-A variation.
#   --out DIR             Result directory (default: a new temporary directory).
#   --base-src DIR        Baseline source tree, for B3 (with --cand-src).
#   --cand-src DIR        Candidate source tree, for B3.
#   --base-registry REG   CL_SOURCE_REGISTRY for the baseline's B3 and legacy
#                         runs (with --cand-registry), when the two arms pin
#                         different dependencies. Default: the caller's.
#   --cand-registry REG   CL_SOURCE_REGISTRY for the candidate's runs.
#   --b3-blocks N         ABBA blocks of b3-measure.sh runs (default 1; 0 skips
#                         B3, e.g. when the source trees are only for --legacy).
#   --legacy              Also run the bench/ benchmarks of this checkout
#                         against both source trees (A then B, not gated);
#                         needs B3_SBCL or sbcl, and CL_SOURCE_REGISTRY.
#   --quick               Small sample counts, for checking the harness only.
#   --harness-arg ARG     Pass ARG to perfharness.py (repeatable).
#   --note TEXT           Record TEXT in the verdict table and JSON (repeatable),
#                         e.g. what differs between the two binaries.
#
# Run it under the shared lock so heavy jobs do not overlap:
#   lockf ~/.local/state/nshell-v08/locks/heavy.lock scripts/perf/compare.sh A B
#
# Exit status: 0 pass, 1 fail, 3 inconclusive, 2 usage error.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
python=${PYTHON:-python3}

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# need_value OPTION "$@": exit 2 unless OPTION is followed by a nonempty value.
need_value() {
  if [[ $# -lt 3 || -z $3 ]]; then
    printf 'compare.sh: %s needs a value\n' "$1" >&2
    exit 2
  fi
}

noise_file=
out_dir=
base_src=
cand_src=
base_registry=
cand_registry=
b3_blocks=1
legacy=0
harness_args=()
notes=()
mode=compare

while [[ $# -gt 0 ]]; do
  case $1 in
    --noise) need_value "$1" "$@"; noise_file=$2; shift 2 ;;
    --out) need_value "$1" "$@"; out_dir=$2; shift 2 ;;
    --base-src) need_value "$1" "$@"; base_src=$2; shift 2 ;;
    --cand-src) need_value "$1" "$@"; cand_src=$2; shift 2 ;;
    --base-registry) need_value "$1" "$@"; base_registry=$2; shift 2 ;;
    --cand-registry) need_value "$1" "$@"; cand_registry=$2; shift 2 ;;
    --b3-blocks) need_value "$1" "$@"; b3_blocks=$2; shift 2 ;;
    --legacy) legacy=1; shift ;;
    --quick)
      harness_args+=(--startup-blocks 1 --key-blocks 1 --path-key-blocks 1 --keys 20 --warmup-keys 2
        --tab-blocks 1 --tab-samples 2 --prompt-blocks 1 --prompt-samples 3)
      shift ;;
    --harness-arg) need_value "$1" "$@"; harness_args+=("$2"); shift 2 ;;
    --note) need_value "$1" "$@"; notes+=(--note "$2"); shift 2 ;;
    --noise-mode) mode=noise; shift ;;  # used by noise.sh
    -h|--help) usage ;;
    --) shift; break ;;
    -*) printf 'compare.sh: unknown option %s\n' "$1" >&2; usage ;;
    *) break ;;
  esac
done

[[ $# -eq 2 ]] || usage
baseline=$1
candidate=$2

for binary in "$baseline" "$candidate"; do
  if [[ ! -f $binary || ! -x $binary ]]; then
    printf 'compare.sh: not an executable file: %s\n' "$binary" >&2
    exit 2
  fi
done
if [[ -n $base_src || -n $cand_src ]] && [[ -z $base_src || -z $cand_src ]]; then
  printf 'compare.sh: --base-src and --cand-src go together\n' >&2
  exit 2
fi
if [[ -n $base_registry || -n $cand_registry ]] && [[ -z $base_registry || -z $cand_registry ]]; then
  printf 'compare.sh: --base-registry and --cand-registry go together\n' >&2
  exit 2
fi
if [[ -n $base_registry && -z $base_src ]]; then
  printf 'compare.sh: --base-registry needs --base-src and --cand-src\n' >&2
  exit 2
fi
if [[ ! $b3_blocks =~ ^[0-9]+$ ]]; then
  printf 'compare.sh: --b3-blocks must be a nonnegative integer\n' >&2
  exit 2
fi
if [[ -n $noise_file && ! -r $noise_file ]]; then
  printf 'compare.sh: cannot read noise file %s\n' "$noise_file" >&2
  exit 2
fi
if ! command -v "$python" >/dev/null 2>&1; then
  printf 'compare.sh: %s not found (set PYTHON)\n' "$python" >&2
  exit 2
fi
if [[ $legacy -eq 1 && -z $base_src ]]; then
  printf 'compare.sh: --legacy needs --base-src and --cand-src\n' >&2
  exit 2
fi

if [[ -z $out_dir ]]; then
  out_dir=$(mktemp -d "${TMPDIR:-/tmp}/nshell-perf.XXXXXXXX")
fi
mkdir -p -- "$out_dir"
out_dir=$(cd -- "$out_dir" && pwd -P)
printf 'compare.sh: results in %s\n' "$out_dir" >&2

uptime >"$out_dir/uptime-before.txt"
{
  printf 'baseline=%s\n' "$baseline"
  printf 'candidate=%s\n' "$candidate"
  printf 'noise_file=%s\n' "${noise_file:-none}"
  printf 'base_src=%s\ncand_src=%s\n' "${base_src:-none}" "${cand_src:-none}"
  printf 'base_registry=%s\ncand_registry=%s\n' \
    "${base_registry:-${CL_SOURCE_REGISTRY:-unset}}" "${cand_registry:-${CL_SOURCE_REGISTRY:-unset}}"
  printf 'host=%s %s\n' "$(uname -s)" "$(uname -m)"
  printf 'python=%s\n' "$("$python" --version 2>&1)"
} >"$out_dir/conditions.txt"

harness_status=0
"$python" -B "$script_dir/perfharness.py" --a "$baseline" --b "$candidate" \
  --out "$out_dir/raw.json" ${harness_args[@]+"${harness_args[@]}"} \
  2> >(tee "$out_dir/harness.log" >&2) || harness_status=$?
if [[ $harness_status -ne 0 || ! -s $out_dir/raw.json ]]; then
  uptime >"$out_dir/uptime-after.txt"
  printf 'compare.sh: harness exited %s without results; outcome inconclusive\n' "$harness_status" >&2
  exit 3
fi

# Run "$@" with the dependency registry of arm $1.
with_arm_registry() {
  local arm=$1
  shift
  if [[ -z $base_registry ]]; then
    "$@"
  elif [[ $arm == A ]]; then
    CL_SOURCE_REGISTRY=$base_registry "$@"
  else
    CL_SOURCE_REGISTRY=$cand_registry "$@"
  fi
}

# B3: in-process per-key consing and I/O counts from each source tree.
b3_args=()
b3_status=
if [[ -n $base_src ]]; then
  b3_script=$script_dir/b3-measure.sh
  if [[ $b3_blocks -eq 0 ]]; then
    b3_status="not measured: --b3-blocks 0"
  elif [[ ! -x $b3_script ]]; then
    b3_status="error: B3 requested but $b3_script is not executable"
  else
    b3_failures=()
    for ((block = 1; block <= b3_blocks; block++)); do
      position=0
      for arm in A B B A; do
        position=$((position + 1))
        src=$base_src
        [[ $arm == B ]] && src=$cand_src
        out=$out_dir/b3-$block-$position-$arm.json
        printf 'compare.sh: B3 block %s run %s (arm %s)\n' "$block" "$position" "$arm" >&2
        if with_arm_registry "$arm" "$b3_script" "$src" "$out" 2>"$out_dir/b3-$block-$position-$arm.log"; then
          b3_args+=(--b3 "$arm:$block:$out")
        else
          b3_failures+=("arm $arm block $block run $position (see ${out%.json}.log)")
        fi
      done
    done
    if [[ ${#b3_failures[@]} -gt 0 ]]; then
      b3_status="error: b3-measure.sh failed: ${b3_failures[*]}"
    fi
  fi
fi

if [[ $legacy -eq 1 ]]; then
  for arm in A B; do
    src=$base_src
    binary=$baseline
    if [[ $arm == B ]]; then
      src=$cand_src
      binary=$candidate
    fi
    with_arm_registry "$arm" "$script_dir/legacy-bench.sh" "$src" "$out_dir/legacy-$arm.jsonl" "$binary" \
      >"$out_dir/legacy-$arm.log" 2>&1 ||
      printf 'compare.sh: legacy benchmark for arm %s failed (informational, see %s)\n' \
        "$arm" "$out_dir/legacy-$arm.log" >&2
  done
fi

uptime >"$out_dir/uptime-after.txt"

noise_status=0
if [[ $mode == noise ]]; then
  noise_args=(noise "$out_dir/raw.json" --out "$out_dir/noise.json")
  [[ -n $b3_status ]] && noise_args+=(--b3-status "$b3_status")
  "$python" -B "$script_dir/perfstats.py" "${noise_args[@]}" ${b3_args[@]+"${b3_args[@]}"} || noise_status=$?
  if [[ $noise_status -ne 0 && $noise_status -ne 3 ]]; then
    exit "$noise_status"
  fi
  printf 'compare.sh: noise file %s\n' "$out_dir/noise.json" >&2
fi

judge_args=(judge "$out_dir/raw.json" --json "$out_dir/verdict.json" --table "$out_dir/verdict.txt")
[[ -n $noise_file ]] && judge_args+=(--noise "$noise_file")
[[ -n $b3_status ]] && judge_args+=(--b3-status "$b3_status")
if [[ -z $noise_file && $mode == compare ]]; then
  printf 'compare.sh: WARNING: no --noise file; using table thresholds without the 2x noise floor\n' >&2
fi
status=0
"$python" -B "$script_dir/perfstats.py" "${judge_args[@]}" ${b3_args[@]+"${b3_args[@]}"} \
  ${notes[@]+"${notes[@]}"} || status=$?
printf 'uptime after all runs: %s\n' "$(cat "$out_dir/uptime-after.txt")" | tee -a "$out_dir/verdict.txt"
if [[ $mode == noise ]]; then
  # The A-vs-A verdict is a harness sanity check; a fail here means the
  # harness or the machine introduced a bias between the two arms.
  if [[ $status -eq 1 ]]; then
    printf 'noise.sh: WARNING: the same binary failed against itself; treat this noise file with suspicion\n' >&2
  fi
  if [[ $noise_status -eq 3 ]]; then
    # compare.sh judges every gated metric missing from this file inconclusive.
    printf 'noise.sh: the noise file lacks gated metrics (see %s); outcome inconclusive\n' \
      "$out_dir/noise.json" >&2
    exit 3
  fi
  exit 0
fi
exit "$status"
