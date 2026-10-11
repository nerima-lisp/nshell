#!/usr/bin/env bash
set -euo pipefail

native_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
native_sbcl=${SBCL:-sbcl}
if [[ ${CL_PROCESS_KIT_SPAWN:-} != /* || ! -f ${CL_PROCESS_KIT_SPAWN:-} || ! -x ${CL_PROCESS_KIT_SPAWN:-} ]]; then
  echo 'native-spawn environment error: CL_PROCESS_KIT_SPAWN must name an absolute executable file' >&2
  exit 2
fi
for native_tool in "$native_sbcl" timeout sha256sum sh touch cat ps perl uname stat wc mkdir mktemp rm; do
  if ! command -v "$native_tool" >/dev/null 2>&1; then
    printf 'native-spawn environment error: required tool %s is unavailable\n' "$native_tool" >&2
    exit 2
  fi
done
native_source=$("$native_sbcl" --noinform --script "$native_script_dir/test-dependencies.lisp" --native-spawn-source)
if [[ $native_source != /nix/store/*/t/native-spawn-test.sh || ! -f $native_source || ! -s $native_source ]]; then
  echo 'native-spawn source error: expected a nonempty pinned Nix store script' >&2
  exit 2
fi
# cl-process-kit 3.2.0, revision 44fc4281e5f7e97d662180aa15e23349b7ed7a5d.
# Refuse a substituted or empty upstream test rather than accepting its exit alone.
native_digest=$(sha256sum -- "$native_source")
if [[ ${native_digest%% *} != 1cada2f6fbbc6dec58db8ef0e099cfb39c20d1e230d1c27b0d0091cefe112d8a ]]; then
  echo 'native-spawn source error: pinned upstream test digest differs' >&2
  exit 2
fi
native_tmp_parent=${TMPDIR:-/tmp}
if [[ $native_tmp_parent != /* || ! -d $native_tmp_parent ]]; then
  echo 'native-spawn environment error: TMPDIR must name an absolute existing directory' >&2
  exit 2
fi
native_tmp=$(mktemp -d "$native_tmp_parent/nshell-native-spawn.XXXXXXXX")
trap 'rm -rf -- "$native_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# Upstream uses a PID-named child directory. Its parent and cwd are exclusive here.
export TMPDIR="$native_tmp"
cd -- "$native_tmp"
printf 'native-spawn-discovery discovered=1 selected=1 upstream-sha256=%s\n' "${native_digest%% *}"
if timeout 30 sh "$native_source" "$CL_PROCESS_KIT_SPAWN"; then
  printf 'native-spawn-result executed=1 pass=1 status=PASS\n'
else
  native_exit=$?
  printf 'native-spawn-result executed=1 pass=0 status=FAIL exit=%s\n' "$native_exit" >&2
  exit "$native_exit"
fi
