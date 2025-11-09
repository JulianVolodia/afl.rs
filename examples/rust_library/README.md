# Example: Fuzzing a Rust Library

This example shows how to integrate AFL fuzzing into your Rust library project.

## Project Structure

```
example_parser_library/
├── Cargo.toml          # Package configuration with fuzzing feature
├── src/
│   └── lib.rs          # Your library code
├── fuzz/
│   └── main.rs         # Fuzzing harness
└── corpus/             # Sample inputs for fuzzing
    └── initial/
```

## Step-by-Step Integration

### 1. Add AFL to Cargo.toml

```toml
[features]
fuzzing = ["afl"]

[dependencies]
afl = { version = "0.4", optional = true }

[[bin]]
name = "fuzz_parser"
path = "fuzz/main.rs"
required-features = ["fuzzing"]
```

### 2. Create Fuzz Harness

Create `fuzz/main.rs`:

```rust
#[cfg(feature = "fuzzing")]
use afl::fuzz;
use your_library::your_function;

fn main() {
    #[cfg(feature = "fuzzing")]
    fuzz(|data: &[u8]| {
        let _ = your_function(data);
    });
}
```

### 3. Build with AFL Instrumentation

```bash
cargo afl build --release --features fuzzing
```

### 4. Create Initial Corpus

```bash
mkdir -p corpus/initial
echo "test1" > corpus/initial/test1.txt
echo "test2" > corpus/initial/test2.txt
```

### 5. Start Fuzzing

```bash
cargo afl fuzz \
    -i corpus/initial \
    -o findings \
    target/release/fuzz_parser
```

## Advanced: Multiple Fuzz Targets

For better coverage, create separate targets for each function:

### fuzz/parse_message.rs
```rust
use afl::fuzz;
use parser::parse_message;

fn main() {
    fuzz(|data: &[u8]| {
        let _ = parse_message(data);
    });
}
```

### fuzz/process_command.rs
```rust
use afl::fuzz;
use parser::process_command;

fn main() {
    fuzz(|data: &[u8]| {
        if let Ok(s) = std::str::from_utf8(data) {
            let _ = process_command(s);
        }
    });
}
```

Add to Cargo.toml:

```toml
[[bin]]
name = "fuzz_message"
path = "fuzz/parse_message.rs"
required-features = ["fuzzing"]

[[bin]]
name = "fuzz_command"
path = "fuzz/process_command.rs"
required-features = ["fuzzing"]
```

## Using the Deployment Script

The easiest way to set up fuzzing:

```bash
cd /path/to/your/rust/project
/path/to/deploy_fuzzing.sh --source .
```

This will:
- Add AFL dependency to your project
- Create fuzz harness template
- Set up corpus and output directories
- Generate helper scripts

## Continuous Fuzzing

Integrate into CI/CD (see `ci_integration` example):

```yaml
# .github/workflows/fuzz.yml
name: Continuous Fuzzing

on:
  schedule:
    - cron: '0 0 * * *'  # Daily

jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Install AFL
        run: cargo install afl
      - name: Build fuzzer
        run: cargo afl build --release --features fuzzing
      - name: Fuzz for 1 hour
        run: timeout 3600 cargo afl fuzz -i corpus -o findings target/release/fuzz_parser || true
      - name: Check for crashes
        run: |
          if [ -d findings/crashes ] && [ "$(ls -A findings/crashes)" ]; then
            echo "Crashes found!"
            exit 1
          fi
```

## Tips

1. **Start Small**: Fuzz one function at a time
2. **Good Corpus**: Use real-world inputs for better coverage
3. **Sanitizers**: Build with AddressSanitizer for better bug detection
4. **Parallel**: Run multiple fuzzer instances
5. **Monitor**: Check findings regularly

## Resources

- [AFL Documentation](http://lcamtuf.coredump.cx/afl/)
- [afl.rs GitHub](https://github.com/rust-fuzz/afl.rs)
- [Rust Fuzz Book](https://rust-fuzz.github.io/book/)
