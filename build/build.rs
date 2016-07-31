extern crate gcc;

use std::path::{ PathBuf, Path };
use std::process::Command;

struct Perl {
    bin: String,
}

impl Perl {
    fn new() -> Perl {
        Perl {
            bin: std::env::var("PERL").unwrap_or("perl".to_owned()),
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

    fn path_core(&self) -> PathBuf {
        let archlib = self.cfg("archlibexp");
        Path::new(&archlib).join("CORE")
    }
}

fn build(perl: &Perl) {
    let mut gcc = gcc::Config::new();

    let ccflags = perl.cfg("ccflags");
    for flag in ccflags.split_whitespace() {
        gcc.flag(flag);
    }
    gcc.flag("-g");
    gcc.flag("-finline-functions");

    gcc.include(&perl.path_core());

    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR is set");
    gcc.file(Path::new(&out_dir).join("perl_sys.c"));

    gcc.compile("libperlsys.a");
}

fn main() {
    let perl = Perl::new();

    perl.run("build/regen.pl");

    build(&perl);

    if perl.cfg("usemultiplicity") == "define" {
        println!("cargo:rustc-cfg=perl_multiplicity");
    }

    if perl.cfg("useshrplib") == "true" {
        println!("cargo:rustc-cfg=perl_useshrplib");

        // Make sure ld links to libperl that matches current perl interpreter, instead of whatever
        // is libperl version exists in default linker search path. $archlibexp/CORE is hard-coded
        // installation path for default perl so this ought to be enough in most cases.
        println!("cargo:rustc-link-search=native={}", perl.path_core().to_str().unwrap());
    }
}
