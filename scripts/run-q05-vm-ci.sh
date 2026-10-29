#!/usr/bin/env bash
set -euo pipefail

readonly q05_host_test_interface="q05tap0"
readonly q05_server_address="192.168.56.10"
readonly q05_client_address="192.168.56.11"
readonly q05_image_name="ubuntu-24.04-server-cloudimg-amd64.img"
readonly q05_image_base="https://cloud-images.ubuntu.com/releases/noble/release"
readonly q05_vm_disk_size="32G"
q05_workspace="$(mktemp -d "${RUNNER_TEMP:?}/nshell-q05-vm.XXXXXX")"
readonly q05_workspace
readonly q05_results="${RUNNER_TEMP}/nshell-q05-results"
readonly q05_export="${q05_workspace}/export"
readonly q05_export_config="/etc/exports.d/nshell-q05.exports"
q05_qemu_pid=""
q05_exported=false
q05_tap_created=false
q05_export_config_created=false
q05_nfs_was_active=false

mkdir -p "$q05_results" "$q05_export"

q05_cleanup() {
  local q05_exit_status=$?
  trap - EXIT
  if [[ -n "$q05_qemu_pid" ]] && kill -0 "$q05_qemu_pid" 2>/dev/null; then
    kill -TERM "$q05_qemu_pid" || true
    for _ in {1..10}; do
      if ! kill -0 "$q05_qemu_pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "$q05_qemu_pid" 2>/dev/null; then
      kill -KILL "$q05_qemu_pid" || true
    fi
  fi
  if [[ "$q05_exported" == true ]]; then
    sudo exportfs -u "${q05_client_address}:${q05_export}" || true
  fi
  if [[ "$q05_export_config_created" == true ]]; then
    sudo rm -f "$q05_export_config"
    sudo exportfs -ra || true
  fi
  if [[ "$q05_tap_created" == true ]]; then
    sudo ip link del "$q05_host_test_interface" || true
  fi
  if [[ "$q05_nfs_was_active" == false ]]; then
    sudo systemctl stop nfs-kernel-server || true
  fi
  sudo rm -rf "$q05_workspace"
  exit "$q05_exit_status"
}
trap q05_cleanup EXIT

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "Q05 requires KVM on the Linux runner; no CPU emulation fallback is used." >&2
  exit 1
fi
if ip link show "$q05_host_test_interface" >/dev/null 2>&1; then
  echo "Q05 host test interface already exists: $q05_host_test_interface" >&2
  exit 1
fi
if [[ -e "$q05_export_config" ]]; then
  echo "Q05 NFS export configuration already exists: $q05_export_config" >&2
  exit 1
fi
if sudo systemctl is-active --quiet nfs-kernel-server; then
  q05_nfs_was_active=true
fi

sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  cloud-image-utils \
  nfs-kernel-server \
  qemu-system-x86 \
  qemu-utils
sudo install -d -m 0755 /etc/exports.d

mkdir -p "$q05_export/git" "$q05_export/completion" "$q05_export/glob"
touch \
  "$q05_export/completion/complete-probe-a" \
  "$q05_export/completion/complete-probe-b" \
  "$q05_export/glob/glob-probe-a" \
  "$q05_export/glob/glob-probe-b"
sudo chown -R 1000:1000 "$q05_export"

sudo ip tuntap add dev "$q05_host_test_interface" mode tap user "$(id -u)"
q05_tap_created=true
sudo ip address add "${q05_server_address}/24" dev "$q05_host_test_interface"
sudo ip link set dev "$q05_host_test_interface" up

q05_export_config_created=true
printf '%s %s(rw,sync,no_subtree_check,fsid=0)\n' \
  "$q05_export" "$q05_client_address" | sudo tee "$q05_export_config" >/dev/null
sudo exportfs -ra
q05_exported=true
sudo systemctl enable --now nfs-kernel-server
sudo exportfs -s | tee "$q05_results/nfs-exports.txt"

