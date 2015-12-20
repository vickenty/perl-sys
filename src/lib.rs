use std::mem;
use std::ffi;
use std::os::raw::{ c_void, c_char, c_int, c_long };

mod macros;

pub enum Perl {}
pub enum CV {}

#[repr(C)]
struct Stack {
	sp: *mut c_void,
	mark: *mut c_void,
	ax: c_int,
	items: c_int,
}

// Should be generated with a macro, but it is not allowed (rust-lang/rust#5668)
#[cfg(feature="perl_multiplicity")]
extern {
	fn ouroboros_stack_init(perl: *mut Perl, stack: *mut Stack);
	fn ouroboros_stack_prepush(perl: *mut Perl, stack: &mut Stack);
	fn ouroboros_stack_putback(perl: *mut Perl, stack: *mut Stack);
	fn ouroboros_stack_xpush_iv(perl: *mut Perl, stack: *mut Stack, iv: c_long);
	fn ouroboros_stack_xpush_pv(perl: *mut Perl, stack: *mut Stack, str: *const c_char, len: c_long);
	fn Perl_newXS(perl: *mut Perl, name: *const i8, xs: FunXS, file: *const c_char);
}

#[cfg(not(feature="perl_multiplicity"))]
extern {
	fn ouroboros_stack_init(stack: *mut Stack);
	fn ouroboros_stack_prepush(stack: &mut Stack);
	fn ouroboros_stack_putback(stack: *mut Stack);
	fn ouroboros_stack_xpush_iv(stack: *mut Stack, iv: c_long);
	fn ouroboros_stack_xpush_pv(stack: *mut Stack, str: *const c_char, len: c_long);
	fn Perl_newXS(name: *const i8, xs: FunXS, file: *const c_char);
}

#[cfg(feature="perl_multiplicity")]
pub type FunXS = extern "C" fn(&mut Perl, &CV);
#[cfg(feature="perl_multiplicity")]
macro_rules! call { ($name:ident, $xs:expr, $( $args:expr ),*) => { $name($xs.perl, $( $args ),*) } }

#[cfg(not(feature="perl_multiplicity"))]
pub type FunXS = extern "C" fn(&CV);
#[cfg(not(feature="perl_multiplicity"))]
macro_rules! call { ($name:ident, $xs:expr, $( $args:expr ),*) => { $name($( $args ),*) } }

pub struct XS<'a> {
	#[cfg(feature="perl_multiplicity")]
	perl: *mut Perl,
    #[allow(dead_code)]
	cv: *const CV,
	stack: Stack,
	marker: ::std::marker::PhantomData<&'a Perl>,
}

impl<'a> XS<'a> {
	#[cfg(feature="perl_multiplicity")]
	pub fn new(perl: *mut Perl, cv: *const CV) -> XS<'a> {
        let stack = unsafe {
            let mut stack = mem::uninitialized();
            ouroboros_stack_init(perl, &mut stack);
            stack
        };

        XS {
            perl: perl,
            cv: cv,
            stack: stack,
            marker: ::std::marker::PhantomData,
        }
	}

	#[cfg(not(feature="perl_multiplicity"))]
	pub fn new(cv: *const CV) -> XS<'a> {
        let stack = unsafe {
            let mut stack = mem::uninitialized();
            ouroboros_stack_init(&mut stack);
            stack
        };

        XS {
            cv: cv,
            stack: stack,
            marker: ::std::marker::PhantomData,
        }
	}

	pub fn prepush(&mut self) {
		unsafe {
			call!(ouroboros_stack_prepush, self, &mut self.stack);
		}
	}

	pub fn push_long(&mut self, val: c_long) {
		unsafe {
			call!(ouroboros_stack_xpush_iv, self, &mut self.stack, val);
		}
	}

	pub fn push_string(&mut self, string: &str) {
		let cstr = ffi::CString::new(string).unwrap();
		unsafe {
			call!(ouroboros_stack_xpush_pv, self, &mut self.stack, cstr.as_ptr(), string.len() as c_long);
		}
	}

	pub fn putback(&mut self) {
		unsafe {
			call!(ouroboros_stack_putback, self, &mut self.stack);
		}
	}

	pub fn new_xs(&mut self, name: &str, xs: FunXS, file: &'static [u8]) {
		let cname = ffi::CString::new(name).unwrap();
		unsafe {
			call!(Perl_newXS, self, cname.as_ptr(), xs, file.as_ptr() as *const c_char);
		}
	}
}
