#[rustler::nif]
fn world() -> &'static str {
    "Hello from a Rust NIF on GRiSP Alloy!"
}

rustler::init!("hello_rust_nif");
