# Q05: Slow NFS responsiveness

## Procedure

1. Use disposable Debian or Ubuntu Linux VMs for an NFS server and client. Use your hypervisor's host-only or isolated-network feature for the test interfaces; keep a separate management interface and do not bridge the test network to a public network. Allow NFSv4 TCP port 2049 only between the two test addresses, using the VM firewall's interface-scoped rule if a firewall is active. Keep the examples' server and client addresses, `192.168.56.10` and `192.168.56.11`, or replace them with addresses on that network. The server needs `nfs-kernel-server`; the client needs `nfs-common`, `iproute2`, `git`, and Nix.
2. On each VM, list interfaces with `ip -brief link`. Assign the server address to the server's test interface and the client address to the client's test interface. Replace `SERVER_TEST_INTERFACE` and `CLIENT_TEST_INTERFACE` with those host-only interface names.

   ```sh
   # NFS server
   sudo ip addr add 192.168.56.10/24 dev SERVER_TEST_INTERFACE
   sudo ip link set SERVER_TEST_INTERFACE up

   # NFS client
   sudo ip addr add 192.168.56.11/24 dev CLIENT_TEST_INTERFACE
   sudo ip link set CLIENT_TEST_INTERFACE up
   ```

3. On the client, run `id -u` and `id -g`. On the server, replace `1000:1000` below with those numeric results, then export the test directory to the client. The export directory must be owned by that numeric UID and GID so the client can create the Git fixture.

   ```sh
   sudo apt-get install nfs-kernel-server
   sudo mkdir -p /srv/nfs/q05
   sudo chown 1000:1000 /srv/nfs/q05
   sudo mkdir -p /etc/exports.d
   printf '/srv/nfs/q05 192.168.56.11(rw,sync,no_subtree_check,fsid=0)\n' | sudo tee /etc/exports.d/q05.exports
   sudo systemctl enable --now nfs-kernel-server
   sudo exportfs -ra
   ```

   On the server, verify that `stat -c '%u:%g' /srv/nfs/q05` prints the
   client's numeric UID and GID.

   On the client, install the NFS utilities and mount the export. The `ip route get` output identifies the client interface to use for the delay.

   ```sh
   sudo apt-get install nfs-common iproute2 git
   sudo mkdir -p /mnt/q05
   sudo mount -t nfs -o vers=4 192.168.56.10:/ /mnt/q05
   ip route get 192.168.56.10
   ```

4. From the root of a local checkout of the candidate revision on the client, record `git rev-parse HEAD` and build the Linux binary before testing. Keep the binary and its Nix store dependencies on the client, not on the NFS export. The result below puts the executable at `/tmp/nshell-q05/bin/nshell`.

   ```sh
   nix build .#packages.x86_64-linux.default --out-link /tmp/nshell-q05
   test -x /tmp/nshell-q05/bin/nshell
   ```

5. Create the NFS fixtures. Use a shell account with the same numeric UID and GID on both VMs.

   ```sh
   mkdir -p /mnt/q05/git /mnt/q05/completion /mnt/q05/glob /tmp/q05-home
   git -C /mnt/q05/git init
   touch /mnt/q05/completion/complete-probe-a /mnt/q05/completion/complete-probe-b
   touch /mnt/q05/glob/glob-probe-a /mnt/q05/glob/glob-probe-b
   ```

6. Record one baseline trial for each check with no network delay. Start a fresh nshell process for each trial, from `/mnt/q05/git`, using a PTY and direct exec. Use a stopwatch and the 60-second cutoff for baseline trials too. If a trial reaches the cutoff, mark it failed and send Ctrl-C to stop the foreground command before continuing cleanup.

   ```sh
   cd /mnt/q05/git
   env -i HOME=/tmp/q05-home PATH=/usr/bin:/bin TERM=xterm-256color /tmp/nshell-q05/bin/nshell
   ```

   For the prompt check, start timing before launching nshell. Confirm that the prompt shows `/mnt/q05/git` and the Git branch. Then run `echo Q05_OK`; stop timing only after `Q05_OK` is visible and the prompt returns. For completion, start a fresh process and begin timing before pressing Tab after entering `ls /mnt/q05/completion/complete-probe-`. Record both candidates, press Enter, run `echo Q05_OK`, and stop after its output and the next prompt appear. For glob, start a fresh process and begin timing before entering `echo /mnt/q05/glob/glob-probe-*`. Confirm both expected names appear, run `echo Q05_OK`, and stop after its output and the next prompt appear.
7. On the client test interface reported after `dev` by `ip route get`, add 500 ms of network delay. Replace `CLIENT_TEST_INTERFACE` with that interface. Use the interface connected only to this test NFS server, not the management interface. Confirm `sudo tc qdisc show dev CLIENT_TEST_INTERFACE` reports `netem delay 500ms`. Repeat each check ten times, starting a fresh nshell process for every trial. Apply the 60-second cutoff to each trial using the same start and stop points as the baseline.

   ```sh
   sudo tc qdisc replace dev CLIENT_TEST_INTERFACE root netem delay 500ms
   ```

8. Close nshell and move the client terminal out of the mount. Remove the delay, confirm that `ls /mnt/q05` lists `completion`, `git`, and `glob`, unmount it, and discard both VMs.

   ```sh
   cd /tmp
   sudo tc qdisc del dev CLIENT_TEST_INTERFACE root
   ls /mnt/q05
   sudo umount /mnt/q05
   ```

Record the date, both VM operating systems, candidate revision, server and client test-interface names, the client route, baseline durations, all delayed trial durations, and any errors. Obtain the revision with `git rev-parse HEAD`; obtain the client route with `ip route get 192.168.56.10`.

## Automated Linux CI

The Scenario corpus workflow runs these three PTY scenarios in a dedicated
Ubuntu job. The runner host exports the NFS fixture on a TAP test interface.
An Ubuntu 24.04 QEMU client VM reaches the host through that interface and uses
a separate user-mode management interface for SSH. The guest builds the
candidate binary in its own Nix store, mounts the host export over NFSv4/TCP,
and confirms that the route to the server uses the test interface before
starting any trial.

The job starts a fresh PTY process for each trial: one baseline trial for each
check, followed by ten trials per check with 500 ms of `tc netem` delay on the
client test interface. Every trial has a 60-second cutoff. The job uploads
`results.json` and the per-trial runner output even when a trial fails. Treat a
missing or unsuccessful CI job as unverified; the local manual procedure above
remains the reference for a two-VM setup.

## Pass condition

Pass when all ten delayed trials of each check finish within 60 seconds, show the expected prompt, completion candidates, or glob matches, print `Q05_OK` after the recovery command, and return to the prompt. A filesystem error followed by a usable prompt and `Q05_OK` is responsive, but it does not pass because the expected result was missing. A hang, timeout, missing expected result, absent `Q05_OK`, or failure to return to the prompt is a failure. If the isolated NFS server, export, or test-only network is unavailable, record the check as not run.
