use strict;
use warnings;

sub format_apiver {
    my ($rev, $ver, $sub) = @_;
    my $str = sprintf "v%d.%d", $rev, $ver;
    $str .= ".$sub" if $ver % 2 != 0;
    return $str;
}

sub current_apiver {
    return format_apiver(@Config::Config{qw/
        api_revision
        api_version
        api_subversion
    /});
}

1;
