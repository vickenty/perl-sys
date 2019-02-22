package PerlSys::RustSyn;
use strict;
use warnings;

use Config;
use Exporter qw/import/;

our @EXPORT_OK = qw/
    TYPEMAP
    map_type
    indent
    mod
    type
    extern
    link_name
    _fn
    fn
    extern_fn
    callback_fn
    callback_ptr
    linked_fn
    const
    struct
    cstruct
    cstruct_pub
    struct_val
    enum
    impl
    let
    rif
/;

our %EXPORT_TAGS = (all => \@EXPORT_OK);

use constant {
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
};

sub map_type {
    my ($type) = @_;

    # working copy
    my $work = $type;
    my $mode = "mut";
    my @base_type;
    my @ptr;

    my $lim = 100;
    while ($work && --$lim > 0) {
        if ($work =~ s/^const\s*//) {
            $mode = "const";
        }
        elsif ($work =~ s/^volatile\s*//) {
        }
        elsif ($work =~ s/^(\w+)\s*//) {
            push @base_type, $1;
        }
        elsif ($work =~ s/^\*\s*//) {
            unshift @ptr, $mode;
            $mode = "mut";
        }
        else {
            die "can't parse $work (was: $type)";
        }
    }

    die "unparsable type '$type'" if !$lim;

    my $base_type = join " ", @base_type;
    my $rust_type = TYPEMAP->{$base_type}
        or die "unknown type $base_type (was: $type)";

    return join " ", map("*$_", @ptr), $rust_type;
}


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

    push @formal, $fn->{take_self} if $fn->{take_self};
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
        "pub struct $name {",
        indent(@fields_rs),
        "}"
    );
}

sub cstruct {
    my ($name, @fields) = @_;
    return (
        "#[repr(C)]",
        struct($name, @fields),
    );
}

sub cstruct_pub {
    my ($name, @fields) = @_;

    my @pub_fields;
    while (my ($name, $type) = splice @fields, 0, 2) {
        push @pub_fields, "pub $name" => $type;
    }

    return cstruct($name, @pub_fields);
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

sub impl {
    my ($name, @lines) = @_;
    return (
        "impl $name {",
        indent(@lines),
        "}"
    );
}

sub let {
    my ($name, $type, $init) = @_;

    return "let $name"
        . ($type ? ": $type" : "")
        . ($init ? " = $init" : "")
        . ";";
}

sub rif {
    my ($cond, $then, $else) = @_;

    return (
        "if $cond {",
        indent(@$then),
        "}",
        $else ? ("{", indent(@$else), "}") : (),
    );
}

1;
