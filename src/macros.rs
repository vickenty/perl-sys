#[macro_export]
macro_rules! xs_proc {
    ($name:ident, $xs:ident, $body:block) => {
        #[allow(dead_code)]
        #[allow(non_snake_case)]
        #[no_mangle]
        pub extern "C" fn $name(perl: $crate::raw::types::PerlContext, cv: *mut $crate::raw::types::CV) {
            let mut $xs = $crate::XS::new(perl, cv);
            $body
        }
    }
}

#[macro_export]
macro_rules! XS {
    (package $pkg:ident ($boot:ident) { $( sub $name:ident($xs:ident) $body:block)* }) => {
        $(xs_proc!($name, $xs, $body);)*

        xs_proc!(
            $boot, xs, {
            $({
                let name = [ stringify!($pkg), stringify!($name) ].join("::");
                xs.new_xs(&name, $name, b"Rust code\0");
            })*

            xs.prepush();
            xs.push_long(1);
            xs.putback();
        });
    }
}
