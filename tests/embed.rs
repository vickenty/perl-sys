#[macro_use]
extern crate perl_sys;

#[cfg(perl_useshrplib)]
mod embedded {
    use std::{ mem, ptr, ffi };
    use std::os::raw::c_int;
    use perl_sys::funcs::*;

    macro_rules! cstr {
        ($e:expr) => (ffi::CString::new($e).unwrap().as_ptr() as *mut i8)
    }

    #[link(name="perl", kind="dylib")]
    extern "C" {}

    #[test]
    fn simple() {
        let mut argc: c_int = 3;
        let mut argv: [*mut i8; 3] = [
            cstr!(""),
            cstr!("-e"),
            cstr!("0"),
        ];
        let mut argvp = argv.as_mut_ptr();

        let mut env: [*mut i8; 1] = [
            ptr::null_mut(),
        ];
        let mut envp = env.as_mut_ptr();

        let iv = unsafe {
            ouroboros_sys_init3(&mut argc, &mut argvp, &mut envp);

            let perl = perl_alloc();
            perl_construct(perl);
            perl_parse(perl, mem::transmute(0usize), 3, argvp, envp);

            perl_run(perl);

            pthx!(Perl_eval_pv(perl, cstr!("$foo = 6 * 7"), 1));
            let sv = pthx!(Perl_get_sv(perl, cstr!("foo"), 0));
            let iv = pthx!(ouroboros_sv_iv(perl, sv));

            perl_free(perl);

            iv
        };

        assert_eq!(iv, 42);
    }
}
