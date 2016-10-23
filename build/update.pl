#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use File::Spec::Functions qw/catfile/;

require "build/lib/version.pl" or die;

my ($path) = @ARGV;

unless ($path) {
    die "Usage: $0 /path/to/perl.git\n";
}

unless (-d catfile($path, ".git")) {
    die "Could not find perl git checkout at $path.\n";
}

unless (-f "Cargo.toml") {
    die "Run from the top-level crate directory.\n";
}

my $ver_re = qr/^v(\d+)\.(\d+)\.(\d+)$/;

my @tags = grep /$ver_re/, `cd "$path" && git tag`;
chomp @tags;
@tags = sort { version->parse($a) <=> version->parse($b) } @tags;

# released versions
my %latest;
foreach my $tag (@tags) {
    my ($rev, $ver, $sub) = $tag =~ /$ver_re/;
    my $apiver = format_apiver($rev, $ver, $sub);
    $latest{$apiver} = $tag;
}

# blead version
my %blead_ver = map /^#define\s+PERL_API_(\w+)\s*(\d+)/ ? (lc $1, $2) : (),
    `cd "$path" && git show blead:patchlevel.h`;
my $blead_ver = format_apiver(@blead_ver{qw/revision version subversion/});
$latest{$blead_ver} = "blead";

foreach my $apiver (keys %latest) {
    my $embed = `cd "$path" && git show "$latest{$apiver}:embed.fnc"`;
    open my $fh, ">", "build/embed.fnc/$apiver";
    $fh->print($embed);
}
