#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use JSON::PP qw(encode_json);
use POSIX qw(uname);
use Symbol qw(gensym);
use Time::HiRes qw(time);

sub abort { die "competitor benchmark failed: $_[0]\n" }

my $run_id = $ENV{NSHELL_COMPARE_RUN_ID} // '';
abort('NSHELL_COMPARE_RUN_ID is required') unless $run_id =~ /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/;
my $samples = $ENV{NSHELL_COMPARE_SAMPLES} // 100;
abort('NSHELL_COMPARE_SAMPLES must be an integer >= 100')
  unless $samples =~ /\A\d+\z/ && $samples >= 100;
my $timeout = $ENV{NSHELL_COMPARE_TIMEOUT} // 30;
abort('NSHELL_COMPARE_TIMEOUT must be a positive integer')
  unless $timeout =~ /\A\d+\z/ && $timeout > 0;
my $output_path = $ENV{NSHELL_COMPARE_JSONL} // 'competitors.jsonl';
my $repetitions = $ENV{NSHELL_COMPARE_REPETITIONS} // 2;
abort('NSHELL_COMPARE_REPETITIONS must be an integer >= 2')
  unless $repetitions =~ /\A\d+\z/ && $repetitions >= 2;
my $batch_commands = $ENV{NSHELL_COMPARE_BATCH_COMMANDS} // 100;
abort('NSHELL_COMPARE_BATCH_COMMANDS must be a positive integer')
  unless $batch_commands =~ /\A\d+\z/ && $batch_commands > 0;

my @fixture_arguments = ('-c', 'echo nshell-bench-sentinel');
my $batch_command = "printf nshell-bench-sentinel\n";
my $batch_input = $batch_command x $batch_commands;
my $batch_output = 'nshell-bench-sentinel' x $batch_commands;

my @definitions = (
    [ nshell => 'NSHELL_BENCH_NSHELL_BIN' ],
    [ bash   => 'NSHELL_BENCH_BASH_BIN' ],
    [ zsh    => 'NSHELL_BENCH_ZSH_BIN' ],
);

sub nix_store_executable {
    my ($path) = @_;
    return defined($path)
      && $path =~ m{\A/nix/store/[a-z0-9]{32}-[^/]+/.+\z}
      && -f $path && -x $path;
}

my @candidates;
for my $definition (@definitions) {
    my ($name, $variable) = @$definition;
    my $path = $ENV{$variable};
    next unless defined($path) && length($path);
    abort("$variable must name an executable under /nix/store") unless nix_store_executable($path);
    push @candidates, { name => $name, path => $path, arguments => \@fixture_arguments };
}
abort('set at least one NSHELL_BENCH_*_BIN candidate') unless @candidates;

my $home = tempdir('nshell-compare-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my %isolated_environment = (
    HOME => $home, LANG => 'C', LC_ALL => 'C', NO_COLOR => '1', TERM => 'dumb', TZ => 'UTC',
);

