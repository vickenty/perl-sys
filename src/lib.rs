include!(concat!(env!("OUT_DIR"), "/perl_sys.rs"));

#[cfg(perl_multiplicity)]
#[macro_export]
macro_rules! pthx {
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter $(, $pid : $pty )*) $body);
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident $(, $pid:ident : $pty:ty )* ) -> $rty:ty $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter $(, $pid : $pty )*) -> $rty $body);

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
