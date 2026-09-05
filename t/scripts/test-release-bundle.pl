use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use FindBin qw($Bin);

my $repository = abs_path("$Bin/../..");
my $script = "$repository/scripts/verify-release-bundle.pl";
# Synthetic readelf output checks gate decisions, not real ELF execution or Linux smoke behavior.
my $root = tempdir('.release-bundle-test-XXXXXX', DIR => $repository, CLEANUP => 1);
$root = abs_path($root);
sub write_file {
    my ($path, $contents, $mode) = @_;
    open my $fh, '>', $path or die "$path: $!";
    print {$fh} $contents;
    close $fh or die $!;
    chmod $mode, $path or die $! if defined $mode;
}
make_path("$root/tools");
write_file("$root/tools/readelf", '#!' . $^X . "\n" . <<'STUB', 0755);
use strict;
use warnings;
my ($flag, $object) = @ARGV;
open my $trace, '>>', $ENV{GATE_TRACE} or die $!;
print {$trace} "$flag $object\n";
close $trace;
my $helper = $object =~ m{/libexec/cl-process-kit-spawn$};
exit 2 if $helper && $ENV{GATE_CASE} eq 'readelf-failure';
if ($flag eq '-d') {
    print " (NEEDED) Shared library: [libmissing.so.1]\n"
        if $helper && $ENV{GATE_CASE} eq 'dependency';
} elsif ($flag eq '-l') {
    my $interpreter = $helper && $ENV{GATE_CASE} eq 'interpreter'
        ? '/lib64/ld-linux-x86-64.so.2.extra' : '/lib64/ld-linux-x86-64.so.2';
    print " [Requesting program interpreter: $interpreter]\n";
} else { die "unexpected readelf flag $flag" }
STUB
my @licenses = qw(SBCL-COPYING ZSTD-LICENSE CL-PROLOG-KIT-LICENSE CL-PARSER-KIT-LICENSE CL-DATAFLOW-KIT-LICENSE CL-HOST-KIT-LICENSE CL-BOUNDARY-KIT-LICENSE CL-CLI-LICENSE CL-TTY-KIT-LICENSE CL-LOG-KIT-LICENSE CL-PROCESS-KIT-LICENSE CL-HISTORY-KIT-LICENSE CL-CODEC-KIT-LICENSE CL-DATE-KIT-LICENSE CL-CONCURRENT-KIT-LICENSE GLIBC-COPYING.LIB);
my @cases = (
    ['control', undef, undef],
    ['missing-launcher', 'bin/cl-process-kit-spawn', qr/missing Linux release file: bin\/cl-process-kit-spawn/],
    ['missing-helper', 'libexec/cl-process-kit-spawn', qr/missing Linux release file: libexec\/cl-process-kit-spawn/],
    ['nonexec-launcher', 'bin/cl-process-kit-spawn', qr/bin\/cl-process-kit-spawn is not executable/],
    ['nonexec-helper', 'libexec/cl-process-kit-spawn', qr/libexec\/cl-process-kit-spawn is not executable/],
    ['dependency', undef, qr/ELF dependency would fall back to the host.*libmissing.so.1/],
    ['interpreter', undef, qr/unexpected ELF interpreter/],
    ['readelf-failure', undef, qr/readelf -d failed/],
);
for my $case (@cases) {
    my ($name, $target, $error) = @$case;
    my $bundle = "$root/$name";
    make_path(map { "$bundle/$_" } qw(bin libexec lib LICENSES share/man/man1));
    for my $relative ('README.md', 'LICENSE', 'share/man/man1/nshell.1', map { "LICENSES/$_" } @licenses) {
        write_file("$bundle/$relative", "fixture\n", 0644);
    }
    for my $relative (qw(bin/nshell bin/cl-process-kit-spawn libexec/nshell libexec/cl-process-kit-spawn lib/ld-linux-x86-64.so.2)) {
        next if $name =~ /^missing-/ && $relative eq $target;
        write_file("$bundle/$relative", "fixture\n", $name =~ /^nonexec-/ && $relative eq $target ? 0644 : 0755);
    }
    local $ENV{PATH} = "$root/tools:$ENV{PATH}";
    local $ENV{GATE_CASE} = $name;
    local $ENV{GATE_TRACE} = "$root/$name.trace";
    my $pid = fork // die $!;
    if (!$pid) {
        open STDOUT, '>', "$root/$name.out" or die $!;
        open STDERR, '>&', \*STDOUT or die $!;
        exec $^X, '-e', 'local $^O = "linux"; my $script = shift @ARGV; do $script; die $@ || $!;', $script, $bundle, '--no-smoke';
        die $!;
    }
    waitpid $pid, 0;
    my $status = $?;
    open my $output, '<', "$root/$name.out" or die $!;
    my $text = do { local $/; <$output> };
    if ($error) {
        isnt($status, 0, "$name rejects fixture");
        like($text, $error, "$name diagnostic");
    } else {
        is($status, 0, 'known-good synthetic control accepted');
        open my $trace, '<', "$root/$name.trace" or die $!;
        my $calls = do { local $/; <$trace> };
        like($calls, qr/-d .*libexec\/cl-process-kit-spawn/, 'helper dynamic dependencies inspected');
        like($calls, qr/-l .*libexec\/cl-process-kit-spawn/, 'helper interpreter inspected');
    }
}
done_testing(17);
