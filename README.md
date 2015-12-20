# Perl XS for Rust

This package can be used to write native Perl extensions in Rust. It provides
a safe set of wrappers around native Perl macros and functions, as well as
some Rust macros to automatically generate boilerplate code.

# Teaser

```Rust
#[macro_use]
extern crate perl_xs;

XS! {
    package XSDemo (boot_XSDemo) {
        sub hello(xs) {
            xs.prepush();
            xs.push_string("Hello from Rust XS demo");
            xs.putback();
        }
    }
}
```
