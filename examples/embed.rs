extern crate perl_sys;

use perl_sys::fn_bindings::{
    eval_pv, ouroboros_sys_init3, ouroboros_sys_term, perl_alloc,
    perl_construct, perl_destruct, perl_free, perl_parse, perl_run,
};
use perl_sys::pthx;

pthx! {
    fn init(_perl) {}
}

#[link(name="perl")]
extern "C" {}

#[link_name="my_perl"]
pub static mut MY_PERL: *mut perl_sys::types::PerlInterpreter = std::ptr::null_mut();

fn main() {
    let mut argv = [
        b"\0"[..].as_ptr() as *mut _,
        b"-e0\0"[..].as_ptr() as *mut _,
        std::ptr::null_mut(),
    ];
    let mut argc = 2;
    let mut argv = argv.as_mut_ptr();
    let mut envp = [std::ptr::null_mut()].as_mut_ptr();

    unsafe {
        ouroboros_sys_init3(&mut argc, &mut argv, &mut envp);
        MY_PERL = perl_alloc();
        perl_construct(MY_PERL);
        perl_parse(MY_PERL, init, argc, argv, envp);
        perl_run(MY_PERL);

        pthx!(eval_pv(MY_PERL, b"print 1 + 2, chr(10) \0".as_ptr() as *const _, 1));
        
        perl_destruct(MY_PERL);
        perl_free(MY_PERL);
        ouroboros_sys_term();
    }
}
