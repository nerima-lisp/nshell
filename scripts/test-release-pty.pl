#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use POSIX qw(WNOHANG);
use Time::HiRes qw(time sleep);

# Usage: perl scripts/test-release-pty.pl EXTRACTED_BUNDLE [--timeout SECONDS]
# Only the public executable is launched; no Lisp forms or source paths are supplied.
my $bundle = shift @ARGV;
my $timeout = 45;
if (@ARGV == 2 && $ARGV[0] eq '--timeout' && $ARGV[1] =~ /^\d+$/) {
    $timeout = $ARGV[1];
    @ARGV = ();
}
die "usage: $0 EXTRACTED_BUNDLE [--timeout SECONDS (5..300)]\n"
    if !defined($bundle) || @ARGV || $timeout < 5 || $timeout > 300;
$bundle = abs_path($bundle) // die "bundle does not exist\n";
my $executable = "$bundle/bin/nshell";
die "bundle/bin/nshell must be a nonempty executable file\n"
    unless -f $executable && -s $executable && -x $executable;
die "PTY verification requires Linux or Darwin (no skip)\n"
    unless $^O eq 'linux' || $^O eq 'darwin';
if ($^O eq 'darwin') {
    for my $object ($executable, "$bundle/libexec/nshell") {
        next unless -f $object;
        open my $fh, '<', $object or die "cannot inspect executable\n";
        read($fh, my $magic, 4) == 4 or die "cannot read executable header\n";
        close $fh or die "cannot close executable\n";
        die "Linux ELF bundle cannot be verified on Darwin (no skip)\n"
            if $magic eq "\x7fELF";
    }
}
my $isolation = tempdir('nshell-release-pty-XXXXXX', TMPDIR => 1, CLEANUP => 1);
make_path(map { "$isolation/$_" } qw(home config cache data state tmp));
my $backend = <<'PYTHON';
import copy
import errno
import fcntl
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

executable, isolation, seconds = sys.argv[1:]
deadline = time.monotonic() + int(seconds)
# Reserve time for escalation/reaping inside the whole-run deadline.
work_deadline = deadline - 2
stage = 'startup'
sessions = []
jobs = {}
passed = []
prompt = b'release-pty> '
nonce = os.urandom(8).hex()
environment = {
    'HOME': isolation + '/home', 'XDG_CONFIG_HOME': isolation + '/config',
    'XDG_CACHE_HOME': isolation + '/cache', 'XDG_DATA_HOME': isolation + '/data',
    'XDG_STATE_HOME': isolation + '/state', 'TMPDIR': isolation + '/tmp',
    'PATH': '/usr/bin:/bin', 'TERM': 'xterm', 'LANG': 'C', 'LC_ALL': 'C',
    'NSHELL_PROMPT': prompt.decode(),
}


def interrupted(signum, frame):
    raise RuntimeError('runner interrupted by signal %d' % signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGALRM, interrupted)
signal.setitimer(signal.ITIMER_REAL, int(seconds))


def remaining(limit=5):
    value = min(limit, work_deadline - time.monotonic())
    if value <= 0:
        raise RuntimeError('whole-run deadline exceeded')
    return value


