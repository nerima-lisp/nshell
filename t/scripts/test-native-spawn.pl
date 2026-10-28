use strict;
use warnings;
use Test::More;
use Cwd qw(abs_path);
use Config;
use File::Temp qw(tempdir);
use FindBin qw($Bin);

my $repository = abs_path("$Bin/../..");
my $helper = $ENV{CL_PROCESS_KIT_SPAWN} // '';
die "CL_PROCESS_KIT_SPAWN must name the real absolute executable helper\n"
    unless $helper =~ m{^/} && -f $helper && -x $helper;
my $root = abs_path(tempdir('nshell-native-fixture-XXXXXX', TMPDIR => 1, CLEANUP => 1));
my $observations = "$root/observations";
my $instrumented = "$root/helper";
my $perl = abs_path($Config{perlpath});
die "Perl must provide an absolute executable interpreter path\n"
    unless defined $perl && $perl =~ m{^/} && -f $perl && -x $perl;
open my $fixture, '>', $instrumented or die $!;
# $^X can be a bare name after PATH-based invocation, which is not a valid shebang.
print {$fixture} '#!', $perl, "\n", <<'PL';
use strict;
use warnings;
use Cwd qw(getcwd);
use Fcntl qw(:flock);
open my $log, '>>', $ENV{NATIVE_OBSERVATIONS} or die $!;
flock $log, LOCK_EX or die $!;
print {$log} join("\t", $ENV{TMPDIR}, getcwd()), "\n";
close $log or die $!;
exec $ENV{NATIVE_REAL_HELPER}, @ARGV;
die $!;
PL
close $fixture or die $!;
chmod 0700, $instrumented or die $!;
open my $sentinel, '>', "$root/sentinel" or die $!;
print {$sentinel} "preserve\n";
close $sentinel or die $!;

sub start {
    my ($name, $spawn, $tmpdir, $environment) = @_;
    my $log = "$root/$name.log";
    my $pid = fork();
    die $! unless defined $pid;
    if (!$pid) {
        $ENV{CL_PROCESS_KIT_SPAWN} = $spawn;
        $ENV{TMPDIR} = $tmpdir;
        $ENV{NATIVE_REAL_HELPER} = $helper;
        $ENV{NATIVE_OBSERVATIONS} = $observations;
        @ENV{keys %$environment} = values %$environment if $environment;
        open STDOUT, '>', $log or die $!;
        open STDERR, '>&', STDOUT or die $!;
        exec '/bin/bash', "$repository/scripts/test-native-spawn.sh";
        die $!;
    }
    return [$pid, $log];
}

sub finish {
    my ($job) = @_;
    waitpid($job->[0], 0);
    my $status = $?;
    open my $log, '<', $job->[1] or die $!;
    local $/;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, <$log>);
}

my @jobs = (start('first', $instrumented, $root), start('second', $instrumented, $root));
for my $job (@jobs) {
    my ($exit, $output) = finish($job);
    is($exit, 0, 'real pinned upstream test succeeds concurrently');
    like($output, qr/native-spawn-discovery discovered=1 selected=1 upstream-sha256=[a-f0-9]{64}/,
         'one nonempty locked upstream script selected');
    like($output, qr/native-spawn-result executed=1 pass=1 status=PASS/,
         'actual upstream execution passes');
}
open my $log, '<', $observations or die $!;
my %calls;
my $isolated = 1;
while (my $line = <$log>) {
    chomp $line;
    my ($tmpdir, $cwd) = split /\t/, $line;
    $isolated &&= $tmpdir eq $cwd && index($tmpdir, "$root/nshell-native-spawn.") == 0;
    $calls{$tmpdir}++;
}
close $log or die $!;
is(scalar keys %calls, 2, 'concurrent invocations use distinct private tmp parents');
ok($isolated, 'upstream helper uses the exclusive parent as both TMPDIR and cwd');
is_deeply([sort values %calls], [10, 10], 'each real upstream test executes all ten helper scenarios');
ok(!(grep { -e $_ } keys %calls), 'both private parents are removed after success');
ok(-f "$root/sentinel", 'unrelated parent content is preserved');

my $failing = "$root/failing-helper";
open $fixture, '>', $failing or die $!;
print {$fixture} "#!/bin/sh\nexit 7\n";
close $fixture or die $!;
chmod 0700, $failing or die $!;
my ($exit, $output) = finish(start('failure', $failing, $root));
is($exit, 7, 'upstream failure status propagates without conversion to success');
like($output, qr/native-spawn-result executed=1 pass=0 status=FAIL exit=7/,
     'failed upstream execution is explicit');
my @remaining = glob "$root/nshell-native-spawn.*";
is(scalar @remaining, 0, 'private parent is also removed after failure');
($exit, $output) = finish(start('relative-tmp', $instrumented, '.'));
is($exit, 2, 'relative TMPDIR is rejected before unsafe isolation');
like($output, qr/TMPDIR must name an absolute existing directory/, 'invalid tmp environment is explicit');

my $empty = "$root/empty-helper";
open $fixture, '>', $empty or die $!;
print {$fixture} "#!/bin/sh\nexit 0\n";
close $fixture or die $!;
chmod 0700, $empty or die $!;
($exit, $output) = finish(start('empty-helper', $empty, $root));
is($exit, 1, 'an executable no-op helper cannot pass the upstream assertions');
like($output, qr/native-spawn-result executed=1 pass=0 status=FAIL exit=1/,
     'empty helper produces a failed result rather than a vacuous pass');

mkdir "$root/bin" or die $!;
symlink '/usr/bin/dirname', "$root/bin/dirname" or die $!;
($exit, $output) = finish(start('missing-timeout', $instrumented, $root,
                              {SBCL => '/usr/bin/true', PATH => "$root/bin"}));
is($exit, 2, 'missing timeout fails the preflight');
like($output, qr/required tool timeout is unavailable/, 'missing timeout is explicitly identified');
done_testing();
