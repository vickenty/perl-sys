# Perl XS bindings for Rust

This package provides raw low-level bindings for Perl XS API.

## Dependencies

* C compiler
* Perl 5.18 or later
* Perl packages:
  * File::Slurp
  * Ouroboros

## Building

Due to flexibility of the perl build process, bindings need to be intimately
coupled to the intended target perl version, since size of almost all types as
well as certain compile time features dramatically change the binary interface.

Once dependencies are installed, set `PERL` environment variable to point to
the target perl interpreter binary. E.g.:

    PERL=/usr/bin/perl cargo build

## Layout

This crate exports three modules:

* `types` - contains type definitions used by the XS API.

* `consts` - contains constants: `SVt_*`, `SVf_*` and some others.

* `funcs` - contains function declarations.

Also exported is `pthx!` macro which is used to handle varying function
signatures between normal and threaded Perl builds.

## SvIV et al.

Some essential endpoints in the XS API are implemented entirely as C
preprocessor macros. libouroboros provides wrappers for some of these macros,
which are exported under their original library names. libouroboros is bundled
with this crate, will be built automatically and statically linked into the
final binary.
