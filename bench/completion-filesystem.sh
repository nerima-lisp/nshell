#!/usr/bin/env bash
set -euo pipefail

readonly fixture_entry_count=20000
readonly warmup_count=2
readonly sample_count=10

run_arm() {
  local arm=$1
  local binary

  case $arm in
    before) binary=${NSHELL_FS_BENCH_BEFORE_BINARY:?} ;;
    after) binary=${NSHELL_FS_BENCH_AFTER_BINARY:?} ;;
    *) printf 'unknown benchmark arm: %s\n' "$arm" >&2; return 2 ;;
  esac

  "$binary" --no-config -c "$NSHELL_FS_BENCH_COMPLETION_LINE" \
    >"$NSHELL_FS_BENCH_OUTPUT"
  if ! cmp -s "$NSHELL_FS_BENCH_REFERENCE" "$NSHELL_FS_BENCH_OUTPUT"; then
    printf 'output parity check failed for %s arm\n' "$arm" >&2
    return 1
  fi
}

if [[ ${1-} == --run ]]; then
  [[ $# -eq 2 ]] || { printf 'usage: %s --run before|after\n' "$0" >&2; exit 2; }
  run_arm "$2"
  exit
fi

if [[ $# -ne 2 ]]; then
  printf 'usage: %s BEFORE_BINARY AFTER_BINARY\n' "$0" >&2
  exit 2
fi

before_binary=$1
after_binary=$2
hyperfine_binary=${HYPERFINE:-hyperfine}

for binary in "$before_binary" "$after_binary"; do
  if [[ ! -f $binary || ! -x $binary ]]; then
    printf 'benchmark input must be an executable file: %s\n' "$binary" >&2
    exit 2
  fi
done
if ! command -v "$hyperfine_binary" >/dev/null 2>&1; then
  printf 'required benchmark tool is unavailable: %s\n' "$hyperfine_binary" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'required benchmark result parser is unavailable: jq\n' >&2
  exit 2
fi

work_dir=$(mktemp -d "/tmp/nshell-completion-filesystem.XXXXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT
fixture_dir=$work_dir/fixture
reference_output=$work_dir/reference.txt
actual_output=$work_dir/actual.txt
hyperfine_json=$work_dir/hyperfine.json
mkdir "$fixture_dir"

for ((index = 0; index < fixture_entry_count; index++)); do
  printf -v name 'item-%05d' "$index"
  : >"$fixture_dir/$name"
done

actual_fixture_count=$(find "$fixture_dir" -type f -print | wc -l)
actual_fixture_count=${actual_fixture_count//[[:space:]]/}
if [[ $actual_fixture_count -ne $fixture_entry_count ]]; then
  printf 'fixture verification failed: expected %s files, found %s\n' \
    "$fixture_entry_count" "$actual_fixture_count" >&2
  exit 1
fi

completion_line="complete -C 'source $fixture_dir/item-'"
if ! "$before_binary" --no-config -c "$completion_line" >"$reference_output"; then
  printf 'before binary failed while establishing the output reference\n' >&2
  exit 1
fi
actual_candidate_count=$(wc -l <"$reference_output")
actual_candidate_count=${actual_candidate_count//[[:space:]]/}
unique_candidate_count=$(LC_ALL=C sort -u "$reference_output" | wc -l)
unique_candidate_count=${unique_candidate_count//[[:space:]]/}
if [[ $actual_candidate_count -ne $fixture_entry_count || \
      $unique_candidate_count -ne $fixture_entry_count ]]; then
  printf 'completion verification failed: expected %s unique candidates, found %s rows and %s unique rows\n' \
    "$fixture_entry_count" "$actual_candidate_count" "$unique_candidate_count" >&2
  exit 1
fi
if ! "$after_binary" --no-config -c "$completion_line" >"$actual_output"; then
  printf 'after binary failed while checking output parity\n' >&2
  exit 1
fi
if ! cmp -s "$reference_output" "$actual_output"; then
  printf 'before and after outputs differ before measurement\n' >&2
  exit 1
fi

export NSHELL_FS_BENCH_BEFORE_BINARY=$before_binary
export NSHELL_FS_BENCH_AFTER_BINARY=$after_binary
export NSHELL_FS_BENCH_COMPLETION_LINE=$completion_line
export NSHELL_FS_BENCH_REFERENCE=$reference_output
export NSHELL_FS_BENCH_OUTPUT=$actual_output

script_path=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")
printf -v quoted_script_path '%q' "$script_path"
before_command="$quoted_script_path --run before"
after_command="$quoted_script_path --run after"

os_name=$(uname -s)
kernel_version=$(uname -r)
architecture=$(uname -m)
case $os_name in
  Darwin)
    cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null || printf unknown)
    load_average=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' || printf unknown)
    ;;
  Linux)
    cpu_model=$(awk -F: '/^model name/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo 2>/dev/null || printf unknown)
    read -r load_average _ < /proc/loadavg
    ;;
  *)
    cpu_model=unknown
    load_average=unknown
    ;;
esac
[[ -n $cpu_model ]] || cpu_model=unknown
cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf unknown)
hyperfine_version=$("$hyperfine_binary" --version)

printf 'benchmark=filesystem file completion through nshell -c\n'
printf 'binary_before=%s\n' "$before_binary"
printf 'binary_after=%s\n' "$after_binary"
printf 'fixture_files=%s\n' "$actual_fixture_count"
printf 'completion_line=complete -C source <fixture>/item-\n'
printf 'candidate_rows=%s unique_candidates=%s\n' "$actual_candidate_count" "$unique_candidate_count"
printf 'host=%s kernel=%s architecture=%s cpu=%s cpu_count=%s load_average=%s\n' \
  "$os_name" "$kernel_version" "$architecture" "$cpu_model" "$cpu_count" "$load_average"
printf 'shell=bash %s hyperfine=%s\n' "$BASH_VERSION" "$hyperfine_version"
printf 'protocol=2 warmups per arm excluded, 10 measured runs per arm, fresh wrapper and binary process per sample, three arms in hyperfine default randomized command order\n'
printf 'verification=each timed run captures output and compares it byte-for-byte with the verified 20000-row reference\n'

"$hyperfine_binary" \
  --warmup "$warmup_count" \
  --runs "$sample_count" \
  --shell bash \
  --export-json "$hyperfine_json" \
  --command-name baseline-a "$before_command" \
  --command-name baseline-b "$before_command" \
  --command-name after "$after_command"

jq -e '
  .schema_version == 2 and
  (.results | length == 3) and
  all(.results[]; .summary.time_wall_clock.median != null and
                  .summary.time_wall_clock.stddev != null and
                  .summary.time_wall_clock.min != null and
                  .summary.time_wall_clock.max != null)
' "$hyperfine_json" >/dev/null

baseline_a_median_ms=$(jq -r '(.results[0].summary.time_wall_clock.median * 1000)' "$hyperfine_json")
baseline_a_stddev_ms=$(jq -r '(.results[0].summary.time_wall_clock.stddev * 1000)' "$hyperfine_json")
baseline_a_range_ms=$(jq -r '((.results[0].summary.time_wall_clock.max - .results[0].summary.time_wall_clock.min) * 1000)' "$hyperfine_json")
baseline_b_median_ms=$(jq -r '(.results[1].summary.time_wall_clock.median * 1000)' "$hyperfine_json")
baseline_b_stddev_ms=$(jq -r '(.results[1].summary.time_wall_clock.stddev * 1000)' "$hyperfine_json")
baseline_b_range_ms=$(jq -r '((.results[1].summary.time_wall_clock.max - .results[1].summary.time_wall_clock.min) * 1000)' "$hyperfine_json")
after_median_ms=$(jq -r '(.results[2].summary.time_wall_clock.median * 1000)' "$hyperfine_json")
after_stddev_ms=$(jq -r '(.results[2].summary.time_wall_clock.stddev * 1000)' "$hyperfine_json")
after_range_ms=$(jq -r '((.results[2].summary.time_wall_clock.max - .results[2].summary.time_wall_clock.min) * 1000)' "$hyperfine_json")
baseline_median_delta_ms=$(jq -r '(.results[0].summary.time_wall_clock.median - .results[1].summary.time_wall_clock.median | if . < 0 then -. else . end) * 1000' "$hyperfine_json")
printf 'hyperfine_baseline_a_median_ms=%s stddev_ms=%s range_ms=%s\n' \
  "$baseline_a_median_ms" "$baseline_a_stddev_ms" "$baseline_a_range_ms"
printf 'hyperfine_baseline_b_median_ms=%s stddev_ms=%s range_ms=%s\n' \
  "$baseline_b_median_ms" "$baseline_b_stddev_ms" "$baseline_b_range_ms"
printf 'hyperfine_baseline_median_delta_ms=%s\n' "$baseline_median_delta_ms"
printf 'hyperfine_after_median_ms=%s stddev_ms=%s range_ms=%s\n' \
  "$after_median_ms" "$after_stddev_ms" "$after_range_ms"
