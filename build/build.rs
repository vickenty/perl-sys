extern crate gcc;

use std::path::Path;
use std::process::Command;

struct Perl {
    bin: String,
}

impl Perl {
    fn new() -> Perl {
        Perl {
            bin: std::env::var("PERL").unwrap(),
        }
    }

    fn cfg(&self, key: &str) -> String {
        let out = Command::new(&self.bin)
            .arg("-MConfig")
            .arg("-e")
            .arg(format!("print $Config::Config{{{}}}", key))
            .output()
            .unwrap();

        String::from_utf8(out.stdout).unwrap()
    }

    fn run(&self, script: &str) {
        Command::new(&self.bin)
            .arg(script)
            .status()
            .unwrap();
    }
}

fn main() {
    let perl = Perl::new();

    let prefix = perl.cfg("archlibexp");
    let perl_multi = perl.cfg("usemultiplicity");

    let perl_inc = Path::new(&prefix).join("CORE");

    perl.run("build/regen.pl");

    gcc::Config::new()
        .file("ouroboros/libouroboros.c")
        .include(&perl_inc)
        .compile("libouroboros.a");

    if perl_multi == "define" {
        println!("cargo:rustc-cfg=perl_multiplicity");
    }
}
