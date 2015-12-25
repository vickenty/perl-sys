extern crate gcc;

use std::process::Command;
use std::io::{ stderr, Write };

fn main() {
    let perl = std::env::var("PERL").unwrap();

    Command::new(perl).arg("build/regen.pl").status().unwrap();

    gcc::compile_library("libouroboros.a", &[ "ouroboros/libouroboros.c" ]);
}
