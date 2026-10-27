#!/usr/bin/env bash
set -euo pipefail

readonly fixture_entry_count=20000
readonly minimum_sample_pairs=20

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$script_dir/.." && pwd -P)
artifact_root=$repo_root/.mediator/nshell-work/benchmarks/completion-filesystem-stages
warmup_pairs=${NSHELL_FS_STAGES_WARMUP_PAIRS:-3}
sample_pairs=${NSHELL_FS_STAGES_SAMPLES:-30}

if [[ ! $warmup_pairs =~ ^[1-9][0-9]*$ ]]; then
  printf 'warmup pairs must be a positive integer: %s\n' "$warmup_pairs" >&2
  exit 2
fi
if [[ ! $sample_pairs =~ ^[1-9][0-9]*$ ]] ||
   (( sample_pairs < minimum_sample_pairs )); then
  printf 'sample pairs must be at least %s: %s\n' \
    "$minimum_sample_pairs" "$sample_pairs" >&2
  exit 2
fi

mkdir -p -- "$artifact_root"
run_dir=$(mktemp -d "$artifact_root/run.XXXXXXXX")
asdf_output_dir=$run_dir/asdf-output
mkdir -p -- "$asdf_output_dir"
export NSHELL_ASDF_OUTPUT_DIR=$asdf_output_dir
fixture_dir=$run_dir/fixture
log_file=$run_dir/aa.log
artifact_relative_dir=.mediator/nshell-work/benchmarks/completion-filesystem-stages/${run_dir##*/}
mkdir -- "$fixture_dir"

cleanup() {
  rm -rf -- "$fixture_dir"
}
trap cleanup EXIT

for ((index = 0; index < fixture_entry_count; index++)); do
  printf -v name 'item-%05d' "$index"
  : >"$fixture_dir/$name"
done

actual_fixture_count=$(find "$fixture_dir" -type f -print | wc -l | tr -d '[:space:]')
if [[ $actual_fixture_count -ne $fixture_entry_count ]]; then
  printf 'fixture verification failed: expected %s files, found %s\n' \
    "$fixture_entry_count" "$actual_fixture_count" >&2
  exit 1
fi

export NSHELL_FS_STAGES_WARMUP_PAIRS=$warmup_pairs
export NSHELL_FS_STAGES_SAMPLES=$sample_pairs

{
  printf 'benchmark=completion-filesystem-stages\n'
  printf 'protocol=same SBCL process/runtime and fixture; alternating paired-arm order; full GC before every timed arm; full ordered candidate signature/hash checked before timing and on every conversion arm\n'
  printf 'fixture_files=%s candidate_prefix=item-\n' "$actual_fixture_count"
  printf 'warmup_pairs=%s measured_pairs=%s per phase/cache state\n' \
    "$warmup_pairs" "$sample_pairs"
  printf 'artifact_dir=%s\n' "$artifact_relative_dir"
  printf 'asdf_output_dir=%s/asdf-output\n' "$artifact_relative_dir"
  printf 'fixture_cleanup=after run; log retained at %s/aa.log\n' "$artifact_relative_dir"
  printf 'os_page_and_dentry_cache=not flushed or controlled\n'
} | tee "$log_file"

cd -- "$repo_root"
set +e
if [[ -n ${IN_NIX_SHELL:-} ]]; then
  sbcl --script "$script_dir/completion-filesystem-stages.lisp" \
    "$fixture_dir" 2>&1 | tee -a "$log_file"
  statuses=("${PIPESTATUS[@]}")
else
  nix develop --command sbcl --script \
    "$script_dir/completion-filesystem-stages.lisp" "$fixture_dir" \
    2>&1 | tee -a "$log_file"
  statuses=("${PIPESTATUS[@]}")
fi
set -e
benchmark_exit=${statuses[0]}

printf 'benchmark_process_exit=%s\n' "$benchmark_exit" | tee -a "$log_file"
printf 'log_path=%s/aa.log\n' "$artifact_relative_dir" | tee -a "$log_file"
exit "$benchmark_exit"
