#!/usr/bin/env perl

use strict;
use warnings;
use B qw(SVp_IOK SVp_NOK svref_2object);
use JSON::PP qw(decode_json);
use POSIX qw(isfinite);
use File::Temp qw(tempfile);

sub fail {
    die "benchmark JSONL verification failed: $_[0]\n";
}

sub object {
    my ($value, $name) = @_;
    fail("$name must be an object") unless ref($value) eq 'HASH';
    return $value;
}

sub array {
    my ($value, $name) = @_;
    fail("$name must be an array") unless ref($value) eq 'ARRAY';
    return $value;
}

sub string {
    my ($value, $name) = @_;
    fail("$name must be a non-empty string")
      if !defined($value) || ref($value) || $value eq '';
    return $value;
}

sub integer {
    my ($value, $name, $minimum) = @_;
    fail("$name must be an integer >= $minimum")
      if !defined($value) || ref($value) || $value !~ /\A\d+\z/ || $value < $minimum;
    return 0 + $value;
}

sub number {
    my ($value, $name) = @_;
    my $numeric = defined($value)
      && !ref($value)
      && (svref_2object(\$value)->FLAGS & (SVp_IOK | SVp_NOK));
    fail("$name must be a finite non-negative JSON number")
      if !$numeric || !isfinite($value) || $value < 0;
    return 0 + $value;
}

sub false_boolean {
    my ($value, $name) = @_;
    fail("$name must be the JSON boolean false")
      unless JSON::PP::is_bool($value) && !$value;
}

sub verify_statistics {
    my ($statistics, $samples, $name) = @_;
    object($statistics, $name);
    fail("$name requires at least one sample") unless @$samples;

    my %values;
    for my $key (qw(min p50 p95 p99 max mean mad)) {
        fail("$name.$key is missing") unless exists $statistics->{$key};
        $values{$key} = number($statistics->{$key}, "$name.$key");
    }
    fail("$name percentiles are not ordered")
      unless $values{min} <= $values{p50}
      && $values{p50} <= $values{p95}
      && $values{p95} <= $values{p99}
      && $values{p99} <= $values{max};
    fail("$name.mean is outside min/max")
      unless $values{min} <= $values{mean} && $values{mean} <= $values{max};
    fail("$name.mad exceeds the observed range")
      unless $values{mad} <= $values{max} - $values{min};

    my ($observed_min, $observed_max) = ($samples->[0], $samples->[0]);
    for my $sample (@$samples) {
        $observed_min = $sample if $sample < $observed_min;
        $observed_max = $sample if $sample > $observed_max;
    }
    my $scale = 1 + $observed_max;
    fail("$name.min does not match raw samples")
      if abs($values{min} - $observed_min) > 1e-8 * $scale;
    fail("$name.max does not match raw samples")
      if abs($values{max} - $observed_max) > 1e-8 * $scale;
}

sub verify_samples {
    my ($record, $sample_key, $statistics_key) = @_;
    my $samples = array($record->{$sample_key}, $sample_key);
    for my $index (0 .. $#$samples) {
        $samples->[$index] = number($samples->[$index], "$sample_key\[$index\]");
    }
    verify_statistics($record->{$statistics_key}, $samples, $statistics_key);
    return $samples;
}

sub common_metadata {
    my ($record) = @_;
    string($record->{source_revision}, 'source_revision');
    string($record->{cpu_model}, 'cpu_model');
    string($record->{benchmark}, 'benchmark');
    string($record->{scope}, 'scope');
    string($record->{scenario}, 'scenario');
    string($record->{cache_state}, 'cache_state');
    string($record->{sample_unit}, 'sample_unit');
    false_boolean($record->{ranking_eligible}, 'ranking_eligible');
}

