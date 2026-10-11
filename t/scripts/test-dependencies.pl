use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use FindBin qw($Bin);

my $repository = abs_path("$Bin/../..");
my $root = tempdir('nshell-dependency-fixture-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $sbcl = "$root/sbcl";
open my $fixture, '>', $sbcl or die $!;
print {$fixture} <<'SH';
#!/bin/sh
case "$*" in
  *--list) printf '%s\n' cl-process-kit/test cl-history-kit/test ;;
  *--native-spawn-source) echo 'unexpected resolver call' >&2; exit 99 ;;
  *cl-history-kit/signal-fixture-test)
    printf '%s\n' 'dependency signal fixture reached'
    kill -TERM "$NSHELL_DEPENDENCY_FIXTURE_GATE_PID" ;;
esac
SH
close $fixture or die $!;
chmod 0700, $sbcl or die $!;

sub run {
    my ($script, @arguments) = @_;
    my $log = "$root/output";
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        $ENV{SBCL} = $sbcl;
        $ENV{TMPDIR} = $root;
        $ENV{NSHELL_DEPENDENCY_FIXTURE_GATE_PID} = $$;
        delete $ENV{CL_PROCESS_KIT_SPAWN};
        open STDOUT, '>', $log or die $!;
        open STDERR, '>&', STDOUT or die $!;
        exec '/bin/bash', "$repository/scripts/$script", @arguments;
        die $!;
    }
    waitpid($pid, 0);
    my $status = $?;
    open my $output, '<', $log or die $!;
    local $/;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, <$output>);
}

my ($exit, $output) = run('test-dependencies.sh', '--list');
is($exit, 0, 'list succeeds');
like($output, qr/^cl-process-kit\/native-spawn-test$/m, 'ordinary list includes upstream shell test');
($exit, $output) = run('test-dependencies.sh');
is($exit, 1, 'default gate rejects missing native environment');
like($output, qr/dependency-suites selected=3 pass=2 failed=1/, 'native contributes to aggregate result');
like($output, qr/CL_PROCESS_KIT_SPAWN/, 'missing helper is explicit');
($exit, $output) = run('test-dependencies.sh', 'cl-process-kit/test');
is($exit, 1, 'explicit process suite also includes native test');
like($output, qr/dependency-suites selected=2 pass=1 failed=1/, 'explicit process gate cannot omit native');
($exit, $output) = run('test-dependencies.sh', 'cl-history-kit/test');
is($exit, 0, 'unrelated narrow suite does not require native environment');
like($output, qr/dependency-suites selected=1 pass=1 failed=0/, 'narrow selection remains nonempty');
($exit, $output) = run('test-dependencies.sh', 'cl-history-kit/signal-fixture-test');
like($output, qr/^dependency signal fixture reached$/m, 'signal fixture executed inside dependency gate');
is($exit, 143, 'signal-terminated dependency gate cannot pass');
($exit, $output) = run('test-native-spawn.sh');
is($exit, 2, 'standalone native gate reports environment error');
like($output, qr/CL_PROCESS_KIT_SPAWN/, 'standalone missing environment is explicit');
done_testing();
