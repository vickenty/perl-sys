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
        let status = Command::new(&self.bin)
            .arg(script)
            .status()
            .unwrap();
        assert!(status.success());
    }
}

fn build_ouro(perl: &Perl) {
    let mut gcc = gcc::Config::new();

    let ccflags = perl.cfg("ccflags");
    for flag in ccflags.split_whitespace() {
        gcc.flag(flag);
    }

    let archlib = perl.cfg("archlibexp");
    let coreinc = Path::new(&archlib).join("CORE");
    gcc.include(&coreinc);

    gcc.file("ouroboros/libouroboros.c");
    gcc.compile("libouroboros.a");
}

fn main() {
    let perl = Perl::new();

    build_ouro(&perl);

    perl.run("build/regen.pl");

    if perl.cfg("usemultiplicity") == "define" {
        println!("cargo:rustc-cfg=perl_multiplicity");
    }
}
