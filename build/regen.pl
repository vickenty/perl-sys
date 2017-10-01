use strict;
use warnings FATAL => "all";
use autodie;

use B;
use Config;

use Ouroboros;
use Ouroboros::Spec 0.11;
use Ouroboros::Library;
use File::Spec::Functions qw/catfile/;

use FindBin '$Bin';
use lib "$Bin/lib";

use PerlSys::EmbedFnc qw/:all/;
use PerlSys::IO qw/:all/;
use PerlSys::RustSyn qw/:all/;

use constant {
    PERL_NAME => "Perl",

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

    NO_CATCH => {
        "ouroboros_xcpt_try" => "captures perl croaks itself",
        "ouroboros_xcpt_rethrow" => "has to be able to die",
        "croak" => "has to be able to die",
        "croak_sv" => "has to be able to die",
        "croak_no_modify" => "has to be able to die",
    },

    # Map from names of variadic functions to names of known equivalents taking va_list.
    VARIADIC_IMPL => {
        "croak" => "vcroak",
    },
};

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

sub map_type_size {
    my ($base, $size) = @_;
    return TYPESIZEMAP->{$base}{$size} // die "$base size $size type is missing";
}

# Output blocks

sub perl_types {
    my $c = \%Config::Config;
    my $os = \%Ouroboros::SIZE_OF;

    return [
        map(enum($_), @{STUB_TYPES()}),

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

        cstruct("OuroborosStack",
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
        map(qq{#include "$_"}, Ouroboros::Library::c_header()),
        "",
        map(@{$_->{source}}, @wrappers),
        "",
        map(qq{#include "$_"}, Ouroboros::Library::c_source()),
    ];

    my $defs = [ map $_->{def}, @wrappers ];

    return ($src, $defs);
}

sub proxy_method {
    my ($fn) = @_;

    my $can_throw = !NO_CATCH->{$fn->{name}};
    my $use_retval = $can_throw && $fn->{type} ne "void";

    return () if grep $_->[0] eq "...", @{$fn->{args}};

    my $retval = "rv";
    $retval++ while grep $_->[1] eq $retval, @{$fn->{args}};

    my @actual;
    push @actual, "self.pthx" if $Config{usemultiplicity} && $fn->{take_pthx};
    push @actual, "&mut $retval" if $use_retval;
    push @actual, map $_->[1], @{$fn->{args}};

    my $proto = _fn("pub unsafe", {
        %$fn,
        take_pthx => 0,
        take_self => "&self",
    });

    my @body;
    if ($can_throw) {
        push @body, let("mut $retval", map_type($fn->{type}), "::std::mem::zeroed()")
            if $use_retval;

        push @body, let("rc", undef, do {
            local $" = ", ";
            "::fn_wrappers::$fn->{name}(@actual)"
        });

        push @body, rif("rc != 0", [
            "::panic_with_code(rc)",
        ]);

        push @body, $retval if $use_retval;
    } else {
        local $" = ", ";
        push @body, "::fn_bindings::$fn->{name}(@actual)";
    }

    return (
        "#[inline]",
        "$proto {",
        indent(@body),
        "}",
    );
}

sub perl_context {
    my ($functions) = @_;

    my $has_pthx = $Config{usemultiplicity};

    my $pthx_type = $has_pthx
        ? "*mut PerlInterpreter"
        : "()";

    my @ctor = (
        sprintf("pub fn initialize(pthx: $pthx_type) -> %s {", PERL_NAME),
        indent(
            struct_val(PERL_NAME, pthx => "pthx")),
        "}",
    );

    return (
        "#[derive(Copy, Clone, PartialEq)]",
        struct(PERL_NAME, pthx => $pthx_type),
        "",
        @ctor,
        "",
        impl(PERL_NAME,
            map(proxy_method($_), sort_by_name @$functions)),
    );
}

sub build_bindings {
    my ($type_defs, $functions, $wrapper_defs, $struct_defs) = @_;

    return (
        "/* Generated for Perl $Config::Config{version} */",
        mod("types",
            @$type_defs,
            map(cstruct_pub($_->{name}, @{$_->{fields}}), values %$struct_defs),
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
            "use super::types::*;",
            perl_consts(),
            ouro_consts(),
            mgvtbl_const($struct_defs),
        ),
        "",
        "use types::*;",
        perl_context($functions),
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