curl --fail --location --silent --show-error \
  "${q05_image_base}/SHA256SUMS" \
  --output "$q05_workspace/SHA256SUMS"
curl --fail --location --silent --show-error \
  "${q05_image_base}/${q05_image_name}" \
  --output "$q05_workspace/${q05_image_name}"
q05_expected_hash="$(awk -v image="$q05_image_name" '$2 == image || $2 == "*" image {print $1; exit}' "$q05_workspace/SHA256SUMS")"
if [[ ! "$q05_expected_hash" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Ubuntu cloud image SHA256 was not found in SHA256SUMS." >&2
  exit 1
fi
printf '%s  %s\n' "$q05_expected_hash" "$q05_workspace/${q05_image_name}" | sha256sum --check

qemu-img create -f qcow2 -F qcow2 \
  -b "$q05_workspace/${q05_image_name}" \
  "$q05_workspace/client.qcow2" "$q05_vm_disk_size"
ssh-keygen -q -t ed25519 -N '' -f "$q05_workspace/id_ed25519"
q05_ssh_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"

cat > "$q05_workspace/user-data" <<EOF
#cloud-config
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
users:
  - default
  - name: ubuntu
    ssh_authorized_keys:
      - $(cat "$q05_workspace/id_ed25519.pub")
package_update: true
packages:
  - ca-certificates
  - curl
  - git
  - iproute2
  - nfs-common
  - openssh-server
  - python3
  - tmux
  - xz-utils
runcmd:
  - [systemctl, enable, --now, ssh]
EOF
cat > "$q05_workspace/meta-data" <<'EOF'
instance-id: nshell-q05-client
local-hostname: nshell-q05-client
EOF
cat > "$q05_workspace/network-config" <<'EOF'
version: 2
ethernets:
  management:
    match:
      macaddress: "52:54:00:05:00:01"
    set-name: mgmt0
    dhcp4: true
    dhcp6: false
  nfs-test:
    match:
      macaddress: "52:54:00:05:00:02"
    set-name: test0
    addresses:
      - 192.168.56.11/24
    dhcp4: false
    dhcp6: false
EOF
cloud-localds --network-config="$q05_workspace/network-config" \
  "$q05_workspace/seed.iso" "$q05_workspace/user-data" "$q05_workspace/meta-data"

qemu-system-x86_64 \
  -name nshell-q05-client \
  -enable-kvm \
  -machine q35 \
  -cpu host \
  -smp 2 \
  -m 8192 \
  -drive "file=$q05_workspace/client.qcow2,if=virtio,format=qcow2" \
  -drive "file=$q05_workspace/seed.iso,if=virtio,format=raw,readonly=on" \
  -netdev "user,id=management,hostfwd=tcp:127.0.0.1:${q05_ssh_port}-:22" \
  -device virtio-net-pci,netdev=management,mac=52:54:00:05:00:01 \
  -netdev "tap,id=nfs-test,ifname=$q05_host_test_interface,script=no,downscript=no" \
  -device virtio-net-pci,netdev=nfs-test,mac=52:54:00:05:00:02 \
  -display none \
  -serial "file:$q05_workspace/serial.log" \
  -monitor none \
  -daemonize \
  -pidfile "$q05_workspace/qemu.pid"
q05_qemu_pid="$(cat "$q05_workspace/qemu.pid")"

q05_ssh() {
  ssh \
    -i "$q05_workspace/id_ed25519" \
    -p "$q05_ssh_port" \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=4 \
    ubuntu@127.0.0.1 "$@"
}

q05_ssh_ready=false
for _ in {1..120}; do
  if q05_ssh true >/dev/null 2>&1; then
    q05_ssh_ready=true
    break
  fi
  sleep 5
done
if [[ "$q05_ssh_ready" != true ]]; then
  echo "Q05 Ubuntu client VM did not become reachable over its management NIC." >&2
  exit 1
fi
q05_ssh 'sudo cloud-init status --wait'
q05_ssh 'df -h /; available_bytes="$(df -B1 --output=avail / | tail -n 1)"; if [ "$available_bytes" -lt 17179869184 ]; then echo "Q05 guest root filesystem has less than 16 GiB available after cloud-init growth." >&2; exit 1; fi'
q05_ssh 'ip -brief address; ip route get 192.168.56.10; id'

git -C "$GITHUB_WORKSPACE" archive --format=tar "$GITHUB_SHA" \
  | q05_ssh 'mkdir -p /home/ubuntu/nshell && tar -xf - -C /home/ubuntu/nshell'

cat > "$q05_workspace/guest-run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly q05_revision="$1"
readonly q05_source="/home/ubuntu/nshell"
readonly q05_results="/tmp/q05-results"
mkdir -p "$q05_results" "$q05_source"
cd "$q05_source"
git init --initial-branch=q05-ci
git -c user.name='Q05 CI' -c user.email='q05-ci@invalid.example' add -A
git -c user.name='Q05 CI' -c user.email='q05-ci@invalid.example' \
  commit --quiet -m 'Q05 candidate source snapshot'
free -h
df -h /
nproc

curl --fail --location --silent --show-error https://nixos.org/nix/install \
  --output /tmp/install-nix.sh
sh /tmp/install-nix.sh --no-daemon
. /home/ubuntu/.nix-profile/etc/profile.d/nix.sh
export NIX_CONFIG='experimental-features = nix-command flakes'
nix run nixpkgs#cachix -- use takeokunn-nshell
nix run nixpkgs#cachix -- use nix-community
if nix build --print-build-logs --max-jobs 1 --cores 1 \
  .#packages.x86_64-linux.default --out-link /tmp/nshell-q05; then
  :
else
  build_status=$?
  free -h
  df -h /
  sudo dmesg --ctime | tail -n 80 || true
  exit "$build_status"
fi
test -x /tmp/nshell-q05/bin/nshell
mkdir -p /tmp/q05-home
sudo mkdir -p /mnt/q05
sudo mount -t nfs -o vers=4,proto=tcp 192.168.56.10:/ /mnt/q05
git -C /mnt/q05/git init --initial-branch=q05-branch
test -f /mnt/q05/completion/complete-probe-a
test -f /mnt/q05/completion/complete-probe-b
test -f /mnt/q05/glob/glob-probe-a
test -f /mnt/q05/glob/glob-probe-b
ip route get 192.168.56.10
python3 scripts/run-q05-trials.py \
  --binary /tmp/nshell-q05/bin/nshell \
  --scenario-dir t/scenarios/Q05 \
  --server-interface q05tap0 \
  --interface test0 \
  --output-dir "$q05_results" \
  --candidate-revision "$q05_revision" \
  --git-diagnostics
EOF
chmod 700 "$q05_workspace/guest-run.sh"
q05_ssh 'mkdir -p /tmp/q05-results'
scp \
  -i "$q05_workspace/id_ed25519" \
  -P "$q05_ssh_port" \
  -o BatchMode=yes \
  -o ConnectTimeout=5 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$q05_workspace/guest-run.sh" \
  ubuntu@127.0.0.1:/tmp/q05-guest-run.sh

set +e
q05_ssh "bash /tmp/q05-guest-run.sh '$GITHUB_SHA'" 2>&1 \
  | tee "$q05_results/guest-run.log"
q05_guest_status=${PIPESTATUS[0]}
set -e

set +e
q05_ssh 'tar -C /tmp -cf - q05-results' \
  | tar -C "$q05_results" -xf -
q05_results_status=$?
set -e
if [[ "$q05_results_status" -ne 0 ]]; then
  echo "Q05 trial evidence could not be copied from the client VM." >&2
  exit "$q05_results_status"
fi
if [[ "$q05_guest_status" -ne 0 ]]; then
  echo "Q05 client run failed with exit status $q05_guest_status." >&2
  exit "$q05_guest_status"
fi
