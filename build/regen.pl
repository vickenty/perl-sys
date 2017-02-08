use strict;
use warnings FATAL => "all";
use autodie;

use B;
use Config;
use Config::Perl::V;

use Ouroboros;
use Ouroboros::Spec 0.11;
use Ouroboros::Library;
use File::Spec::Functions qw/catfile/;

require "build/lib/version.pl" or die;

use constant {
    EMBED_FNC_PATH => "build/embed.fnc",
    OUT_DIR => $ENV{OUT_DIR} // ".",

    PTHX_TYPE => "PerlThreadContext",

    STRUCT_MAP => {
        magic => "MAGIC",
        mgvtbl => "MGVTBL",
    },

    STUB_TYPES => [
        "PerlInterpreter",
        "PerlIO",
        "SV",
        "AV",
        "HV",
        "HE",
        "GV",
        "CV",
        "OP",
        "IO",
        "BHK",
        "PERL_CONTEXT",
        "PADLIST",
        "PADNAME",
        "PADNAMELIST",
        "HEK",
        "UNOP_AUX_item",
        "LOOP",
        "CLONE_PARAMS",
    ],

    TYPEMAP => {
        "ouroboros_stack_t" => "OuroborosStack",
        "ouroboros_xcpt_callback_t" => "extern fn(*mut ::std::os::raw::c_void)",

        "void" => "::std::os::raw::c_void",
        "int" => "::std::os::raw::c_int",
        "unsigned" => "::std::os::raw::c_uint",
        "unsigned int" => "::std::os::raw::c_uint",
        "char" => "::std::os::raw::c_char",
        "unsigned char" => "::std::os::raw::c_uchar",

        "bool" => "c_bool",
        "size_t" => "Size_t",

        "MAGIC" => "MAGIC",
        "MGVTBL" => "MGVTBL",
    },

    TYPESIZEMAP => {
        IV => {
            1 => "i8",
            2 => "i16",
            4 => "i32",
            8 => "i64",
        },
        UV => {
            1 => "u8",
            2 => "u16",
            4 => "u32",
            8 => "u64",
        },
        NV => {
            4 => "f32",
            8 => "f64",
        },
    },

    BLACKLIST => {
        "sv_nolocking" => "listed as part of public api, but not actually defined",
    },

    NO_CATCH => {
        "ouroboros_xcpt_try" => "captures perl croaks itself",
        "ouroboros_xcpt_rethrow" => "has to be able to die",
        "croak" => "has to be able to die",
    },

    # Map from names of variadic functions to names of known equivalents taking va_list.
    VARIADIC_IMPL => {
        "croak" => "vcroak",
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

sub read_ouro_spec {
    my $spec = \%Ouroboros::Spec::SPEC;

    my @fns;
    foreach my $fn (@{$spec->{fn}}) {
        my $name = "arg0";
        my @args = map [ $_,  $name++ ], @{$fn->{params}};

        push @fns, {
            type => $fn->{type},
            name => $fn->{name},
            args => \@args,

            link_name => $fn->{name},
            call_name => $fn->{name},

            take_pthx => !$fn->{tags}{no_pthx},
            pass_pthx => !$fn->{tags}{no_pthx},
        };
    }

    return @fns;
}

sub parse_header {
    my ($header, $names) = @_;
    my $src = join "", read_file(catfile($Config{archlibexp}, "CORE", $header));

    $src =~ s#/\*.*?\*/##g;
    $src =~ s/\s+$//g;

    my %defs;
    while ($src =~ /struct\s+(?<name>\w+)\s*{(?<source>[^\}]+)}/g) {
        my $name = $names->{$+{name}} // next;
        $defs{$name} = {
            name => $name,
            source => $+{source},
        };
    }

    foreach my $def (values %defs) {
        my @fields;
        foreach my $field (split /;/, $def->{source}) {
            if ($field =~ /^(?<type>[^\(]+)\(\*(?<name>\w+)\)\s*\((?<pthx>pTHX_\s+)?(?<args>[^)]+)\)$/) {
                my $type = strip($+{type});
                my $name = strip($+{name});
                my $pthx = defined $+{pthx};
                my $args = strip($+{args});

                push @fields, $name => callback_ptr($type, $pthx, map parse_argument($_), split /,/, $args),
            }
            else {
                my ($type, $name) = @{parse_argument($field)};
                push @fields, $name => map_type($type);
            }
        }

        $def->{fields} = \@fields;
    }

    return %defs;
}

sub read_struct_defs {
    my %defs = parse_header("mg.h", STRUCT_MAP);
    return \%defs;
}

# Getters

sub map_type {
    my ($type) = @_;

    # working copy
    my $work = $type;

    # canonicalize const placement, "const int" is the same as "int const"
    $work =~ s/const\s+(\w+)/$1 const/;

    (my $base_type, $work) = $work =~ /^((?:unsigned )?\w+)\s*(.*)/
        or die "unparsable type '$type'";

    my $rust_type = TYPEMAP->{$base_type}
        or die "unknown type $base_type (was: $type)";

    my $lim = 100;
    while ($work && --$lim > 0) {
        my $mode = "mut";
        if ($work =~ s/^const\s*//) {
            $mode = "const";
        }
        if ($work =~ s/^\*\s*//) {
            $rust_type = "*$mode $rust_type";
        }
    }
    die "unparsable type '$type'" if !$lim;

    return $rust_type;
}

sub map_type_size {
    my ($base, $size) = @_;
    return TYPESIZEMAP->{$base}{$size} // die "$base size $size type is missing";
}

# Rust syntax

sub indent {
    map "    $_", @_;
}

sub mod {
    my ($name, @items) = @_;
    return (
        "pub mod $name {",
        indent(@items),
        "}",
    );
}

sub type {
    my ($name, $ty) = @_;

    TYPEMAP->{$name} = $name;

    return "pub type $name = $ty;";
}

sub extern {
    my ($abi, @items) = @_;
    return (
        "extern \"$abi\" {",
        indent(@items),
        "}",
    );
}

sub link_name {
    my ($name) = @_;
    return (qq!#[link_name="$name"]!);
}

sub _fn {
    my ($qual, $fn) = @_;

    my @formal;

    push @formal, "my_perl: *mut PerlInterpreter" if $fn->{take_pthx} && $Config{usemultiplicity};

    foreach my $arg (@{$fn->{args}}) {
        my ($type, $name) = @$arg;
        if ($type eq "...") {
            push @formal, "...";
        }
        else {
            my $rs_type = map_type($type);
            push @formal, $name ? "$name: $rs_type" : $rs_type;
        }
    }

    my $returns = $fn->{type} eq "void" ? "" : " -> " . map_type($fn->{type});

    local $" = ", ";

    return "$qual fn $fn->{name}(@formal)$returns";
}

sub fn {
    return _fn("pub", @_) . ";";
}

sub extern_fn {
    my ($type, @args) = @_;

    return _fn('extern "C"', {
        type => $type,
        name => "",
        args => [ map [ $_ ], @args ],
        take_pthx => 1,
    });
}

sub callback_fn {
    my ($type, $pthx, @args) = @_;

    return _fn('extern "C"', {
        type => $type,
        name => "",
        args => \@args,
        take_pthx => $pthx,
    });
}

sub callback_ptr {
    my ($type, $pthx, @args) = @_;
    return sprintf "Option<%s>", callback_fn($type, $pthx, @args);
}

sub linked_fn {
    my ($fn) = @_;

    return (
        link_name($fn->{link_name}),
        fn($fn),
    );
}

sub const {
    my ($name, $type, $head, @rest) = @_;

    my @lines = (
        "pub const $name: $type = $head",
        @rest,
    );

    $lines[-1] .= ";";

    return @lines;
}

sub struct {
    my ($name, @fields) = @_;

    TYPEMAP->{$name} = $name;

    my @fields_rs;
    while (my ($name, $type) = splice @fields, 0, 2) {
        push @fields_rs, sprintf "%s: %s,", $name, $type;
    }

    return (
        "#[repr(C)]",
        "pub struct $name {",
        indent(@fields_rs),
        "}"
    );
}

sub struct_pub {
    my ($name, @fields) = @_;

    my @pub_fields;
    while (my ($name, $type) = splice @fields, 0, 2) {
        push @pub_fields, "pub $name" => $type;
    }

    return struct($name, @pub_fields);
}

sub struct_val {
    my ($type, @fields) = @_;

    my @init;
    while (my ($name, $value) = splice @fields, 0, 2) {
        push @init, "$name: $value,";
    }

    return "$type {", indent(@init), "}";
}

sub enum {
    my ($name, @items) = @_;
    die "non-empty enums are not supported yet" if @items;

    TYPEMAP->{$name} = $name;

    return "pub enum $name {}";
}


# Output blocks

sub perl_types {
    my $c = \%Config::Config;
    my $os = \%Ouroboros::SIZE_OF;

    my $pthx = $c->{usemultiplicity}
        ? type(PTHX_TYPE, "*mut PerlInterpreter")
        : type(PTHX_TYPE, "()");

    return [
        map(enum($_), @{STUB_TYPES()}),

        $pthx,

        type("IV", map_type_size("IV", $c->{ivsize})),
        type("UV", map_type_size("UV", $c->{uvsize})),
        type("NV", map_type_size("NV", $c->{nvsize})),

        type("I8", map_type_size("IV", $c->{i8size})),
        type("U8", map_type_size("UV", $c->{u8size})),
        type("I16", map_type_size("IV", $c->{i16size})),
        type("U16", map_type_size("UV", $c->{u16size})),
        type("I32", map_type_size("IV", $c->{i32size})),
        type("U32", map_type_size("UV", $c->{u32size})),

        # assumes that these three types have the same size
        type("Size_t", map_type_size("UV", $c->{sizesize})),
        type("SSize_t", map_type_size("IV", $c->{sizesize})),
        type("STRLEN", map_type_size("UV", $c->{sizesize})),

        type("c_bool", map_type_size("UV", $os->{bool})),
        type("svtype", map_type_size("UV", $os->{svtype})),
        type("PADOFFSET", map_type_size("UV", $os->{PADOFFSET})),
        type("Optype", map_type_size("UV", $os->{Optype})),

        type("XSINIT_t", extern_fn("void")),
        type("SVCOMPARE_t", extern_fn("I32", "SV*", "SV*")),
        type("XSUBADDR_t", extern_fn("void", "CV*")),
        type("Perl_call_checker", extern_fn("OP*", "OP*", "GV*", "SV*")),
        type("Perl_check_t", extern_fn("OP*", "OP*")),

        struct("OuroborosStack",
            _data => sprintf("[u8; %d]", $os->{"ouroboros_stack_t"}),
            _align => "[*const u8; 0]"),
    ];
}

sub sort_by_name {
    sort { $a->{name} cmp $b->{name} } @_
}

sub link_funcs {
    my ($functions) = @_;
    return extern("C",
        map(linked_fn($_), sort_by_name @$functions));
}

sub wrap_funcs {
    my ($wrapper_defs) = @_;
    return extern("C",
        map(linked_fn($_), sort_by_name @$wrapper_defs));
}

sub perl_consts {
    map(const($_, "U32", B->can($_)->()), grep /^SV(?!t_)/ || /^G_/, @B::EXPORT_OK);
}

sub ouro_consts {
    my %defined = map { $_, 1 } @Ouroboros::CONSTS;

    map(const($_->{name}, $_->{c_type}, Ouroboros->can($_->{name})->()),
        @{$Ouroboros::Spec::SPEC{enum}},
        grep($defined{$_->{name}}, @{$Ouroboros::Spec::SPEC{const}}));
}

sub xcpt_wrapper {
    my ($fn) = @_;

    if (my $reason = BLACKLIST->{$fn->{name}}) {
        warn "skipping blacklisted '$fn->{name}': $reason\n";
        return ();
    }

    my $impl = $fn->{call_name};

    my (@args, @formal);
    my (@va_list, @va_start, @va_end);
    foreach my $arg (@{$fn->{args}}) {
        my ($type, $name) = @$arg;

        push @formal, $arg;

        if ($type eq "...") {
            $impl = VARIADIC_IMPL->{$fn->{name}};

            if (!$impl) {
                warn "skipping variadic function '$fn->{name}': va_list equivalent is not known";
                return ();
            }

            my $va_name = "ap";
            $va_name++ while (grep $_ eq $va_name, @args);

            @va_list = "va_list $va_name;";
            @va_start = "va_start($va_name, $args[-1]);";
            @va_end = "va_end($va_name);";

            push @args, "&$va_name";
        }
        else {
            push @args, $name;
        }
    }

    my $store = "";
    if ($fn->{type} ne "void") {
        unshift @formal, [ "$fn->{type}*",  "RETVAL" ];
        $store = "*RETVAL = ";
    }

    my $wrapper_name = "perl_sys_$fn->{name}";

    my @pthx;
    if ($fn->{take_pthx} && $Config{usemultiplicity}) {
        @pthx = ("pTHX");
    }

    if ($fn->{pass_pthx} && $Config{usemultiplicity}) {
        unshift @args, "aTHX";
    }

    my (@jmpenv_push, @jmpenv_pop);
    if ($fn->{take_pthx} && !NO_CATCH->{$fn->{name}}) {
        @jmpenv_push = (
            "dJMPENV;",
            "JMPENV_PUSH(rc);",
        );
        @jmpenv_pop = (
            "JMPENV_POP;",
        );
    }

    local $" = ", ";

    my $formal = join ", ", @pthx, map join(" ", @$_), @formal;

    return {
        source => [
            "int $wrapper_name($formal) {",
            indent(
                "int rc = 0;",
                @va_list,
                @va_start,
                @jmpenv_push,
                "if (rc == 0) { $store$impl(@args); }",
                @jmpenv_pop,
                @va_end,
                "return rc;",
            ),
            "}",
        ],
        def => {
            %$fn,
            type => "int",
            args => \@formal,
            link_name => $wrapper_name,
        },
    };
}

sub build_wrappers {
    my ($functions) = @_;
    my @wrappers = map(xcpt_wrapper($_), @$functions);

    my $src = [
        "/* Generated for Perl $Config::Config{version} */",
        q{#define PERL_NO_GET_CONTEXT},
        q{#include "EXTERN.h"},
        q{#include "perl.h"},
        q{#include "XSUB.h"},
        q{#define OUROBOROS_STATIC static},
        map(qq{#include "$_"}, Ouroboros::Library::c_header()),
        "",
        map(@{$_->{source}}, @wrappers),
        "",
        map(qq{#include "$_"}, Ouroboros::Library::c_source()),
    ];

    my $defs = [ map $_->{def}, @wrappers ];

    return ($src, $defs);
}

sub build_bindings {
    my ($type_defs, $functions, $wrapper_defs, $struct_defs) = @_;

    return (
        "/* Generated for Perl $Config::Config{version} */",
        mod("types",
            "#![allow(non_camel_case_types)]",
            @$type_defs,
            map(struct_pub($_->{name}, @{$_->{fields}}), values %$struct_defs),
        ),
        "",
        "#[macro_use]",
        mod("fn_bindings",
            "use super::types::*;",
            link_funcs($functions)),
        "",
        mod("fn_wrappers",
            "use super::types::*;",
            wrap_funcs($wrapper_defs)),
        "",
        mod("consts",
            "#![allow(non_upper_case_globals)]",
            "use super::types::*;",
            perl_consts(),
            ouro_consts(),
            mgvtbl_const($struct_defs),
        ),
    );
}

sub mgvtbl_const {
    my ($defs) = @_;

    my $def = $defs->{MGVTBL} // return ();

    my @fields = @{$def->{fields}};

    my @init;
    while (my ($name, $type) = splice @fields, 0, 2) {
        push @init, $name, "None";
    }

    return const("EMPTY_MGVTBL", "MGVTBL", struct_val("MGVTBL", @init));
}

#

sub strip {
    shift =~ s/^\s+//r =~ s/\s+$//r;
}

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

#

my $functions = [
    read_embed_fnc(),
    read_ouro_spec(),
];

my $types = perl_types();

my $struct_defs = read_struct_defs();

my ($wrapper_src, $wrapper_defs) = build_wrappers($functions);

write_file("perl_sys.c", @$wrapper_src);
write_file("perl_sys.rs",
    build_bindings($types, $functions, $wrapper_defs, $struct_defs));
