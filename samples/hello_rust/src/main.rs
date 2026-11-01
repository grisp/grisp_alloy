use std::{thread, time::Duration};

fn main() {
    println!("Hello from Rust on GRiSP Alloy!");
    if std::env::args().any(|arg| arg == "--once") {
        return;
    }
    loop {
        thread::sleep(Duration::from_secs(5));
        println!("hello_rust is running");
    }
}
