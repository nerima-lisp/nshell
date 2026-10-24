# Q05: Slow NFS responsiveness

## Procedure

1. Use disposable Debian or Ubuntu Linux VMs for an NFS server and client. Create a host-only network in the VM manager and connect both test interfaces to it; keep a separate management interface. Allow NFSv4 TCP port 2049 between the VMs on the test network. Keep the examples' server and client addresses, `192.168.56.10` and `192.168.56.11`, or replace them with addresses on that network. The server needs `nfs-kernel-server`; the client needs `nfs-common`, `iproute2`, `git`, and Nix.
2. On the server, assign the server address to its test interface. On the client, assign the client address to its test interface. Replace `SERVER_TEST_INTERFACE` and `CLIENT_TEST_INTERFACE` with the host-only interface names.

   ```sh
   # NFS server
   sudo ip addr add 192.168.56.10/24 dev SERVER_TEST_INTERFACE
   sudo ip link set SERVER_TEST_INTERFACE up

   # NFS client
   sudo ip addr add 192.168.56.11/24 dev CLIENT_TEST_INTERFACE
   sudo ip link set CLIENT_TEST_INTERFACE up
   ```

3. On the client, run `id -u` and `id -g`. On the server, replace `1000:1000` below with those numeric results, then export the test directory to the client. If the client reports `1000` for both values, use the commands as shown.

   ```sh
   sudo apt-get install nfs-kernel-server
   sudo mkdir -p /srv/nfs/q05
   sudo chown 1000:1000 /srv/nfs/q05
   sudo mkdir -p /etc/exports.d
   printf '/srv/nfs/q05 192.168.56.11(rw,sync,no_subtree_check,fsid=0)\n' | sudo tee /etc/exports.d/q05.exports
   sudo systemctl enable --now nfs-kernel-server
   sudo exportfs -ra
   ```

   On the client, install the NFS utilities and mount the export. The `ip route get` output identifies the client interface to use for the delay.

   ```sh
   sudo apt-get install nfs-common iproute2 git
   sudo mkdir -p /mnt/q05
   sudo mount -t nfs -o vers=4 192.168.56.10:/ /mnt/q05
   ip route get 192.168.56.10
   ```

4. From the root of a local checkout of the candidate revision on the client, build the Linux binary before testing. Keep the binary and its Nix store dependencies on the client, not on the NFS export. The result below puts the executable at `/tmp/nshell-q05/bin/nshell`.

   ```sh
   nix build .#packages.x86_64-linux.default --out-link /tmp/nshell-q05
   ```

5. Create the NFS fixtures. Use a shell account with the same numeric UID and GID on both VMs.

   ```sh
   mkdir -p /mnt/q05/git /mnt/q05/completion /mnt/q05/glob /tmp/q05-home
   git -C /mnt/q05/git init
   touch /mnt/q05/completion/complete-probe-a /mnt/q05/completion/complete-probe-b
   touch /mnt/q05/glob/glob-probe-a /mnt/q05/glob/glob-probe-b
   ```

6. Record one baseline trial for each check with no network delay. Start a fresh nshell process for each trial, from `/mnt/q05/git`, using a PTY and direct exec. Use a stopwatch and the 60-second cutoff for baseline trials too.

   ```sh
   cd /mnt/q05/git
   env -i HOME=/tmp/q05-home PATH=/usr/bin:/bin TERM=xterm-256color /tmp/nshell-q05/bin/nshell
   ```

   For the prompt check, start timing before launching nshell. Stop after the prompt shows `/mnt/q05/git` and a Git branch, and `echo Q05_OK` returns to the prompt. For completion, start a fresh process and begin timing before pressing Tab after entering `ls /mnt/q05/completion/complete-probe-`. Record both candidates, press Enter, and stop after `echo Q05_OK` returns to the prompt. For glob, start a fresh process and begin timing before entering `echo /mnt/q05/glob/glob-probe-*`. Confirm both expected names appear, then stop after `echo Q05_OK` returns to the prompt.
7. On the client test interface reported after `dev` by `ip route get`, add 500 ms of network delay. Replace `CLIENT_TEST_INTERFACE` with that interface. Use the interface connected only to this test NFS server, not the management interface. Repeat each check ten times, starting a fresh nshell process for every trial. Apply the 60-second cutoff to each trial using the same start and stop points as the baseline.

   ```sh
   sudo tc qdisc replace dev CLIENT_TEST_INTERFACE root netem delay 500ms
   ```

8. Close nshell and move the client terminal out of the mount. Remove the delay, confirm that the mount responds, unmount it, and discard both VMs.

   ```sh
   cd /tmp
   sudo tc qdisc del dev CLIENT_TEST_INTERFACE root
   ls /mnt/q05
   sudo umount /mnt/q05
   ```

Record the candidate revision, interface names, baseline durations, all delayed trial durations, and any errors.

## Pass condition

Pass when all ten delayed trials of each check finish within 60 seconds, show the expected prompt, completion candidates, or glob matches, and leave nshell able to execute `echo Q05_OK`. A filesystem error followed by a usable prompt and marker is responsive, but it does not pass the check because the expected result was missing. A hang, timeout, missing expected result without an error, or failed marker is a failure. If the isolated NFS server, export, or test-only network is unavailable, record the check as not run.
