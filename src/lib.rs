use std::mem;
use std::ffi;
use std::os::raw::{ c_char };

mod macros;

#[macro_use]
pub mod raw {
    include!(concat!(env!("OUT_DIR"), "/perl_defs.rs"));
}


use raw::types::*;

pub struct XS<'a> {
    #[cfg(perl_multiplicity)]
	perl: *mut PerlInterpreter,
    #[cfg(not(perl_multiplicity))]
    perl: (),
    #[allow(dead_code)]
	cv: *mut CV,
	stack: OuroborosStack,
	marker: ::std::marker::PhantomData<&'a PerlInterpreter>,
}

impl<'a> XS<'a> {

	#[cfg(perl_multiplicity)]
	pub fn new(perl: *mut PerlInterpreter, cv: *mut CV) -> XS<'a> {
        let stack = unsafe {
            let mut stack = mem::uninitialized();
            raw::funcs::ouroboros_stack_init(perl, &mut stack);
            stack
        };

        XS {
            perl: perl,
            cv: cv,
            stack: stack,
            marker: ::std::marker::PhantomData,
        }
	}

	#[cfg(not(perl_multiplicity))]
	pub fn new(cv: *const CV) -> XS<'a> {
        let stack = unsafe {
            let mut stack = mem::uninitialized();
            raw::funcs::ouroboros_stack_init(&mut stack);
            stack
        };

        XS {
            perl: std::ptr::null_mut(),
            cv: cv,
            stack: stack,
            marker: ::std::marker::PhantomData,
        }
	}

	pub fn prepush(&mut self) {
		unsafe {
			ouroboros_stack_prepush!(self.perl, &mut self.stack);
		}
	}

	pub fn push_long(&mut self, val: IV) {
		unsafe {
			ouroboros_stack_xpush_iv!(self.perl, &mut self.stack, val);
		}
	}

	pub fn push_string(&mut self, string: &str) {
		unsafe {
			ouroboros_stack_xpush_pv!(self.perl, &mut self.stack, string.as_ptr() as *const i8, string.len() as STRLEN);
		}
	}

	pub fn putback(&mut self) {
		unsafe {
			ouroboros_stack_putback!(self.perl, &mut self.stack);
		}
	}

	pub fn new_xs(&mut self, name: &str, xs: XSUBADDR_t, file: &'static [u8]) {
		let cname = ffi::CString::new(name).unwrap();
		unsafe {
			newXS!(self.perl, cname.as_ptr(), xs, file.as_ptr() as *const c_char);
		}
	}
}
