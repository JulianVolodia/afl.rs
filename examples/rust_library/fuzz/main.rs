// Fuzz harness for the parser library
//
// This demonstrates how to integrate AFL fuzzing into your Rust library

#[cfg(feature = "fuzzing")]
use afl::fuzz;
use parser::{parse_message, process_command, parse_config};

fn main() {
    #[cfg(feature = "fuzzing")]
    {
        fuzz(|data: &[u8]| {
            // Fuzz 1: Binary message parsing
            let _ = parse_message(data);

            // Fuzz 2: Text command processing
            if let Ok(s) = std::str::from_utf8(data) {
                let _ = process_command(s);
            }

            // Fuzz 3: Config file parsing
            if let Ok(s) = std::str::from_utf8(data) {
                let _ = parse_config(s);
            }

            // You can also split fuzzing into separate targets:
            // - One target per function for better coverage
            // - Reduces complexity and improves fuzzing efficiency
        });
    }

    #[cfg(not(feature = "fuzzing"))]
    {
        eprintln!("This binary requires the 'fuzzing' feature to be enabled");
        eprintln!("Build with: cargo afl build --features fuzzing");
        std::process::exit(1);
    }
}
