# Q05: Slow filesystem and NFS responsiveness

## Procedure

1. Use a disposable Linux VM with a dedicated test NFS server and an isolated network interface used only for that mount. Do not change the host's network configuration.
2. With the NFS mount responsive, start nshell from the mount and run `ls`, complete a filename with Tab, and run `echo Q05_READY`. Repeat each operation ten times and record its duration.
3. On the dedicated interface, add a 500 ms delay with `sudo tc qdisc replace dev TEST_INTERFACE root netem delay 500ms`. Repeat the same operations ten times, with a 60-second test safety cutoff for each operation.
4. Remove the delay with `sudo tc qdisc del dev TEST_INTERFACE root` and confirm the mount is responsive again. Record the interface, mount, command, durations, and cutoff results.

## Pass condition

The shell starts and remains usable when filesystem operations are slow. Each operation returns to the prompt or reports an error before the test safety cutoff; none leaves the shell permanently unresponsive. If an isolated NFS test mount and dedicated interface are unavailable, record this case as not run.
