include!(concat!(env!("OUT_DIR"), "/perl_defs.rs"));

#[test]
fn test_svttype() {
    use consts::*;
    /* These relations are documented in perlguts */
    assert!(consts::SVt_PVIV < SVt_PVAV);
    assert!(consts::SVt_PVMG < SVt_PVAV);
}
