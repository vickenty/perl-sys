include!(concat!(env!("OUT_DIR"), "/perl_defs.rs"));

#[cfg(perl_multiplicity)]
pub fn make_context(my_perl: *mut types::PerlInterpreter) -> types::PerlContext {
    my_perl
}

#[cfg(not(perl_multiplicity))]
pub fn make_context(_my_perl: *mut types::PerlInterpreter) -> types::PerlContext {
    unsafe { std::mem::transmute(()) }
}

#[test]
fn test_svttype() {
    use consts::*;
    /* These relations are documented in perlguts */
    assert!(SVt_PVIV < SVt_PVAV);
    assert!(SVt_PVMG < SVt_PVAV);
}
