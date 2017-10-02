[![Build Status](https://travis-ci.org/vickenty/perl-sys.svg?branch=master)](https://travis-ci.org/vickenty/perl-sys)

# Perl XS bindings for Rust

This crate provides raw low-level bindings for Perl XS API.

## Dependencies

* C compiler
* Perl 5.18 or later
* Perl packages:
  * Ouroboros

## Build

Bindings are generated during build process for a specific version of the perl
interpreter. By default, the version found in the system path is used (e.g.
`/usr/bin/perl`). It can be overridden by specifying path to the perl binary
via `PERL` environment variable

    $ PERL=/opt/bin/custom-perl cargo build

## Contents

Only types that are used by XS functions and macros are exported. Most of the
types come as either type aliases to primitive types, or opaque structs.

Small amount of auto-generated C glue is included to deal with XS functions
that are only defined as macros (e.g. `SvIV`, `SvRV`, etc), and exceptions
(they rely on `longjmp` C function, which is not available in Rust yet).
