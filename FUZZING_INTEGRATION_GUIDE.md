# Complete AFL Fuzzing Integration Guide

**A comprehensive, hands-on guide to integrating AFL fuzzing into your Rust, C/C++, or binary projects.**

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Integration Methods](#integration-methods)
3. [Rust Projects](#rust-projects)
4. [Binary Fuzzing](#binary-fuzzing)
5. [CI/CD Integration](#cicd-integration)
6. [Monitoring & Analysis](#monitoring--analysis)
7. [Real-World Examples](#real-world-examples)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Automated Setup (Recommended)

The easiest way to get started:

```bash
# Make script executable
chmod +x deploy_fuzzing.sh

# Interactive mode
./deploy_fuzzing.sh

# Or specify directly
./deploy_fuzzing.sh --source /path/to/rust/project
./deploy_fuzzing.sh --binary /path/to/executable
```

This handles everything: dependencies, corpus creation, build configuration, and helper scripts.

### Manual Setup

If you prefer manual control:

```bash
# 1. Install AFL
cargo install afl

# 2. Create project
cargo new fuzz_target --bin
cd fuzz_target

# 3. Add AFL dependency
cat >> Cargo.toml << 'EOF'
[dependencies]
afl = "0.4"
EOF

# 4. Write fuzz harness (src/main.rs)
cat > src/main.rs << 'EOF'
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Your fuzzing logic here
    });
}
EOF

# 5. Build
cargo afl build --release

# 6. Create corpus
mkdir -p corpus/initial
echo "test" > corpus/initial/test.txt

# 7. Fuzz!
cargo afl fuzz -i corpus/initial -o findings target/release/fuzz_target
```

---

## Integration Methods

### Method 1: Source Code Integration (Best)

**When to use:**
- You have source code
- Want maximum coverage
- Need best performance

**Pros:**
- Coverage-guided fuzzing
- Fast execution (1000+ exec/s)
- Detailed crash information

**Cons:**
- Requires compilation
- Needs code modification

### Method 2: Binary Fuzzing (Convenient)

**When to use:**
- No source code available
- Third-party binaries
- Quick testing

**Pros:**
- No source needed
- Quick setup
- Works with any binary

**Cons:**
- Much slower (10-100x)
- Less effective
- Limited feedback

### Method 3: Library Fuzzing (Targeted)

**When to use:**
- Testing specific functions
- Library development
- Focused security testing

**Pros:**
- Targeted testing
- Better coverage of specific code
- Easier crash reproduction

**Cons:**
- Requires wrapper code
- May miss integration bugs

---

## Rust Projects

### Step-by-Step Integration

#### 1. Add AFL Dependency

Edit `Cargo.toml`:

```toml
[features]
default = []
fuzzing = ["afl"]

[dependencies]
afl = { version = "0.4", optional = true }

[[bin]]
name = "fuzz_target"
path = "fuzz/main.rs"
required-features = ["fuzzing"]
```

#### 2. Create Fuzz Harness

Create `fuzz/main.rs`:

```rust
#[cfg(feature = "fuzzing")]
use afl::fuzz;

// Import your library
use your_library::*;

fn main() {
    #[cfg(feature = "fuzzing")]
    fuzz(|data: &[u8]| {
        // Fuzz your functions
        let _ = parse_data(data);

        // Convert to string if needed
        if let Ok(s) = std::str::from_utf8(data) {
            let _ = process_text(s);
        }

        // Test structured input
        if data.len() >= 4 {
            let value = u32::from_le_bytes([
                data[0], data[1], data[2], data[3]
            ]);
            let _ = process_number(value);
        }
    });
}
```

#### 3. Build and Run

```bash
# Build with instrumentation
cargo afl build --release --features fuzzing

# Prepare corpus
mkdir -p corpus/initial
cp /path/to/samples/* corpus/initial/

# Start fuzzing
cargo afl fuzz \
    -i corpus/initial \
    -o findings \
    target/release/fuzz_target
```

### Multiple Fuzz Targets

For complex projects, create multiple focused targets:

```
fuzz/
├── main.rs          # General fuzzing
├── parse_json.rs    # JSON parser only
├── parse_binary.rs  # Binary format only
└── api_calls.rs     # API fuzzing
```

Update `Cargo.toml`:

```toml
[[bin]]
name = "fuzz_json"
path = "fuzz/parse_json.rs"
required-features = ["fuzzing"]

[[bin]]
name = "fuzz_binary"
path = "fuzz/parse_binary.rs"
required-features = ["fuzzing"]
```

Build all:

```bash
cargo afl build --release --features fuzzing --bins
```

### Fuzzing with Sanitizers

#### AddressSanitizer (ASan)

Detect memory corruption:

```bash
# Build with ASan
export RUSTFLAGS="-Z sanitizer=address"
export ASAN_OPTIONS="detect_odr_violation=0:abort_on_error=1"
cargo afl build --target x86_64-unknown-linux-gnu --features fuzzing

# Fuzz
cargo afl fuzz -i corpus -o findings target/x86_64-unknown-linux-gnu/debug/fuzz_target
```

#### UndefinedBehaviorSanitizer (UBSan)

Detect undefined behavior:

```bash
export RUSTFLAGS="-Z sanitizer=undefined"
cargo afl build --target x86_64-unknown-linux-gnu --features fuzzing
```

---

## Binary Fuzzing

### Using the Binary Wrapper Script

```bash
# Automated setup
./examples/binary_wrapper/fuzz_binary.sh /path/to/binary

# This creates:
# - wrapper_binary.sh (input adapter)
# - run_fuzz_binary.sh (fuzzing script)
# - corpus/ (sample inputs)
```

### Manual Binary Fuzzing

#### Step 1: Create Wrapper

Determine how the binary accepts input:

**Option A: stdin**
```bash
cat > wrapper.sh << 'EOF'
#!/bin/bash
cat "$1" | /path/to/binary 2>&1
EOF
chmod +x wrapper.sh
```

**Option B: File argument**
```bash
cat > wrapper.sh << 'EOF'
#!/bin/bash
/path/to/binary "$1" 2>&1
EOF
chmod +x wrapper.sh
```

**Option C: Command-line args**
```bash
cat > wrapper.sh << 'EOF'
#!/bin/bash
/path/to/binary "$(cat "$1")" 2>&1
EOF
chmod +x wrapper.sh
```

#### Step 2: Prepare Corpus

```bash
mkdir -p corpus
# Add sample files that the binary can process
cp sample1.dat corpus/
cp sample2.dat corpus/
```

#### Step 3: Fuzz

**For instrumented binaries:**
```bash
afl-fuzz -i corpus -o findings ./wrapper.sh @@
```

**For black-box fuzzing:**
```bash
afl-fuzz -i corpus -o findings -n ./wrapper.sh @@
```

### Fuzzing System Binaries (macOS)

#### Example: Fuzzing `file` command

```bash
# Create wrapper
cat > fuzz_file.sh << 'EOF'
#!/bin/bash
file "$1" 2>&1 | head -1
EOF
chmod +x fuzz_file.sh

# Corpus
mkdir -p corpus
cp ~/Pictures/*.{jpg,png} corpus/
cp ~/Documents/*.{pdf,txt} corpus/

# Fuzz
afl-fuzz -i corpus -o findings -n ./fuzz_file.sh @@
```

#### Example: Fuzzing image tools

```bash
# sips (image processing)
cat > fuzz_sips.sh << 'EOF'
#!/bin/bash
OUTPUT="/tmp/sips_out.jpg"
/usr/bin/sips -s format jpeg "$1" --out "$OUTPUT" 2>&1
rm -f "$OUTPUT"
EOF

afl-fuzz -i corpus/images -o findings -n ./fuzz_sips.sh @@
```

---

## CI/CD Integration

### GitHub Actions

Copy `.github/workflows/fuzz.yml`:

```yaml
name: Fuzzing

on:
  pull_request:
  schedule:
    - cron: '0 2 * * *'

jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install AFL
        run: cargo install afl
      - name: Build
        run: cargo afl build --release --features fuzzing
      - name: Quick Fuzz
        run: timeout 300 cargo afl fuzz -i corpus -o findings target/release/fuzz_target || true
      - name: Check Crashes
        run: |
          if find findings/crashes -type f ! -name 'README.txt' | grep -q .; then
            echo "Crashes found!"
            exit 1
          fi
```

See `examples/ci_integration/` for complete examples.

### GitLab CI

Copy `.gitlab-ci.yml` from examples:

```yaml
fuzz:
  stage: test
  script:
    - cargo install afl
    - cargo afl build --release --features fuzzing
    - timeout 3600 cargo afl fuzz -i corpus -o findings target/release/fuzz_target || true
  artifacts:
    paths:
      - findings/
```

### Continuous Fuzzing Strategy

1. **PR Checks (5 minutes):**
   - Quick smoke test
   - Catches obvious bugs
   - Fails build if crashes found

2. **Nightly Builds (1 hour):**
   - Deeper testing
   - Creates issues for crashes
   - Updates corpus

3. **Weekly Deep Fuzz (8+ hours):**
   - Comprehensive testing
   - Multiple targets
   - Performance analysis

---

## Monitoring & Analysis

### Real-Time Monitoring

Use the advanced monitor:

```bash
# Start monitoring
./monitor_fuzzing.sh findings/ 5

# Shows:
# - Fuzzer status and speed
# - Coverage statistics
# - Crashes and hangs
# - Performance metrics
# - Tips and recommendations
```

### Manual Monitoring

```bash
# Watch stats
watch -n 1 'cat findings/fuzzer_stats'

# Count crashes
find findings/crashes -type f ! -name "README.txt" | wc -l

# View recent crashes
ls -lat findings/crashes/ | head -10

# Check fuzzer status
tail -f findings/plot_data
```

### Analyzing Crashes

#### Reproduce Crash

```bash
# Simple reproduction
cat findings/crashes/id:000000,sig:11,... | ./target/release/fuzz_target

# With debugger
lldb ./target/release/fuzz_target
(lldb) run < findings/crashes/id:000000,sig:11,...
(lldb) bt  # backtrace
```

#### Minimize Crash

```bash
# Minimize input size
cargo afl tmin \
    -i findings/crashes/id:000000,sig:11,... \
    -o minimized_crash.bin \
    ./target/release/fuzz_target

# Verify minimized crash still triggers bug
cat minimized_crash.bin | ./target/release/fuzz_target
```

#### Crash Triage

```bash
# Group unique crashes
for crash in findings/crashes/id:*; do
    echo "Testing: $(basename $crash)"
    cat "$crash" | ./target/release/fuzz_target 2>&1 | head -5
    echo "---"
done
```

### Corpus Management

#### Minimize Corpus

```bash
# Remove redundant inputs
cargo afl cmin \
    -i corpus/initial \
    -o corpus/minimized \
    ./target/release/fuzz_target

# Use minimized corpus for faster fuzzing
cargo afl fuzz -i corpus/minimized -o findings ./target/release/fuzz_target
```

#### Merge Corpus from Multiple Fuzzers

```bash
# Merge findings from parallel fuzzing
mkdir -p corpus/merged

# Copy unique inputs from all fuzzers
for fuzzer in findings/fuzzer*; do
    cp "$fuzzer/queue/"* corpus/merged/ 2>/dev/null || true
done

# Minimize merged corpus
cargo afl cmin -i corpus/merged -o corpus/final ./target/release/fuzz_target
```

---

## Real-World Examples

### Example 1: JSON Parser

```rust
// fuzz/json_parser.rs
use afl::fuzz;
use serde_json::Value;

fn main() {
    fuzz(|data: &[u8]| {
        if let Ok(s) = std::str::from_utf8(data) {
            // Try to parse as JSON
            let _ = serde_json::from_str::<Value>(s);

            // If you have custom parser
            // let _ = my_json::parse(s);
        }
    });
}
```

Corpus:
```bash
mkdir -p corpus/json
echo '{"key": "value"}' > corpus/json/simple.json
echo '{"nested": {"data": [1,2,3]}}' > corpus/json/nested.json
curl https://jsonplaceholder.typicode.com/posts/1 > corpus/json/api.json
```

### Example 2: Image Parser

```rust
// fuzz/image_parser.rs
use afl::fuzz;
use image::ImageReader;
use std::io::Cursor;

fn main() {
    fuzz(|data: &[u8]| {
        let cursor = Cursor::new(data);
        if let Ok(reader) = ImageReader::new(cursor).with_guessed_format() {
            let _ = reader.decode();
        }
    });
}
```

Corpus:
```bash
mkdir -p corpus/images
cp ~/Pictures/*.{png,jpg,gif} corpus/images/
# Add minimal valid images
convert -size 1x1 xc:white corpus/images/minimal.png
```

### Example 3: Protocol Parser

```rust
// fuzz/protocol.rs
use afl::fuzz;

#[derive(Debug)]
struct Message {
    version: u8,
    cmd: u8,
    length: u16,
    payload: Vec<u8>,
}

fn parse_message(data: &[u8]) -> Result<Message, &'static str> {
    if data.len() < 4 {
        return Err("Too short");
    }

    let version = data[0];
    let cmd = data[1];
    let length = u16::from_be_bytes([data[2], data[3]]);

    if data.len() < 4 + length as usize {
        return Err("Truncated");
    }

    Ok(Message {
        version,
        cmd,
        length,
        payload: data[4..4 + length as usize].to_vec(),
    })
}

fn main() {
    fuzz(|data: &[u8]| {
        let _ = parse_message(data);
    });
}
```

### Example 4: Fuzzing C Library from Rust

```rust
// fuzz/c_library.rs
use afl::fuzz;
use std::ffi::CString;

// Declare C function
extern "C" {
    fn parse_data(data: *const u8, len: usize) -> i32;
}

fn main() {
    fuzz(|data: &[u8]| {
        unsafe {
            let _ = parse_data(data.as_ptr(), data.len());
        }
    });
}
```

`build.rs`:
```rust
fn main() {
    cc::Build::new()
        .file("src/c_library.c")
        .compile("c_library");
}
```

---

## Troubleshooting

### Problem: "AFL not finding bugs"

**Solutions:**

1. **Improve corpus quality:**
   ```bash
   # Use real-world inputs
   cp production_samples/* corpus/
   ```

2. **Run longer:**
   ```bash
   # Let it run for at least 24 hours
   ```

3. **Try dictionaries:**
   ```bash
   # Create format.dict
   echo 'header="\x89PNG\r\n\x1a\n"' > format.dict
   cargo afl fuzz -x format.dict -i corpus -o findings ./target
   ```

4. **Use sanitizers:**
   ```bash
   export RUSTFLAGS="-Z sanitizer=address"
   cargo afl build --target x86_64-unknown-linux-gnu
   ```

### Problem: "Slow execution speed"

**Solutions:**

1. **Use release builds:**
   ```bash
   cargo afl build --release
   ```

2. **Simplify fuzz target:**
   ```rust
   // Bad: Too much work
   fuzz(|data| {
       parse(data).and_then(|x| process(x)).and_then(|y| save(y))
   });

   // Good: Focus on parse only
   fuzz(|data| {
       let _ = parse(data);
   });
   ```

3. **Reduce input size:**
   ```rust
   fuzz(|data: &[u8]| {
       if data.len() > 1024 {
           return; // Skip large inputs
       }
       // ... fuzzing logic
   });
   ```

### Problem: "Fuzzer hangs or stalls"

**Solutions:**

1. **Check timeout:**
   ```bash
   cargo afl fuzz -t 1000 -i corpus -o findings ./target
   ```

2. **Use AFL_NO_FORKSRV:**
   ```bash
   AFL_NO_FORKSRV=1 cargo afl fuzz -i corpus -o findings ./target
   ```

3. **Increase memory limit:**
   ```bash
   cargo afl fuzz -m 1024 -i corpus -o findings ./target
   ```

### Problem: "Crashes not reproducible"

**Causes:**
- Non-deterministic behavior
- Race conditions
- Uninitialized memory

**Solutions:**

1. **Check stability:**
   ```bash
   grep stability findings/fuzzer_stats
   ```

2. **Use AFL_NO_ARITH:**
   ```bash
   AFL_NO_ARITH=1 cargo afl fuzz -i corpus -o findings ./target
   ```

3. **Fix non-determinism in code:**
   ```rust
   // Bad: Time-dependent
   let timestamp = SystemTime::now();

   // Good: Use fuzzer input
   fuzz(|data| {
       // Deterministic behavior
   });
   ```

---

## Best Practices

### ✅ Do

- **Start with good corpus**: Use real-world samples
- **Run long enough**: Minimum 24 hours for serious fuzzing
- **Use release builds**: Much faster than debug
- **Monitor regularly**: Check for crashes daily
- **Minimize crashes**: Easier to analyze small inputs
- **Fix bugs promptly**: Re-run to verify fixes

### ❌ Don't

- **Don't ignore hangs**: They may indicate DoS bugs
- **Don't fuzz production**: Use isolated environment
- **Don't skip sanitizers**: They catch subtle bugs
- **Don't use tiny corpus**: Need variety for coverage
- **Don't stop too early**: Give it time to find bugs

---

## Resources

### Documentation
- [AFL Homepage](http://lcamtuf.coredump.cx/afl/)
- [afl.rs GitHub](https://github.com/rust-fuzz/afl.rs)
- [Rust Fuzz Book](https://rust-fuzz.github.io/book/)

### Tools
- [AFL++](https://github.com/AFLplusplus/AFLplusplus) - Enhanced AFL
- [libFuzzer](https://llvm.org/docs/LibFuzzer.html) - Alternative fuzzer
- [cargo-fuzz](https://github.com/rust-fuzz/cargo-fuzz) - libFuzzer for Rust

### Examples in This Repository
- `examples/rust_library/` - Library fuzzing example
- `examples/binary_wrapper/` - Binary fuzzing example
- `examples/ci_integration/` - CI/CD examples

---

## Getting Help

- **Issues**: https://github.com/rust-fuzz/afl.rs/issues
- **Discussions**: https://github.com/rust-fuzz/afl.rs/discussions
- **Rust Security**: https://www.rust-lang.org/policies/security

---

## Summary

You now have everything you need to integrate AFL fuzzing:

1. ✅ **Automated setup scripts** (`deploy_fuzzing.sh`)
2. ✅ **Source code integration** (Rust libraries)
3. ✅ **Binary fuzzing** (closed-source binaries)
4. ✅ **CI/CD integration** (GitHub Actions, GitLab CI)
5. ✅ **Monitoring tools** (`monitor_fuzzing.sh`)
6. ✅ **Real-world examples** (JSON, images, protocols)
7. ✅ **Troubleshooting guide** (common problems & solutions)

**Start fuzzing now and find bugs before attackers do!** 🐛🔒
