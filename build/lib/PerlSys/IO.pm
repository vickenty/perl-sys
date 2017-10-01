package PerlSys::IO;
use strict;
use warnings;
use autodie;

use Exporter "import";
use File::Spec::Functions qw/catfile/;

our @EXPORT_OK = qw/
    OUT_DIR
    read_file
    write_file
    strip
/;

our %EXPORT_TAGS = (all => \@EXPORT_OK);

use constant {
    OUT_DIR => $ENV{OUT_DIR} // ".",
};

sub read_file {
    my ($name, %opts) = @_;
    open my $fh, "<", $name;
    my @lines = <$fh>;
    close $fh;
    chomp foreach @lines;
    return @lines;
}

sub write_file {
    my ($name, @lines) = @_;
    open my $fh, ">", catfile(OUT_DIR, $name);
    $fh->print(map "$_\n", @lines);
    close $fh;
}

sub strip {
    shift =~ s/^\s+//r =~ s/\s+$//r;
}

1;
