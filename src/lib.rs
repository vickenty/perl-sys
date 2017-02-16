//! Low-level bindings for Perl XS API.
//!
//! This can be used to create Perl extensions, and to write programs that embed the perl
//! interpreter.
//!
//! Contents of this crate is automatically generated at build time to match specific Perl version
//! installed in the system. Expect type definitions, constants, available functions and their
//! signatures to change between different perl interpreters.
//!
//! API bindings are organized in layers:
//!
//!  - `fn_bindings` module provides raw prototypes for perl functions;
//!  - `fn_wrappers` module provides wrappers around the API to help with exception handling;
//!  - `Perl` type encapsulates exception handling and optional context pointer present in some
//!    builds of perl.

#![allow(non_snake_case)]
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]

use std::mem;
use std::panic;
use std::any::Any;
use std::os::raw::c_int;

include!(concat!(env!("OUT_DIR"), "/perl_sys.rs"));

struct Carrier(c_int);

fn panic_with_code(code: c_int) -> ! {
    panic::resume_unwind(Box::new(Carrier(code)))
}

/// Resume a perl exception.
///
/// This function should be used in pair with `catch_unwind()` for functions that are called by the
/// interpreter (xsubs, opcode checkers and such) to prevent panics from unwinding through the C
/// code.
///
/// If `err` contains a perl exception caught by one of the wrappers, pass control to perl to resume
/// handling of this exception. In this case this function never returns. This interrupts normal
/// control flow expected by the language and prevents destructors for rust values on stack from
/// running.
///
/// If `err` is any other value, it is returned unmodified.
pub unsafe fn try_rethrow(perl: Perl, err: Box<Any>) -> Box<Any> {
    if let Some(&Carrier(code)) = err.downcast_ref() {
        mem::drop(err);
        perl.ouroboros_xcpt_rethrow(code);
        unreachable!();
    }
    err
}

/// Macro to handle the implicit context parameter.
///
/// See [documentation](http://perldoc.perl.org/perlguts.html#Background-and-PERL_IMPLICIT_CONTEXT)
/// for more information about the implicit context. This macro implements equivalent of `pTHX` and
/// `aTHX` macros in C.
///
/// # Defining functions
///
/// Fist two forms are used to define functions:
///
/// ```ignore
/// pthx! {
///     fn foo(my_perl, arg: IV) -> IV {
///         let my_perl = perl_sys::initialize(my_perl);
///         // ...
///     }
/// }
/// ```
///
/// Under perls without implicit context, `foo` will take one parameter and `my_perl` will have unit
/// type and value (unlike C, the context variable is always present). Under perls with implicit
/// context, `foo` will take two parameters and `my_perl` will be an actual pointer.
///
/// # Calling functions
///
/// Last form of this macro is for calling functions that take implicit context parameter:
///
/// ```ignore
/// pthx!(foo(my_perl, arg));
/// ```
///
/// This simply removes first parameter under perls without implicit context.
#[cfg(perl_multiplicity)]
#[macro_export]
macro_rules! pthx {
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) -> $rty:ty $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter $(, $pid : $pty )*) -> $rty $body);
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter $(, $pid : $pty )*) $body);

    ($id:ident ( $ctx:expr $(, $p:expr )* $(,)* )) => ($id($ctx $(, $p )*));
}

#[cfg(not(perl_multiplicity))]
#[macro_export]
macro_rules! pthx {
    ($(#[$me:meta])* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) -> $rty:ty $body:block) => ($(#[$me])* pub extern "C" fn $id ($( $pid : $pty ),*) -> $rty { let $ctx = (); $body });
    ($(#[$me:meta])* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) $body:block) => ($(#[$me])* pub extern "C" fn $id ($( $pid : $pty ),*) { let $ctx = (); $body });

    ($id:ident ( $ctx:expr $(, $p:expr ),* $(,)* )) => ($id($( $p ),*));
}

#[test]
fn test_svttype() {
    use consts::*;
    /* These relations are documented in perlguts */
    assert!(SVt_PVIV < SVt_PVAV);
    assert!(SVt_PVMG < SVt_PVAV);
}

#[test]
fn test_alignment() {
    use std::mem::align_of;
    assert_eq!(align_of::<*mut u8>(), align_of::<types::OuroborosStack>());
}