sub verify_completion {
    my ($record) = @_;
    common_metadata($record);
    fail('schema 1 benchmark must be nshell-completion')
      unless $record->{benchmark} eq 'nshell-completion';
    fail('schema 1 cache_state must be warm') unless $record->{cache_state} eq 'warm';

    my $parameters = object($record->{parameters}, 'parameters');
    my $sample_count = integer($parameters->{samples}, 'parameters.samples', 1);
    integer($parameters->{warmup_batches}, 'parameters.warmup_batches', 1);
    integer($parameters->{batch_size}, 'parameters.batch_size', 1);
    integer($parameters->{warmup_iterations}, 'parameters.warmup_iterations', 1);
    integer($parameters->{measured_iterations}, 'parameters.measured_iterations', 1);
    my $samples = verify_samples(
        $record, 'raw_samples_ms_per_op', 'statistics_ms_per_op');
    fail('parameters.samples does not match raw sample count')
      unless $sample_count == @$samples;

    my $runtime = object($record->{runtime}, 'runtime');
    string($runtime->{implementation}, 'runtime.implementation');
    string($runtime->{implementation_version}, 'runtime.implementation_version');
    string($runtime->{os}, 'runtime.os');
    string($runtime->{os_version}, 'runtime.os_version');
    string($runtime->{architecture}, 'runtime.architecture');
    my $timer = object($record->{timer}, 'timer');
    string($timer->{clock}, 'timer.clock');
    integer($timer->{units_per_second}, 'timer.units_per_second', 1);
    number($timer->{resolution_ms}, 'timer.resolution_ms');
    my $fixture = object($record->{fixture}, 'fixture');
    integer($fixture->{cardinality}, 'fixture.cardinality', 1);
    integer($fixture->{expected_candidates}, 'fixture.expected_candidates', 0);
    object($record->{checksums}, 'checksums');
}

sub verify_process {
    my ($record) = @_;
    common_metadata($record);
    fail('schema 2 benchmark must be shell-process-launch')
      unless $record->{benchmark} eq 'shell-process-launch';
    fail('schema 2 cache_state must be fresh-process-warm-fs')
      unless $record->{cache_state} eq 'fresh-process-warm-fs';
    false_boolean($record->{comparable}, 'comparable');
    string($record->{comparison_reason}, 'comparison_reason');
    string($record->{subject}, 'subject');
    string($record->{version_output}, 'version_output');
    string($record->{os}, 'os');
    string($record->{os_version}, 'os_version');
    string($record->{architecture}, 'architecture');
    integer($record->{timeout_seconds}, 'timeout_seconds', 1);
    integer($record->{order_seed}, 'order_seed', 0);
    array($record->{execution_order}, 'execution_order');
    my $configured = integer($record->{configured_samples}, 'configured_samples', 100);
    my $status = string($record->{status}, 'status');
    fail("unsupported process status $status") unless $status eq 'ok' || $status eq 'skipped';
    my $samples = array($record->{raw_samples_ms}, 'raw_samples_ms');
    for my $index (0 .. $#$samples) {
        $samples->[$index] = number($samples->[$index], "raw_samples_ms\[$index\]");
    }
    if ($status eq 'ok') {
        fail('configured_samples does not match successful raw sample count')
          unless $configured == @$samples;
        verify_statistics($record->{statistics_ms}, $samples, 'statistics_ms');
    } else {
        fail('skipped process record must have no raw samples') if @$samples;
        fail('skipped process record must not have statistics_ms')
          if exists $record->{statistics_ms};
        string($record->{reason}, 'reason');
    }
}

sub verify_record {
    my ($record) = @_;
    object($record, 'record');
    my $version = integer($record->{schema_version}, 'schema_version', 1);
    return verify_completion($record) if $version == 1;
    return verify_process($record) if $version == 2;
    fail("unknown schema_version $version");
}

sub verify_handle {
    my ($handle, $label) = @_;
    my $count = 0;
    my @records;
    while (my $line = <$handle>) {
        ++$count;
        fail("$label line $count is blank") if $line =~ /\A\s*\z/;
        my $record = eval { decode_json($line) };
        fail("$label line $count is invalid JSON: $@") if $@;
        eval { verify_record($record); 1 }
          or fail("$label line $count: $@");
        push @records, $record;
    }
    fail("$label is empty") unless $count;
    return $count;
}

