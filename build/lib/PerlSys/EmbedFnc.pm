package PerlSys::EmbedFnc;
use strict;
use warnings;
use autodie;

use Config::Perl::V;
use Exporter "import";
use File::Spec::Functions qw/catfile/;
use FindBin qw/$Bin/;
use PerlSys::IO qw/read_file strip/;
use PerlSys::Version qw/current_apiver/;

our @EXPORT_OK = qw/
    parse_argument
    read_embed_fnc
/;

our %EXPORT_TAGS = (all => \@EXPORT_OK);

use constant {
    EMBED_FNC_PATH => "$Bin/embed.fnc",

    BLACKLIST => {
        "sv_nolocking" => "listed as part of public api, but not actually defined",
        "sv_nounlocking" => "listed as part of public api, but does nothing",
        "sv_nosharing" => "listed as part of the public api, but does nothing",
        "op_class" => "return type OPclass is not yet supported",
    },
};

sub parse_argument {
    my ($arg) = @_;

    if ($arg eq "...") {
        return [ "..." ];
    }

    my ($type, $name) = $arg =~ /(.*)\b(\w+)/ or die "unparsable argument '$arg'";

    $type = strip($type);
    $name = strip($name);

    $name =~ s/^/a_/ if $name =~ /^(?:type|fn|unsafe|let|loop|ref)$/;

    return [ $type, $name ];
}


sub read_embed_fnc {
    my $embed_path = catfile(EMBED_FNC_PATH, current_apiver());
    my $opts = Config::Perl::V::myconfig()->{options};
    my @lines = read_file($embed_path);
    my @scope = (1);
    my @spec;
    while (defined ($_ = shift @lines)) {
        while (@lines && s/\\$/shift @lines/e) {}

        next if !$_ || /^:/;

        s/#\s*ifdef\s+(\w+)/#if defined($1)/;
        s/#\s*ifndef\s+(\w+)/#if !defined($1)/;

        if (my ($pp, $args) = /^#\s*(\w+)(.*)/) {
            if ($pp eq "if") {
                $args =~ s/defined\s*\([\w+]\)/\$opts->{$1}/;
                unshift @scope, eval $args && $scope[0];
            }
            elsif ($pp eq "endif") {
                die "unmatched #endif" if @scope < 2;
                shift @scope;
            }
            elsif ($pp eq "else") {
                $scope[0] = !$scope[0];
            }
            else {
                die "unknown directive $pp";
            }
            next;
        }

        next unless $scope[0];

        my ($flags, $type, $name, @args) = split /\s*\|\s*/;

        ($type, @args) = map s/^\s+//r =~ s/\s+$//r, ($type, @args);

        # perl volatile and nullability markers mean nothing here
        ($type, @args) = map s/\b(?:VOL|NN|NULLOK)\b\s*//gr, ($type, @args);

        @args = map parse_argument($_), @args;

        if (my $reason = BLACKLIST->{$name}) {
            warn "skipping blacklisted '$name': $reason\n";
            next;
        }

        next unless
            # public
            $flags =~ /A/ &&
            # documented
            $flags =~ /d/ &&
            # not a macro without c function
            !($flags =~ /m/ && $flags !~ /b/) &&
            # not experimental
            $flags !~ /M/ &&
            # not deprecated
            $flags !~ /D/;

        # va_list is useless in rust anyway
        next if grep $_->[0] =~ /\bva_list\b/, @args;

        my $link_name = $flags =~ /[pb]/ ? "Perl_$name" : $name;

        my $call_name = $name;
        my $pass_pthx;

        # If function has Perl_$name implementation, but no friendly $name macro.
        if ($flags =~ /p/ && $flags =~ /o/ && $flags !~ /m/) {
            $call_name = "Perl_$name";
            $pass_pthx = 1;
        }


        push @spec, {
            type => $type,
            name => $name,
            args => \@args,

            link_name => $link_name,
            call_name => $call_name,

            take_pthx => $flags !~ /n/,
            pass_pthx => $pass_pthx,
        };
    }

    return @spec;
}

1;