sub run_sample {
    my ($candidate, $arguments, $stdin, $expected_stdout) = @_;
    local %ENV = %isolated_environment;
    my ($input, $output, $error);
    $error = gensym;
    my $start = time;
    my ($pid, $status, $stdout, $stderr);
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $timeout;
        $pid = open3($input, $output, $error, $candidate->{path}, @$arguments);
        print {$input} $stdin or die "cannot write benchmark stdin: $!\n" if length($stdin);
        close $input;
        $stdout = do { local $/; <$output> // '' };
        $stderr = do { local $/; <$error> // '' };
        waitpid($pid, 0);
        $status = $?;
        alarm 0;
    };
    my $failure = $@;
    if ($failure) {
        kill 'KILL', $pid if $pid;
        waitpid($pid, 0) if $pid;
        return (undef, "execution failed: $failure");
    }
    return (undef, "exit status " . ($status >> 8) . ": $stderr") if $status != 0;
    return (undef, "unexpected stderr: $stderr") unless $stderr eq '';
    return (undef, "unexpected stdout: $stdout") unless $stdout eq $expected_stdout;
    return ((time - $start) * 1000, undef);
}

my @scenarios = (
    {
        name => 'cli-sentinel', arguments => \@fixture_arguments, stdin => '',
        expected_stdout => "nshell-bench-sentinel\n",
        benchmark => 'shell-competitor-process-launch',
        scope => 'fresh process per sample; warm OS filesystem and executable caches',
        cache_state => 'fresh-process-warm-fs', sample_unit => 'milliseconds-per-process',
        fixture => { name => 'common-echo-literal-v1', expected_stdout => "nshell-bench-sentinel\n", expected_stderr => '', expected_exit_status => 0 },
    },
    {
        name => 'resident-batch-throughput', arguments => [], stdin => $batch_input,
        expected_stdout => $batch_output,
        benchmark => 'shell-competitor-resident-batch',
        scope => 'one process per sample; complete command stream is written before stdin is closed, then the process is awaited with warm OS caches',
        cache_state => 'resident-process-warm-fs', sample_unit => 'milliseconds-per-command',
        fixture => { name => 'common-stdin-printf-batch-v1', command => $batch_command, command_count => 0 + $batch_commands, input_bytes => length($batch_input), expected_stdout_per_command => 'nshell-bench-sentinel', expected_stdout_bytes => length($batch_output), expected_stderr => '', expected_exit_status => 0 },
    },
);

sub statistics {
    my ($samples) = @_;
    my @sorted = sort { $a <=> $b } @$samples;
    my $percentile = sub {
        my ($fraction) = @_;
        return $sorted[int($fraction * $#sorted + 0.5)];
    };
    my $mean = 0;
    $mean += $_ for @sorted;
    $mean /= @sorted;
    my @deviations = sort { $a <=> $b } map { abs($_ - $mean) } @sorted;
    return {
        min => $sorted[0], p50 => $percentile->(0.50), p95 => $percentile->(0.95),
        p99 => $percentile->(0.99), max => $sorted[-1], mean => $mean,
        mad => $deviations[int(0.50 * $#deviations + 0.5)],
    };
}

my (undef, undef, undef, undef, $machine) = uname();
my %probe_failure;
for my $scenario (@scenarios) {
for my $candidate (@candidates) {
    my (undef, $reason) = run_sample($candidate, $scenario->{arguments}, $scenario->{stdin}, $scenario->{expected_stdout});
    $probe_failure{"$scenario->{name}/$candidate->{name}"} = "preflight: $reason" if defined $reason;
}
}

my @results;
for my $repetition (1 .. $repetitions) {
for my $scenario (@scenarios) {
for my $candidate (@candidates) {
    my (@raw, $failure);
    $failure = $probe_failure{"$scenario->{name}/$candidate->{name}"};
    for (1 .. $samples) {
        last if $failure;
        my ($elapsed, $reason) = run_sample($candidate, $scenario->{arguments}, $scenario->{stdin}, $scenario->{expected_stdout});
        if (defined($reason)) { $failure = $reason; last }
        push @raw, $scenario->{name} eq 'resident-batch-throughput'
          ? $elapsed / $batch_commands : $elapsed;
    }
    push @results, {
        schema_version => 3,
        benchmark => $scenario->{benchmark},
        source_revision => ($ENV{NSHELL_BENCH_SOURCE_REVISION} // 'unknown'),
        cpu_model => $machine,
        scope => $scenario->{scope},
        scenario => $scenario->{name}, cache_state => $scenario->{cache_state},
        sample_unit => $scenario->{sample_unit},
        run_id => $run_id, repetition_run_id => "$run_id/$scenario->{name}/$repetition/$candidate->{name}",
        repetition_index => $repetition, configured_repetitions => 0 + $repetitions,
        fixture => $scenario->{fixture},
        configured_samples => 0 + $samples, timeout_seconds => 0 + $timeout,
        subject => $candidate->{name}, executable_path => $candidate->{path},
        command_argv => [ $candidate->{path}, @{$scenario->{arguments}} ],
        environment_policy => 'allowlist-v1',
        environment => { map { $_ => ($_ eq 'HOME' ? '<temporary-directory>' : $isolated_environment{$_}) } sort keys %isolated_environment },
        raw_samples_ms => \@raw,
        status => ($failure ? 'failed' : 'ok'),
    };
    if ($failure) { $results[-1]->{failure_reason} = $failure }
    else { $results[-1]->{statistics_ms} = statistics(\@raw) }
}
}
}

for my $scenario (@scenarios) {
for my $candidate (@candidates) {
    my (undef, $reason) = run_sample($candidate, $scenario->{arguments}, $scenario->{stdin}, $scenario->{expected_stdout});
    $probe_failure{"$scenario->{name}/$candidate->{name}"} = "postflight: $reason" if defined $reason;
}
}
my $eligible = @candidates >= 2 && !grep { $_->{status} ne 'ok' } @results;
$eligible = 0 if keys %probe_failure;
open my $jsonl, '>', $output_path or abort("cannot open $output_path: $!");
for my $record (@results) {
    $record->{comparable} = $eligible ? JSON::PP::true : JSON::PP::false;
    $record->{ranking_eligible} = $eligible ? JSON::PP::true : JSON::PP::false;
    $record->{comparison_reason} = $eligible
      ? 'identical argv and verified observable result across all candidates before and after measurement'
      : 'fixture equivalence not established for every candidate and repetition';
    print {$jsonl} encode_json($record), "\n" or abort("cannot write $output_path: $!");
}
close $jsonl or abort("cannot close $output_path: $!");
print "$output_path: wrote " . scalar(@results) . " benchmark record(s); ranking eligible: " . ($eligible ? 'yes' : 'no') . "\n";
