extern crate gcc;

fn main() {
    gcc::compile_library("libouroboros.a", &[ "ouroboros/libouroboros.c" ]);
}
