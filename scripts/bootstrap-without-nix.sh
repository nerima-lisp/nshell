#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_root"

for command_name in cc git jq sbcl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command_name" >&2
    exit 1
  fi
done

test_root="$(mktemp -d "${TMPDIR:-${RUNNER_TEMP:-/tmp}}/nshell-no-nix.XXXXXX")"
mkdir -p \
  "$test_root/home" \
  "$test_root/config" \
  "$test_root/data" \
  "$test_root/state" \
  "$test_root/cache" \
  "$test_root/deps" \
  "$test_root/helpers"

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
export NSHELL_AI_COMMAND=/nonexistent
export NSHELL_TEST_PTY=1
export CI=1

sbcl_version="$(sbcl --version)"
if [[ "$sbcl_version" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  sbcl_major="${BASH_REMATCH[1]}"
  sbcl_minor="${BASH_REMATCH[2]}"
  sbcl_patch="${BASH_REMATCH[3]}"
else
  printf 'Could not read the SBCL version from: %s\n' "$sbcl_version" >&2
  exit 1
fi

if [[ "$sbcl_major" != 2 || "$sbcl_minor" != 6 ]] || ((sbcl_patch >= 10)); then
  printf 'SBCL 2.6.0 through 2.6.9 is required; found: %s\n' "$sbcl_version" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin|Linux) ;;
  *)
    printf 'Unsupported platform: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

deps_dir="$test_root/deps"
kit_manifest="$test_root/locked-kits.tsv"
jq -r '
  .nodes as $nodes
  | $nodes.root.inputs
  | to_entries[]
  | select(.key | startswith("cl-"))
  | select(.key != "cl-nix-forge")
  | .key as $name
  | .value as $node
  | [$name, $nodes[$node].locked.owner, $nodes[$node].locked.repo,
     $nodes[$node].original.ref, $nodes[$node].locked.rev]
  | @tsv
' flake.lock > "$kit_manifest"

if [[ ! -s "$kit_manifest" ]]; then
  printf 'No locked Common Lisp kits were found in flake.lock.\n' >&2
  exit 1
fi

while IFS=$'\t' read -r name owner repo ref locked_rev; do
  if [[ ! "$name" =~ ^cl-[A-Za-z0-9][A-Za-z0-9-]*$ \
    || ! "$owner" =~ ^[A-Za-z0-9-]+$ \
    || ! "$repo" =~ ^[A-Za-z0-9._-]+$ \
    || ! "$ref" =~ ^[A-Za-z0-9._+-]+$ \
    || ! "$locked_rev" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf 'Invalid kit entry in flake.lock.\n' >&2
    exit 1
  fi

  clone_url="https://github.com/$owner/$repo.git"
  checkout_dir="$deps_dir/$name"
  printf 'Fetching %s at %s (%s)\n' "$name" "$ref" "$locked_rev"
  git clone --quiet --depth 1 --branch="$ref" "$clone_url" "$checkout_dir"
  git -C "$checkout_dir" checkout --quiet --detach "$locked_rev"
  actual_rev="$(git -C "$checkout_dir" rev-parse HEAD)"
  if [[ "$actual_rev" != "$locked_rev" ]]; then
    printf 'Locked revision mismatch for %s: expected %s, got %s\n' \
      "$name" "$locked_rev" "$actual_rev" >&2
    exit 1
  fi
done < "$kit_manifest"

shopt -s nullglob
patch_files=("$repo_root"/nix/patches/*.patch)
if ((${#patch_files[@]} == 0)); then
  printf 'No patches found under nix/patches.\n' >&2
  exit 1
fi

for patch_file in "${patch_files[@]}"; do
  patch_name="${patch_file##*/}"
  patch_kit=""
  patch_kit_length=0
  for checkout_dir in "$deps_dir"/cl-*; do
    [[ -d "$checkout_dir" ]] || continue
    candidate="${checkout_dir##*/}"
    if [[ "$patch_name" == "$candidate-"* ]] && (( ${#candidate} > patch_kit_length )); then
      patch_kit="$candidate"
      patch_kit_length="${#candidate}"
    fi
  done

  if [[ -z "$patch_kit" ]]; then
    printf 'Could not find a locked kit for patch: %s\n' "$patch_name" >&2
    exit 1
  fi

  printf 'Applying %s to %s\n' "$patch_name" "$patch_kit"
  git -C "$deps_dir/$patch_kit" apply --check "$patch_file"
  git -C "$deps_dir/$patch_kit" apply "$patch_file"
done

helper_dir="$test_root/helpers"
# nshell does not call cl-process-kit:spawn-native, so its optional trampoline is not needed.
case "$(uname -s)" in
  Darwin)
    cc -O2 -fPIC -dynamiclib "$deps_dir/cl-process-kit/native/pty.c" \
      -o "$helper_dir/libcl_process_kit_pty.dylib"
    export CL_PROCESS_KIT_PTY_LIBRARY="$helper_dir/libcl_process_kit_pty.dylib"
    cc -std=c11 -O2 -Wall -Wextra -Werror \
      "$repo_root/src/infrastructure/acl/pty-exec-bootstrap.c" \
      -o "$helper_dir/nshell-pty-bootstrap"
    export NSHELL_PTY_BOOTSTRAP="$helper_dir/nshell-pty-bootstrap"
    ;;
  Linux)
    cc -O2 -fPIC -shared "$deps_dir/cl-process-kit/native/pty.c" \
      -o "$helper_dir/libcl_process_kit_pty.so" -lutil
    export CL_PROCESS_KIT_PTY_LIBRARY="$helper_dir/libcl_process_kit_pty.so"
    ;;
esac

export CL_SOURCE_REGISTRY="$deps_dir//:$repo_root/"
test_log="$test_root/run-tests.log"
printf 'Running the full suite with isolated state in %s\n' "$test_root"
sbcl --script run-tests.lisp 2>&1 | tee "$test_log"
if ! grep -Eq 'NSHELL_TESTS .*passed=T' "$test_log"; then
  printf 'The test runner did not report the passing NSHELL_TESTS marker.\n' >&2
  exit 1
fi
