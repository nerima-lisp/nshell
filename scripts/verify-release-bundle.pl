#!/usr/bin/env perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Find qw(find);
use File::Basename qw(basename dirname);
use File::Spec;
use File::Temp qw(tempdir);

my ($bundle, @options) = @ARGV;
die "usage: $0 BUNDLE [--no-smoke]\n" unless defined $bundle && -d $bundle;
my $smoke = !grep { $_ eq '--no-smoke' } @options;

for my $relative (qw(
    README.md
    LICENSE
    LICENSES/SBCL-COPYING
    LICENSES/ZSTD-LICENSE
    LICENSES/CL-PROLOG-KIT-LICENSE
    LICENSES/CL-PARSER-KIT-LICENSE
    LICENSES/CL-DATAFLOW-KIT-LICENSE
    LICENSES/CL-HOST-KIT-LICENSE
    LICENSES/CL-BOUNDARY-KIT-LICENSE
    LICENSES/CL-CLI-LICENSE
    LICENSES/CL-TTY-KIT-LICENSE
    LICENSES/CL-LOG-KIT-LICENSE
    LICENSES/CL-PROCESS-KIT-LICENSE
    LICENSES/CL-HISTORY-KIT-LICENSE
    LICENSES/CL-CODEC-KIT-LICENSE
    LICENSES/CL-DATE-KIT-LICENSE
    LICENSES/CL-CONCURRENT-KIT-LICENSE
    share/man/man1/nshell.1
    bin/nshell
)) {
    die "missing release file: $relative\n" unless -f "$bundle/$relative";
}
die "bin/nshell is not executable\n" unless -x "$bundle/bin/nshell";

my @store_references;
# `abs_path`, not `$bundle` directly: `nix build`'s `result` is a symlink to
# the store path, and File::Find only follows a symlink it meets while
# descending -- given one as its OWN starting point, it visits that single
# entry and never opens the directory it points to. Every check below this
# point that uses `-f "$bundle/..."` or `glob "$bundle/..."` is a plain
# string test the OS resolves through the symlink, so this was the only
# scan silently visiting nothing under the exact `... result` invocation
# ci.yml (and this script's own usage line) documents.
find(
    sub {
        return unless -f $_;
        open my $fh, '<:raw', $File::Find::name or die "open $File::Find::name: $!\n";
        local $/;
        my $contents = <$fh>;
        push @store_references, $File::Find::name if $contents =~ m{/nix/store/};
    },
    abs_path($bundle),
);
die "Nix store reference in release bundle:\n  " . join("\n  ", @store_references) . "\n"
    if @store_references;

