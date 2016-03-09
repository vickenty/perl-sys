extern crate perl_sys;

#[cfg(perl_useshrplib)]
mod embedded {
    use std::{ mem, ptr, ffi };
    use perl_sys::funcs::*;

    macro_rules! cstr {
        ($e:expr) => (ffi::CString::new($e).unwrap().as_ptr() as *mut i8)
    }

    #[link(name="perl", kind="dylib")]
    extern "C" {}

    #[test]
    fn simple() {
        let mut argv: [*mut i8; 3] = [
            cstr!(""),
            cstr!("-e"),
            cstr!("0"),
        ];

        let iv = unsafe {
            /* FIXME: missing PERL_SYS_INIT3 calls. */
            let perl = perl_alloc();
            perl_construct(perl);
            perl_parse(perl,
                       mem::transmute(0usize),
                       3,
                       &mut argv as *mut _ as *mut *mut i8,
                       ptr::null_mut());

            perl_run(perl);

            Perl_eval_pv(perl, cstr!("$foo = 6 * 7"), 1);
            let sv = Perl_get_sv(perl, cstr!("foo"), 0);
            let iv = ouroboros_sv_iv(perl, sv);

            perl_free(perl);

            iv
        };

        assert_eq!(iv, 42);
    }
}
