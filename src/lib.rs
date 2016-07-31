include!(concat!(env!("OUT_DIR"), "/perl_sys.rs"));

#[cfg(perl_multiplicity)]
#[macro_export]
macro_rules! pthx {
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident ) $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter) $body);
    ($( #[$me:meta] )* fn $id:ident ( $ctx:ident, $( $pid:ident : $pty:ty ),* ) $body:block) => ($( #[$me] )* pub extern "C" fn $id ($ctx: *mut $crate::types::PerlInterpreter, $( $pid : $pty ),*) $body);

    ($id:ident ( $ctx:expr )) => ($id($ctx));
    ($id:ident ( $ctx:expr, $( $p:expr ),* $(,)* )) => ($id($ctx, $( $p ),*));
}

#[cfg(not(perl_multiplicity))]
#[macro_export]
macro_rules! pthx {
    ($(#[$me:meta])* fn $id:ident ( $ctx:ident ) $body:block) => ($(#[$me])* pub extern "C" fn $id () { let $ctx = (); $body });
    ($(#[$me:meta])* fn $id:ident ( $ctx:ident, $( $pid:ident : $pty:ty ),* ) $body:block) => ($(#[$me])* pub extern "C" fn $id ($( $pid : $pty ),*) { let $ctx = (); $body });

    ($id:ident ( $ctx:expr )) => ($id());
    ($id:ident ( $ctx:expr, $( $p:expr ),* $(,)* )) => ($id($( $p ),*));
}

#[test]
fn test_svttype() {
    use consts::*;
    /* These relations are documented in perlguts */
    assert!(SVt_PVIV < SVt_PVAV);
    assert!(SVt_PVMG < SVt_PVAV);
}
