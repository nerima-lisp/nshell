use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use POSIX qw(WNOHANG);
use Time::HiRes qw(time sleep);

my $repository = abs_path("$Bin/../..");
my $runner = "$repository/scripts/test-release-pty.pl";
my $root = tempdir('nshell-pty-fixtures-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $bash = '/bin/bash';
BAIL_OUT('independent real-PTY fixtures require /bin/bash') unless -x $bash;

sub write_file {
    my ($path, $contents, $mode) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $contents or die $!;
    close $fh or die $!;
    chmod $mode, $path or die $! if defined $mode;
}

sub read_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!";
    local $/;
    return <$fh>;
}

sub perl_literal {
    my ($text) = @_;
    $text =~ s/([\\'])/\\$1/g;
    return "'$text'";
}

sub fixture {
    my ($name) = @_;
    my $bundle = "$root/$name bundle";  # Exercise argv paths, not shell interpolation.
    make_path("$bundle/bin", "$bundle/libexec");
    my $rc = "$bundle/fixture.bashrc";
    my $trace = "$bundle/trace";
    my $job_trace = "$bundle/jobs";
    my $settings = <<'BASH';
PS1=$NSHELL_PROMPT
PROMPT_COMMAND='status=$?'
HISTCONTROL=
HISTIGNORE=
HISTFILE=$HOME/.nshell_history
HISTSIZE=100
HISTFILESIZE=100
if [ "$FIXTURE_HISTORY" = off ]; then unset HISTFILE; fi
BASH
    $settings .= "bind '\"\\C-h\":forward-char'\n" if $name eq 'bad-edit';
    $settings .= "unset HISTFILE\n" if $name eq 'no-history';
    $settings .= "trap '' INT\n" if $name eq 'ignored-pending';
    if ($name eq 'ansi-pending') {
        # Consume the real pending input without rendering it; only emit ANSI color 91.
        $settings .= <<'BASH';
ansi_pending() {
    local discarded
    IFS= read -r -s -n 6 discarded
    printf '%s\n' "$discarded" > "$FIXTURE_PENDING_TRACE"
    bind '"e":self-insert'
    READLINE_LINE=
    READLINE_POINT=0
    printf '\033[1;91m\033[0m'
}
fixture_prompts=0
PROMPT_COMMAND='status=$?; fixture_prompts=$((fixture_prompts + 1)); if [ "$fixture_prompts" = 3 ]; then bind -x '\''"e":ansi_pending'\''; fi'
BASH
    }
    $settings .= "PROMPT_COMMAND='status=\$?; set +m'\n" if $name eq 'no-job-control';
    $settings .= "jobs() { printf 'broken job table\\n'; }\n" if $name eq 'bad-jobs';
    make_path("$bundle/tools");
    my $sleep_program = '#!' . $^X . "\nuse strict; use warnings;\n";
    $sleep_program .= 'open my $log, ">>", ' . perl_literal($job_trace) . " or die \$!;\n";
    $sleep_program .= 'print {$log} "$$\n"; close $log;' . "\n";
    $sleep_program .= "\$SIG{INT} = 'IGNORE';\n" if $name eq 'ignored-foreground';
    $sleep_program .= 'exec "/bin/sleep", @ARGV; die $!;' . "\n";
    write_file("$bundle/tools/sleep", $sleep_program, 0755);
    if ($name eq 'watchdog') {
        # Independent wedged backend: real descendants, no cooperative TERM handler.
        my $wedged = '#!' . $^X . "\nuse strict; use warnings;\n";
        $wedged .= '$SIG{TERM} = "IGNORE";' . "\n";
        $wedged .= '$ENV{HOME} = "$ARGV[3]/home"; my $child = fork // die $!;' . "\n";
        $wedged .= 'if (!$child) { exec $ARGV[2], "--no-config", "--no-history"; die $!; }' . "\n";
        $wedged .= 'sleep 30; waitpid($child, 0); sleep 30; exit 0;' . "\n";
        write_file("$bundle/tools/python3", $wedged, 0755);
    }
    $settings .= 'PATH=' . perl_literal("$bundle/tools:/usr/bin:/bin") . "\n";
    if ($name eq 'missing-job-marker') {
        my $sh_program = '#!' . $^X . "\nuse strict; use warnings;\n";
        $sh_program .= 's{> /dev/tty}{> /dev/null}g for @ARGV; exec "/bin/sh", @ARGV; die $!;' . "\n";
        write_file("$bundle/tools/sh", $sh_program, 0755);
    }
    write_file($rc, $settings, 0600);
    my $program = '#!' . $^X . "\nuse strict; use warnings;\n";
    $program .= 'open my $log, ">>", ' . perl_literal($trace) . " or die \$!;\n";
    $program .= 'print {$log} "$$|$ENV{HOME}|" . join(" ", @ARGV) . "\n"; close $log;' . "\n";
    $program .= <<'PERL';
die "unexpected public CLI arguments" unless @ARGV >= 1 && $ARGV[0] eq '--no-config';
die "unexpected public CLI arguments" if @ARGV > 2 || (@ARGV == 2 && $ARGV[1] ne '--no-history');
$ENV{FIXTURE_HISTORY} = @ARGV == 2 ? 'off' : 'on';
PERL
    $program .= '$ENV{FIXTURE_PENDING_TRACE} = ' . perl_literal("$bundle/pending") . ";\n"
        if $name eq 'ansi-pending';
    if ($name eq 'watchdog' || $name eq 'signal') {
        # Synchronize on a real descendant, then stop the backend, not the runner.
        $program .= 'my $backend = getppid(); my $child = fork // die $!;' . "\n";
        $program .= 'if (!$child) { exec "/bin/sleep", "30"; die $!; }' . "\n";
        $program .= 'kill "STOP", $backend or die $!;' . "\n";
        $program .= 'open my $jobs, ">>", ' . perl_literal($job_trace) . ' or die $!;' . "\n";
        $program .= 'print {$jobs} "$child\n"; close $jobs; sleep 30; exit 0;' . "\n";
    } elsif ($name eq 'hang') {
        $program .= "sleep 30; exit 0;\n";
    } elsif ($name eq 'echo-only') {
        $program .= 'print $ENV{NSHELL_PROMPT}; $|=1; while (<STDIN>) { print $_; print $ENV{NSHELL_PROMPT}; } exit 0;' . "\n";
    } elsif ($name eq 'exit-zero') {
        $program .= "exit 0;\n";
    } else {
        # This is an independent interactive shell, not a canned expected-output transcript.
        $program .= "system('/bin/stty', '-onlcr') == 0 or die 'stty failed';\n"
            if $name eq 'bad-termios';
        $program .= 'exec ' . perl_literal($bash) . ', "--noprofile", "--rcfile", '
            . perl_literal($rc) . ', "-i"; die $!;' . "\n";
    }
    write_file("$bundle/bin/nshell", $program, 0755);
    write_file("$bundle/libexec/nshell", "\x7fELFfixture\n", 0755) if $name eq 'linux-elf';
    return ($bundle, $trace, $job_trace);
}

sub run_fixture {
    my ($name, $timeout) = @_;
    my ($bundle, $trace, $job_trace) = fixture($name);
    my $output = "$bundle/output";
    my $start = time;
    my $pid = fork // die $!;
    if (!$pid) {
        open STDOUT, '>', $output or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        $ENV{PATH} = "$bundle/tools:$ENV{PATH}" if $name eq 'watchdog';
        exec $^X, $runner, $bundle, '--timeout', $timeout;
        die $!;
    }
    my $end = time + $timeout + 5;
    my $signalled = 0;
    while (waitpid($pid, WNOHANG) == 0) {
        if ($name eq 'signal' && !$signalled && -s $job_trace) {
            kill 'TERM', $pid or die "cannot signal owned runner: $!";
            $signalled = 1;
        }
        if (time >= $end) {
            kill 'TERM', $pid;
            sleep 0.2;
            kill 'KILL', $pid;
            waitpid($pid, 0);
            BAIL_OUT("$name runner exceeded test deadline");
        }
        sleep 0.02;
    }
    my $status = $?;
    my $text = read_file($output);
    my @trace = -f $trace ? split(/\n/, read_file($trace)) : ();
    for my $record (@trace) {
        my ($child, $home, $arguments) = split /\|/, $record, 3;
        ok(!kill(0, $child), "$name owned executable PID cleaned");
        ok(!-d $home, "$name isolated HOME removed");
        like($arguments, qr/^--no-config(?: --no-history)?$/, "$name public CLI only");
    }
    my @jobs = -f $job_trace ? split(/\n/, read_file($job_trace)) : ();
    for my $job (@jobs) {
        like($job, qr/^\d+$/, "$name independent job PID trace");
        ok(!kill(0, $job), "$name owned job PID absent after cleanup (including zombies)");
    }
    return ($status, $text, \@trace, time - $start, \@jobs);
}

# An inherited HOME and injection variables must never reach the executable.
make_path("$root/user-home");
write_file("$root/user-home/.nshell_history", "untouched-user-history\n", 0600);
local $ENV{HOME} = "$root/user-home";
local $ENV{NSHELL_PROMPT} = 'incorrect-inherited-prompt';
local $ENV{SBCL_HOME} = '/must/not/load';
local $ENV{BASH_ENV} = '/must/not/load';

my ($status, $text, $records, $elapsed, $jobs) = run_fixture('control', 20);
is($status, 0, 'independent Bash control passes real PTY checks');
diag($text) if $status;
like($text, qr/^PASS: 6 PTY checks; 3 executable sessions exited zero; owned processes cleaned$/m,
    'nonzero assertion and session completion counts');
like($text, qr/^CLEANUP: owned processes absent; PTYs closed$/m,
    'control positively confirms cleanup completion');
is(scalar @$records, 3, 'three actual executable launches');
is(scalar @$jobs, 2, 'two independently observed foreground jobs');
my @homes = map { (split /\|/)[1] } @$records;
is(scalar(keys %{ { map { $_ => 1 } @homes } }), 1, 'history restarts reuse the same isolated HOME');
isnt($homes[0], $ENV{HOME}, 'fixture cannot touch inherited HOME');

for my $case (
    ['bad-edit', qr/FAIL: editing\/backspace:/],
    ['echo-only', qr/FAIL: interactive readiness:/],
    ['exit-zero', qr/FAIL: startup:/],
    ['ignored-pending', qr/FAIL: Ctrl-C pending input:/],
    ['ansi-pending', qr/FAIL: Ctrl-C pending input: expected output deadline exceeded/],
    ['ignored-foreground', qr/FAIL: Ctrl-C foreground:/],
    ['missing-job-marker', qr/FAIL: Ctrl-C foreground:/],
    ['no-job-control', qr/FAIL: Ctrl-C foreground: foreground job lacks an independent real PGID/],
    ['bad-jobs', qr/FAIL: Ctrl-Z\/bg\/fg real PGID:/],
    ['bad-termios', qr/FAIL: interactive termios restoration: interactive termios was not restored \(oflag: \d+ -> \d+\)/],
    ['no-history', qr/FAIL: history restart isolated HOME:/],
    ['hang', qr/FAIL: startup: .*deadline/],
    ['watchdog', qr/PTY backend exceeded whole-run deadline/],
    ['signal', qr/PTY backend interrupted/],
) {
    my ($name, $diagnostic) = @$case;
    my ($result, $output, $trace, $elapsed, $jobs) = run_fixture($name, 9);
    diag(sprintf '%s runner exit=%d signal=%d elapsed=%.3f seconds',
        $name, $result >> 8, $result & 127, $elapsed) if $name eq 'watchdog' || $name eq 'signal';
    isnt($result, 0, "$name rejects broken behavior (no skip success)");
    like($output, $diagnostic, "$name fails at the relevant assertion");
    diag($output) unless $output =~ $diagnostic;
    cmp_ok($elapsed, '<', 11, "$name whole-run deadline bounded");
    cmp_ok(scalar @$trace, '>=', 1, "$name really executed the fixture");
    cmp_ok(scalar @$jobs, '>=', 1, "$name cleanup exercised a real child before failure")
        if $name =~ /^(?:ignored-foreground|missing-job-marker|no-job-control|bad-jobs|watchdog|signal)$/;
    unlike($output, qr/^cleanup:/m, "$name cleanup completed without suppressed errors");
    like($output, qr/^CLEANUP: owned processes absent; PTYs closed$/m,
        "$name positively confirms cleanup completion after failure");
    is(read_file("$root/$name bundle/pending"), "xit 91\n",
        'ANSI-only control consumed the entire pending input independently')
        if $name eq 'ansi-pending';
}

if ($^O eq 'darwin') {
    my ($result, $output, $trace) = run_fixture('linux-elf', 9);
    isnt($result, 0, 'Linux bundle rejected on macOS');
    like($output, qr/Linux ELF bundle cannot be verified on Darwin \(no skip\)/,
        'platform incompatibility is not a successful skip');
    is(scalar @$trace, 0, 'incompatible platform rejected before executable launch');
}
is(read_file("$root/user-home/.nshell_history"), "untouched-user-history\n", 'inherited history unchanged');
done_testing();