if ($^O eq 'darwin') {
    my @mach_objects = ("$bundle/bin/nshell");
    my @dylibs = grep { -f $_ } glob "$bundle/lib/*.dylib";
    for my $library (@dylibs) {
        die "no license mapping for bundled Darwin library: " . basename($library) . "\n"
            unless basename($library) =~ /^libzstd(?:\.|$)/;
    }
    push @mach_objects, @dylibs;
    for my $object (@mach_objects) {
        open my $otool, '-|', 'otool', '-L', $object or die "otool: $!\n";
        my @lines = <$otool>;
        close $otool or die "otool -L failed for $object\n";
        shift @lines;
        for my $line (@lines) {
            next unless $line =~ /^\s+(\S+)\s+\(/;
            my $dependency = $1;
            next if $dependency =~ m{^/(?:usr/lib|System/Library)/};

            my $resolved;
            if ($dependency =~ m{^\@executable_path/(.+)$}) {
                $resolved = File::Spec->catfile($bundle, 'bin', $1);
            } elsif ($dependency =~ m{^\@loader_path/(.+)$}) {
                $resolved = File::Spec->catfile(dirname($object), $1);
            } elsif ($dependency =~ m{^\@rpath/([^/]+)$}
                     && dirname($object) eq "$bundle/lib"
                     && $1 eq basename($object)) {
                # A bundled dylib's own install name, not a runtime lookup.
                $resolved = $object;
            } else {
                die "unsupported Mach-O dependency in $object: $dependency\n";
            }
            die "missing bundled Mach-O dependency in $object: $dependency\n"
                unless -f File::Spec->rel2abs($resolved);
        }
    }
} elsif ($^O eq 'linux') {
    my @executables = qw(libexec/nshell libexec/cl-process-kit-spawn);
    for my $relative (@executables, qw(bin/cl-process-kit-spawn lib/ld-linux-x86-64.so.2 LICENSES/GLIBC-COPYING.LIB)) {
        die "missing Linux release file: $relative\n" unless -f "$bundle/$relative";
    }
    for my $relative (@executables, qw(bin/cl-process-kit-spawn lib/ld-linux-x86-64.so.2)) {
        die "$relative is not executable\n" unless -x "$bundle/$relative";
    }

    my %libraries = map { basename($_) => $_ } grep { -f $_ } glob "$bundle/lib/*";
    my @queue = ((map { "$bundle/$_" } @executables), values %libraries);
    my %checked;
    while (my $object = shift @queue) {
        next if $checked{$object}++;
        open my $readelf, '-|', 'readelf', '-d', $object or die "readelf: $!\n";
        my @dynamic = <$readelf>;
        close $readelf or die "readelf -d failed for $object\n";
        for my $line (@dynamic) {
            next unless $line =~ /\(NEEDED\).*\[([^]]+)\]/;
            my $needed = $1;
            die "ELF dependency would fall back to the host in $object: $needed\n"
                unless exists $libraries{$needed};
            push @queue, $libraries{$needed};
        }
    }

    for my $relative (@executables) {
        my $object = "$bundle/$relative";
        open my $headers, '-|', 'readelf', '-l', $object or die "readelf: $!\n";
        my $program_headers = do { local $/; <$headers> };
        close $headers or die "readelf -l failed for $object\n";
        die "unexpected ELF interpreter in $object\n"
            unless $program_headers =~ m{Requesting program interpreter: /lib64/ld-linux-x86-64\.so\.2\]};
    }

    my @license_for = (
        [ qr/^ld-linux-/, 'LICENSES/GLIBC-COPYING.LIB' ],
        [ qr/^lib(?:c|m|dl|rt|pthread|resolv|util|nss_)[.-]/, 'LICENSES/GLIBC-COPYING.LIB' ],
        [ qr/^libzstd[.-]/, 'LICENSES/ZSTD-LICENSE' ],
        [ qr/^lib(?:gcc_s|stdc\+\+)[.-]/, 'LICENSES/GCC-RUNTIME-LIBRARY-EXCEPTION' ],
    );
    LIBRARY: for my $library (sort keys %libraries) {
        for my $mapping (@license_for) {
            my ($pattern, $license) = @$mapping;
            next unless $library =~ $pattern;
            die "missing license $license for $library\n" unless -f "$bundle/$license";
            if ($library =~ /^lib(?:gcc_s|stdc\+\+)/) {
                die "missing GCC license for $library\n"
                    unless -f "$bundle/LICENSES/GCC-COPYING3";
            }
            next LIBRARY;
        }
        die "no license mapping for bundled Linux library: $library\n";
    }
}

exit 0 unless $smoke;

sub run_nshell {
    my ($input, @arguments) = @_;
    my $temporary = tempdir(CLEANUP => 1);
    my $launcher = "$temporary/nshell";
    symlink File::Spec->rel2abs("$bundle/bin/nshell"), $launcher
        or die "Unable to create launcher symlink $launcher: $!\n";
    open my $stdin, '>', "$temporary/in" or die $!;
    print {$stdin} $input;
    close $stdin;
    my $pid = fork // die "fork: $!\n";
    if ($pid == 0) {
        open STDIN, '<', "$temporary/in" or die $!;
        open STDOUT, '>', "$temporary/out" or die $!;
        open STDERR, '>', "$temporary/err" or die $!;
        exec 'env', '-i', 'HOME=' . $temporary, 'PATH=/usr/bin:/bin', $launcher, @arguments;
        die "exec: $!\n";
    }
    waitpid $pid, 0;
    my $status = $?;
    open my $stdout, '<', "$temporary/out" or die $!;
    open my $stderr, '<', "$temporary/err" or die $!;
    local $/;
    my $output = (<$stdout> // '') . (<$stderr> // '');
    die "nshell @arguments failed ($status):\n$output" if $status != 0;
    return $output;
}

run_nshell('', '--help');
run_nshell('', '--version');
my $echo = run_nshell("echo nshell-release-ok\n");
die "echo smoke test produced unexpected output:\n$echo" unless $echo =~ /nshell-release-ok/;
print "release bundle verified: $bundle\n";