def process(pid):
    result = subprocess.run(['ps', '-o', 'pgid=', '-o', 'stat=', '-o', 'ppid=', '-p', str(pid)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=remaining(1), env=environment)
    if result.returncode == 1 and not result.stdout.strip():
        return None
    if result.returncode != 0:
        raise RuntimeError('ps observation failed')
    fields = result.stdout.split()
    if len(fields) != 3:
        raise RuntimeError('invalid ps observation')
    return int(fields[0]), fields[1].decode('ascii'), int(fields[2])


class Session:
    def __init__(self, history=False):
        self.master, self.slave = os.openpty()
        self.status = None
        self.output = b''
        attributes = termios.tcgetattr(self.slave)
        attributes[3] |= termios.ICANON | termios.ECHO | termios.ISIG
        termios.tcsetattr(self.slave, termios.TCSANOW, attributes)
        # Darwin revokes the slave when its session leader exits; the retained
        # master still exposes this same terminal's attributes after exit.
        self.baseline = copy.deepcopy(termios.tcgetattr(self.master))
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
        self.pid = os.fork()
        if self.pid == 0:
            try:
                os.close(self.master)
                os.setsid()
                fcntl.ioctl(self.slave, termios.TIOCSCTTY, 0)
                for fd in (0, 1, 2):
                    os.dup2(self.slave, fd)
                if self.slave > 2:
                    os.close(self.slave)
                os.chdir(isolation)
                arguments = [executable, '--no-config']
                if not history:
                    arguments.append('--no-history')
                os.execve(executable, arguments, environment)
            except BaseException:
                os._exit(127)
        sessions.append(self)
        os.set_blocking(self.master, False)

    def poll(self):
        if self.status is None:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.status = status
        return self.status

    def read(self, duration=0.02):
        if select.select([self.master], [], [], duration)[0]:
            try:
                data = os.read(self.master, 8192)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b''
            self.output += data
            if len(self.output) > 1024 * 1024:
                raise RuntimeError('PTY output limit exceeded')

    def send(self, data):
        if self.poll() is not None:
            raise RuntimeError('executable exited before input (status %d)' % self.status)
        end = time.monotonic() + remaining()
        view = memoryview(data)
        while view:
            if time.monotonic() >= end:
                raise RuntimeError('PTY write deadline exceeded')
            if select.select([], [self.master], [], 0.02)[1]:
                view = view[os.write(self.master, view):]

    def expect(self, expected, start, stimulus=b''):
        pattern = re.compile(expected) if isinstance(expected, bytes) else expected
        if pattern.search(stimulus):
            raise RuntimeError('assertion would match terminal input echo')
        end = time.monotonic() + remaining()
        while True:
            match = pattern.search(self.output[start:])
            if match:
                return match, start + match.end()
            if self.poll() is not None:
                raise RuntimeError('executable exited before expected output (status %d)' % self.status)
            if time.monotonic() >= end:
                raise RuntimeError('expected output deadline exceeded')
            self.read()

    def marker(self, name, value):
        label = name + '-' + nonce
        command = ("printf 'rel-%s:<%s>\\n' '%s' '%s'\n" % ('%s', '%s', label, value)).encode()
        expected = ('rel-%s:<%s>' % (label, value)).encode()
        start = len(self.output)
        self.send(command)
        match, end = self.expect(re.escape(expected), start, command)
        self.expect(re.escape(prompt), end)
        return command

    def foreground(self):
        return struct.unpack('i', fcntl.ioctl(self.master, termios.TIOCGPGRP, struct.pack('i', 0)))[0]

    def wait(self, predicate):
        end = time.monotonic() + remaining()
        while not predicate():
            if self.poll() is not None:
                raise RuntimeError('executable exited during process-state assertion')
            if time.monotonic() >= end:
                raise RuntimeError('process-state deadline exceeded')
            self.read()

    def finish(self):
        self.send(b'\x04')
        end = time.monotonic() + remaining()
        while self.poll() is None:
            if time.monotonic() >= end:
                raise RuntimeError('interactive exit deadline exceeded')
            self.read()
        if not os.WIFEXITED(self.status) or os.WEXITSTATUS(self.status) != 0:
            raise RuntimeError('interactive executable exit was not zero')
        if termios.tcgetattr(self.master) != self.baseline:
            raise RuntimeError('interactive termios was not restored')


def check(name):
    passed.append(name)
    print('ok: ' + name, flush=True)


failure = None
cleanup_errors = []
try:
    if sys.platform.startswith('linux'):
        # Reap adopted jobs even if a failing shell exits before reaping them.
        import ctypes
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
            raise RuntimeError('cannot establish owned-job subreaper')
    session = Session()
    session.expect(re.escape(prompt), 0)
    stage = 'interactive readiness'
    label = 'tty-' + nonce
    command = ("sh -c 'test -t 0 && test -t 1 && test -t 2 || exit 91; printf \"rel-%%s:<%%s>\\n\" %s yes'\n" % label).encode()
    start = len(session.output)
    session.send(command)
    _, end = session.expect(re.escape(('rel-%s:<yes>' % label).encode()), start, command)
    session.expect(re.escape(prompt), end)
    stage = 'editing/backspace'
    label = 'edit-' + nonce
    command = ("printf 'rel-%%s:<%%s>\\n' %s okx" % label).encode() + b'\x08\n'
    start = len(session.output)
    session.send(command)
    _, end = session.expect(re.escape(('rel-%s:<ok>' % label).encode()), start, command)
    session.expect(re.escape(prompt), end)
    check(stage)

    stage = 'Ctrl-C pending input'
    start = len(session.output)
    session.send(b'exit 91')
    session.expect(b'91', start)  # Ensure the pending bytes reached the editor first.
    start = len(session.output)
    session.send(b'\x03')
    session.expect(re.escape(prompt), start)
    session.marker('pending-recovered', 'yes')
    check(stage)

    stage = 'Ctrl-C foreground'
    label = 'job-' + nonce
    command = ("sh -c 'printf \"rel-%%s:<%%s>\\n\" %s \"$$\" > /dev/tty; exec sleep 30'\n" % label).encode()

    def launch_job():
        start = len(session.output)
        session.send(command)
        match, _ = session.expect(re.compile(re.escape(('rel-%s:<' % label).encode()) + rb'(\d+)>'), start, command)
        pid = int(match.group(1))
        observed = process(pid)
        ancestor = observed
        seen = {pid}
        while ancestor is not None and ancestor[2] != session.pid:
            parent = ancestor[2]
            if parent <= 1 or parent in seen:
                raise RuntimeError('job PID is not an owned PTY descendant')
            seen.add(parent)
            ancestor = process(parent)
        if ancestor is None:
            raise RuntimeError('job PID is not an owned PTY descendant')
        if observed is None or observed[0] != pid or pid == session.pid:
            raise RuntimeError('foreground job lacks an independent real PGID')
        jobs[pid] = observed[0]
        session.wait(lambda: session.foreground() == pid and process(pid) is not None
                     and 'T' not in process(pid)[1])
        return pid

    def interrupt_job(pid):
        start = len(session.output)
        session.send(b'\x03')
        session.wait(lambda: session.foreground() == session.pid)
        session.expect(re.escape(prompt), start)
        label = 'status-' + nonce
        status_command = ("printf 'rel-%%s:<%%s>\\n' %s $status\n" % label).encode()
        start = len(session.output)
        session.send(status_command)
        _, end = session.expect(re.escape(('rel-%s:<130>' % label).encode()), start, status_command)
        session.expect(re.escape(prompt), end)
        session.wait(lambda: process(pid) is None)
        del jobs[pid]

    pid = launch_job()
    interrupt_job(pid)
    check(stage)

    stage = 'Ctrl-Z/bg/fg real PGID'
    pid = launch_job()
    start = len(session.output)
    session.send(b'\x1a')
    session.wait(lambda: session.foreground() == session.pid and process(pid) is not None
                 and 'T' in process(pid)[1])
    session.expect(re.escape(prompt), start)
    start = len(session.output)
    session.send(b'jobs\n')
    _, end = session.expect(rb'\[1\][ +\-]*\s*Stopped\b', start, b'jobs\n')
    session.expect(re.escape(prompt), end)
    start = len(session.output)
    session.send(b'bg 1\n')
    session.wait(lambda: process(pid) is not None and 'T' not in process(pid)[1])
    session.expect(re.escape(prompt), start)
    start = len(session.output)
    session.send(b'jobs\n')
    _, end = session.expect(rb'\[1\][ +\-]*\s*Running\b', start, b'jobs\n')
    session.expect(re.escape(prompt), end)
    session.send(b'fg 1\n')
    session.wait(lambda: session.foreground() == pid)
    interrupt_job(pid)
    check(stage)
    stage = 'interactive termios restoration'
    session.finish()
    check(stage)

    stage = 'history restart isolated HOME'
    writer = Session(history=True)
    writer.expect(re.escape(prompt), 0)
    writer.marker('history-older', 'older')
    writer.marker('history-newest', 'newest')
    writer.finish()
    reader = Session(history=True)
    reader.expect(re.escape(prompt), 0)
    if writer.pid == reader.pid:
        raise RuntimeError('history restart did not start a different process')
    start = len(reader.output)
    reader.send(b'\x1b[A\n')
    _, end = reader.expect(re.escape(('rel-history-newest-%s:<newest>' % nonce).encode()), start, b'\x1b[A\n')
    reader.expect(re.escape(prompt), end)
    reader.finish()
    check(stage)
except BaseException as error:
    failure = '%s: %s' % (stage, error)
finally:
    # Cleanup runs even after deadline/signal failures and never turns one into success.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.setitimer(signal.ITIMER_REAL, max(0.001, deadline - time.monotonic()))

    def cleanup_remaining():
        return max(0.001, deadline - time.monotonic())

    active = {s.pid for s in sessions if s.status is None}
    owned = {pid: 1 for pid in jobs}
    frozen = set()
    # Freeze owned parents before observing descendants, including jobs whose
    # PID marker never arrived or whose PGID assertion failed before registration.
    for pid in active:
        try:
            os.kill(pid, signal.SIGSTOP)
            frozen.add(pid)
        except ProcessLookupError:
            pass
        except BaseException as error:
            cleanup_errors.append('freeze owned PID %d: %s' % (pid, error))
    try:
        snapshot = subprocess.run(['ps', '-axo', 'pid=,ppid='],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  timeout=cleanup_remaining(), env=environment)
        if snapshot.returncode != 0:
            raise RuntimeError('descendant observation failed')
        parents = {int(pid): int(parent) for pid, parent in
                   (row.split() for row in snapshot.stdout.splitlines())}
        for pid in parents:
            ancestor, depth, seen = pid, 0, set()
            while ancestor in parents and ancestor not in active and ancestor not in seen:
                seen.add(ancestor)
                ancestor = parents[ancestor]
                depth += 1
            if ancestor in active and pid not in active:
                owned[pid] = depth
    except BaseException as error:
        cleanup_errors.append('owned descendants: %s' % error)

    for pid in sorted(owned, key=lambda pid: owned[pid], reverse=True):
        for sig in (signal.SIGCONT, signal.SIGKILL):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
            except BaseException as error:
                cleanup_errors.append('owned child PID %d: %s' % (pid, error))
    for pid in frozen:
        try:
            os.kill(pid, signal.SIGCONT)
        except ProcessLookupError:
            pass
        except BaseException as error:
            cleanup_errors.append('resume owned parent PID %d: %s' % (pid, error))
    # Keep parents alive briefly so they can reap killed children before exit.
    try:
        end = min(deadline - 0.5, time.monotonic() + 0.5)
        while owned and time.monotonic() < end:
            probe = subprocess.run(['ps', '-o', 'pid=', '-p', ','.join(map(str, owned))],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   timeout=cleanup_remaining(), env=environment)
            if probe.returncode == 1 and not probe.stdout.strip():
                break
            if probe.returncode not in (0, 1):
                raise RuntimeError('owned-child reaping observation failed')
            time.sleep(0.02)
    except BaseException as error:
        cleanup_errors.append('child-before-parent reaping: %s' % error)
    for session in sessions:
        try:
            if session.status is None:
                # setsid may not have happened when startup failed.
                try:
                    os.kill(session.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        except BaseException as error:
            cleanup_errors.append('owned PID %d: %s' % (session.pid, error))
        for fd in (session.master, session.slave):
            try:
                os.close(fd)
            except BaseException as error:
                cleanup_errors.append('owned PTY fd %d: %s' % (fd, error))
    try:
        pending = set(owned) | active
        while pending:
            # Linux subreaper also adopts children of failed/exited job parents.
            while True:
                try:
                    pid, status = os.waitpid(-1, os.WNOHANG)
                except ChildProcessError:
                    break
                if pid == 0:
                    break
                for session in sessions:
                    if session.pid == pid:
                        session.status = status
            for pid in tuple(pending):
                probe = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       timeout=cleanup_remaining(), env=environment)
                if probe.returncode == 1 and not probe.stdout.strip():
                    pending.remove(pid)
                elif probe.returncode != 0:
                    raise RuntimeError('owned-process absence observation failed')
            if pending and time.monotonic() >= deadline - 0.1:
                raise RuntimeError('owned PIDs remain after cleanup: %s' % sorted(pending))
            if pending:
                time.sleep(0.02)
    except BaseException as error:
        cleanup_errors.append('owned-process postcondition: %s' % error)
    signal.setitimer(signal.ITIMER_REAL, 0)

if failure or cleanup_errors:
    print('FAIL: ' + (failure or 'cleanup failed'), file=sys.stderr)
    for error in cleanup_errors:
        print('cleanup: ' + error, file=sys.stderr)
    sys.exit(1)
if len(passed) != 6 or len(sessions) != 3 or any(s.status != 0 for s in sessions):
    print('FAIL: incomplete PTY execution', file=sys.stderr)
    sys.exit(1)
print('PASS: 6 PTY checks; 3 executable sessions exited zero; owned processes cleaned', flush=True)
PYTHON

my $pid = fork // die "cannot start PTY backend: $!\n";
if (!$pid) {
    exec 'python3', '-c', $backend, $executable, $isolation, $timeout;
    die "python3 PTY backend unavailable: $!\n";
}
my $signal;
local $SIG{INT} = sub { $signal = 'INT'; kill 'TERM', $pid };
local $SIG{TERM} = sub { $signal = 'TERM'; kill 'TERM', $pid };
my $end = time + $timeout + 1;
while (1) {
    my $reaped = waitpid($pid, WNOHANG);
    if ($reaped == $pid) {
        my $status = $?;
        die "PTY backend interrupted\n" if $signal;
        exit(($status & 127) ? 1 : $status >> 8);
    }
    die "cannot reap PTY backend\n" if $reaped == -1;
    if (time >= $end) {
        kill 'TERM', $pid;
        sleep 0.1;
        kill 'KILL', $pid;
        waitpid($pid, 0);
        die "PTY backend exceeded whole-run deadline\n";
    }
    sleep 0.02;
}
