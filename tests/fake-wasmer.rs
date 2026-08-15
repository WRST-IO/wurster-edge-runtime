use std::{env, fs, path::Path};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.get(1).map(String::as_str) == Some("--version") {
        println!("wasmer 7.2.1");
        println!("features: napi_v10 napi_extension_wasmer_v0");
        return;
    }

    let log = env::var("FAKE_WASMER_LOG").expect("FAKE_WASMER_LOG is required");
    fs::write(Path::new(&log), args.iter().skip(1).cloned().collect::<Vec<_>>().join("\n"))
        .expect("failed to write argv log");
    if env::var("FAKE_WASMER_MODE").as_deref() == Ok("fallback") {
        std::process::exit(97);
    }
}