sub completion_fixture {
    return {
        schema_version => 1, source_revision => 'abc', cpu_model => 'cpu',
        benchmark => 'nshell-completion', scope => 'warm fixture', scenario => 'fixed',
        ranking_eligible => JSON::PP::false, cache_state => 'warm',
        sample_unit => 'batch-average-ms-per-operation', raw_samples_ms_per_op => [ 1, 2, 3 ],
        statistics_ms_per_op => { min => 1, p50 => 2, p95 => 3, p99 => 3, max => 3, mean => 2, mad => 1 },
        timer => { clock => 'clock', units_per_second => 1000, resolution_ms => 1 },
        runtime => { implementation => 'SBCL', implementation_version => '2', os => 'OS', os_version => '1', architecture => 'arch' },
        parameters => { warmup_batches => 1, samples => 3, batch_size => 2, warmup_iterations => 2, measured_iterations => 6 },
        fixture => { cardinality => 3, expected_candidates => 1 }, allocation_bytes_per_op => 0,
        checksums => { latency => 1, allocation => 1 },
    };
}

sub process_fixture {
    my @samples = (1) x 100;
    return {
        schema_version => 2, source_revision => 'abc', cpu_model => 'cpu',
        benchmark => 'shell-process-launch', scope => 'process fixture', subject => 'nshell',
        executable_path => '/bin/nshell', version_output => 'nshell 1', os => 'OS', os_version => '1', architecture => 'arch',
        configured_samples => 100, timeout_seconds => 30, order_seed => 1,
        execution_order => ['nshell/cli'], scenario => 'cli', status => 'ok',
        comparable => JSON::PP::false, comparison_reason => 'not equivalent',
        ranking_eligible => JSON::PP::false, cache_state => 'fresh-process-warm-fs',
        sample_unit => 'milliseconds-per-process', raw_samples_ms => \@samples,
        statistics_ms => { min => 1, p50 => 1, p95 => 1, p99 => 1, max => 1, mean => 1, mad => 0 },
    };
}

sub self_test {
    my @valid = (completion_fixture(), process_fixture());
    verify_record($_) for @valid;

    my @invalid;
    push @invalid, sub { verify_record({ %{ completion_fixture() }, schema_version => 99 }) };
    push @invalid, sub { my $r = completion_fixture(); $r->{parameters}{samples} = 4; verify_record($r) };
    push @invalid, sub { my $r = completion_fixture(); $r->{raw_samples_ms_per_op}[0] = -1; verify_record($r) };
    push @invalid, sub { my $r = completion_fixture(); $r->{raw_samples_ms_per_op}[0] = '1'; verify_record($r) };
    push @invalid, sub { my $r = completion_fixture(); $r->{statistics_ms_per_op}{p50} = 4; verify_record($r) };
    push @invalid, sub { my $r = process_fixture(); $r->{comparable} = JSON::PP::true; verify_record($r) };
    push @invalid, sub { my $r = process_fixture(); $r->{ranking_eligible} = JSON::PP::true; verify_record($r) };
    push @invalid, sub { my $r = process_fixture(); $r->{configured_samples} = 99; verify_record($r) };
    for my $case (@invalid) {
        fail('self-test accepted an invalid record') if eval { $case->(); 1 };
    }

    my ($empty, $empty_path) = tempfile();
    close $empty;
    open my $input, '<', $empty_path or fail("cannot open self-test file: $!");
    fail('self-test accepted an empty file') if eval { verify_handle($input, $empty_path); 1 };
    close $input;

    my ($broken, $broken_path) = tempfile();
    print {$broken} '{"schema_version":';
    close $broken;
    open $input, '<', $broken_path or fail("cannot open self-test file: $!");
    fail('self-test accepted malformed JSON') if eval { verify_handle($input, $broken_path); 1 };
    close $input;
    print "benchmark JSONL verifier self-test passed\n";
}

if (@ARGV == 1 && $ARGV[0] eq '--self-test') {
    self_test();
    exit 0;
}
fail('usage: verify-benchmark-jsonl.pl --self-test | FILE [FILE ...]') unless @ARGV;
for my $path (@ARGV) {
    open my $handle, '<', $path or fail("cannot open $path: $!");
    my $count = verify_handle($handle, $path);
    close $handle or fail("cannot close $path: $!");
    print "$path: $count benchmark record(s) verified\n";
}
