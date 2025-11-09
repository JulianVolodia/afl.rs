# macOS Fuzzing Guide: Finding Vulnerabilities with AFL

## Table of Contents

1. [Introduction](#introduction)
2. [Environment Setup](#environment-setup)
3. [Creating Fuzz Targets](#creating-fuzz-targets)
4. [Target macOS Frameworks](#target-macos-frameworks)
5. [Advanced Techniques](#advanced-techniques)
6. [Analyzing Results](#analyzing-results)
7. [Reporting to Apple](#reporting-to-apple)

---

## Introduction

This guide demonstrates how to use AFL (American Fuzzy Lop) to find security vulnerabilities in macOS system libraries and frameworks. AFL is a coverage-guided fuzzer that has discovered thousands of vulnerabilities in major software.

**Prerequisites:**
- Basic understanding of C/Rust programming
- Familiarity with macOS development
- Understanding of common vulnerability types (buffer overflow, UAF, etc.)

**What You'll Learn:**
- Setting up AFL on macOS
- Writing effective fuzz harnesses
- Fuzzing macOS frameworks (CoreGraphics, Foundation, etc.)
- Analyzing crashes and triaging bugs
- Responsible disclosure to Apple

---

## Environment Setup

### Quick Setup

Run the automated setup script:

```bash
chmod +x macos_fuzzing_setup.sh
./macos_fuzzing_setup.sh
```

### Manual Setup

If you prefer manual setup:

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Install afl.rs
cargo install afl

# 3. Disable crash reporter (IMPORTANT!)
sudo launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.ReportCrash.Root.plist

# 4. Verify installation
cargo afl --version
```

---

## Creating Fuzz Targets

### Basic Template

Every fuzz target follows this pattern:

```rust
// fuzz_target/src/main.rs
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Your fuzzing logic here
        // This closure is called repeatedly with random data
    });
}
```

### Example 1: Fuzzing String Parsing

```rust
use afl::fuzz;

fn parse_custom_format(data: &[u8]) -> Result<(), &'static str> {
    if data.len() < 4 {
        return Err("Too short");
    }

    // Simulate parsing logic
    let header = &data[0..4];
    if header != b"HEAD" {
        return Err("Invalid header");
    }

    // More parsing...
    Ok(())
}

fn main() {
    fuzz(|data: &[u8]| {
        let _ = parse_custom_format(data);
    });
}
```

### Example 2: Fuzzing with Structure

```rust
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Check minimum length
        if data.len() < 10 {
            return;
        }

        // Parse structured input
        let command = data[0];
        let length = u32::from_le_bytes([data[1], data[2], data[3], data[4]]) as usize;
        let payload = &data[5..];

        // Bounds checking
        if length > payload.len() {
            return;
        }

        // Process based on command
        match command {
            0x01 => process_type_a(&payload[..length]),
            0x02 => process_type_b(&payload[..length]),
            _ => return,
        }
    });
}

fn process_type_a(data: &[u8]) {
    // Your processing logic
}

fn process_type_b(data: &[u8]) {
    // Your processing logic
}
```

---

## Target macOS Frameworks

### 1. Fuzzing Image Parsing (CoreGraphics)

**Target:** CGImageSource (PNG, JPEG, GIF parsers)

```bash
# Create project
cargo new --bin fuzz_coregraphics
cd fuzz_coregraphics
```

**Cargo.toml:**
```toml
[package]
name = "fuzz_coregraphics"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
core-foundation = "0.9"
core-graphics = "0.23"

[[bin]]
name = "fuzz_image"
path = "src/main.rs"
```

**src/main.rs:**
```rust
use afl::fuzz;
use core_foundation::data::CFData;
use core_graphics::image::CGImageSource;

fn main() {
    fuzz(|data: &[u8]| {
        // Create CFData from fuzz input
        let cf_data = CFData::from_buffer(data);

        // Try to create image source
        if let Some(source) = CGImageSource::from_data(&cf_data, None) {
            // Exercise various APIs
            let _ = source.get_type();
            let count = source.get_count();

            // Try to create images
            for index in 0..count.min(5) {
                if let Some(image) = source.create_image_at_index(index, None) {
                    // Access image properties
                    let _ = image.width();
                    let _ = image.height();
                    let _ = image.bits_per_component();
                    let _ = image.bits_per_pixel();
                }
            }
        }
    });
}
```

**Build and run:**
```bash
# Build with AFL instrumentation
cargo afl build --release

# Create corpus directory with sample images
mkdir -p corpus/images
cp /System/Library/Desktop\ Pictures/*.jpg corpus/images/

# Start fuzzing
cargo afl fuzz \
    -i corpus/images \
    -o findings/coregraphics \
    target/release/fuzz_image
```

### 2. Fuzzing Archive Parsing (libarchive)

**Target:** ZIP, TAR, RAR archive handlers

```rust
use afl::fuzz;
use std::io::Cursor;

fn main() {
    fuzz(|data: &[u8]| {
        // Fuzz ZIP parsing
        let cursor = Cursor::new(data);
        if let Ok(mut archive) = zip::ZipArchive::new(cursor) {
            // Enumerate entries
            for i in 0..archive.len().min(100) {
                if let Ok(file) = archive.by_index(i) {
                    let _ = file.name();
                    let _ = file.size();
                    let _ = file.compressed_size();
                }
            }
        }
    });
}
```

### 3. Fuzzing XML/Plist Parsing (Foundation)

**Target:** NSPropertyListSerialization, NSXMLParser

```rust
use afl::fuzz;
use plist::Value;

fn main() {
    fuzz(|data: &[u8]| {
        // Try parsing as binary plist
        let _ = Value::from_reader(data);

        // Try parsing as XML plist
        let _ = Value::from_reader_xml(data);
    });
}
```

### 4. Fuzzing Font Parsing (CoreText)

**Target:** TTF, OTF font parsers

```rust
use afl::fuzz;
use core_text::font_descriptor::CTFontDescriptor;

fn main() {
    fuzz(|data: &[u8]| {
        // Write data to temporary file
        let temp_path = "/tmp/fuzz_font.ttf";
        if std::fs::write(temp_path, data).is_ok() {
            // Try to load as font
            if let Ok(descriptor) = CTFontDescriptor::from_path(temp_path) {
                let _ = descriptor.family_name();
                let _ = descriptor.display_name();
            }
            let _ = std::fs::remove_file(temp_path);
        }
    });
}
```

### 5. Fuzzing Audio/Video Codecs (AVFoundation)

**Target:** MP4, MOV, AAC parsers

```rust
use afl::fuzz;
use std::fs::File;
use std::io::Write;

fn main() {
    fuzz(|data: &[u8]| {
        let temp_path = "/tmp/fuzz_video.mp4";

        // Write fuzz data to temp file
        if let Ok(mut file) = File::create(temp_path) {
            let _ = file.write_all(data);
        }

        // Try to parse with AVFoundation (via FFI or using a crate)
        // This requires binding to AVFoundation APIs

        let _ = std::fs::remove_file(temp_path);
    });
}
```

### 6. Fuzzing PDF Parsing (PDFKit)

**Target:** PDF parser

**Note:** PDFKit is Objective-C based, so you'll need to use `objc` crate or FFI:

```rust
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Write to temp file
        let temp_pdf = "/tmp/fuzz.pdf";
        if std::fs::write(temp_pdf, data).is_ok() {
            // Call PDFKit via FFI
            // (simplified - actual implementation requires objc bindings)
            unsafe {
                // let pdf = PDFDocument::initWithURL(...)
                // Exercise PDF APIs
            }
            let _ = std::fs::remove_file(temp_pdf);
        }
    });
}
```

---

## Advanced Techniques

### Using AddressSanitizer (ASan)

ASan detects memory corruption bugs:

```bash
# Build with ASan
export RUSTFLAGS="-Z sanitizer=address"
export ASAN_OPTIONS="detect_leaks=0:abort_on_error=1"
cargo afl build --target x86_64-apple-darwin

# Run fuzzer
cargo afl fuzz -i corpus -o findings ./target/x86_64-apple-darwin/debug/fuzz_target
```

### Using UndefinedBehaviorSanitizer (UBSan)

```bash
export RUSTFLAGS="-Z sanitizer=undefined"
cargo afl build --target x86_64-apple-darwin
```

### Dictionary-Based Fuzzing

Create a dictionary file for better coverage:

```
# magic.dict
header_png="\x89PNG\r\n\x1a\n"
header_jpeg="\xFF\xD8\xFF"
header_gif="GIF89a"
chunk_ihdr="IHDR"
chunk_idat="IDAT"
```

Use with AFL:

```bash
cargo afl fuzz -i corpus -o findings -x magic.dict ./target/release/fuzz_target
```

### Persistent Mode (Already Enabled)

The `fuzz()` function automatically uses AFL's persistent mode (1000 iterations per fork), which is much faster than traditional fuzzing.

### Parallel Fuzzing

Run multiple fuzzing instances:

```bash
# Master instance
cargo afl fuzz -i corpus -o findings -M fuzzer01 ./target/release/fuzz_target &

# Slave instances
cargo afl fuzz -i corpus -o findings -S fuzzer02 ./target/release/fuzz_target &
cargo afl fuzz -i corpus -o findings -S fuzzer03 ./target/release/fuzz_target &
cargo afl fuzz -i corpus -o findings -S fuzzer04 ./target/release/fuzz_target &

# Monitor all instances
cargo afl whatsup findings
```

---

## Analyzing Results

### Understanding AFL Output

```
┌─────────────────────────────────────────────────────────────┐
│        american fuzzy lop 2.52b (fuzz_target)               │
├─────────────────────────────┬───────────────────────────────┤
│ process timing              │ overall results               │
│   run time : 0 days, 2 hrs  │   cycles done : 12            │
│   last new path : 0 days, 0 │   total paths : 234           │
│   last uniq crash : none    │   uniq crashes : 0            │
│   last uniq hang : none     │   uniq hangs : 0              │
├─────────────────────────────┼───────────────────────────────┤
│ cycle progress              │ map coverage                  │
│   now processing : 189/234  │   map density : 4.23%         │
│   paths timed out : 0       │   count coverage : 2.11 bits  │
├─────────────────────────────┼───────────────────────────────┤
│ stage progress              │ findings in depth             │
│   now trying : havoc        │   favored paths : 67          │
│   stage execs : 1245/5000   │   new edges on : 123          │
│   total execs : 12.3M       │   total crashes : 0           │
│   exec speed : 4500/sec     │   total hangs : 0             │
└─────────────────────────────┴───────────────────────────────┘
```

**Key Metrics:**
- **cycles done:** Number of complete fuzzing cycles
- **uniq crashes:** Unique crashes found
- **exec speed:** Iterations per second (higher is better)
- **map density:** Code coverage percentage

### Triaging Crashes

When AFL finds crashes, they appear in `findings/crashes/`:

```bash
# List crashes
ls -la findings/crashes/

# Example output:
# id:000000,sig:06,src:000123,op:havoc,rep:4
# id:000001,sig:11,src:000456,op:splice,rep:2
```

**Signal codes:**
- `sig:06` = SIGABRT (assertion failure)
- `sig:11` = SIGSEGV (segmentation fault)
- `sig:08` = SIGFPE (floating point exception)

### Reproducing Crashes

```bash
# Replay crash
cat findings/crashes/id:000000,sig:06,... | ./target/release/fuzz_target

# With debugger
lldb ./target/release/fuzz_target
(lldb) run < findings/crashes/id:000000,sig:06,...
```

### Minimizing Test Cases

```bash
# Minimize crash input
cargo afl tmin \
    -i findings/crashes/id:000000,sig:06,... \
    -o minimized_crash.bin \
    ./target/release/fuzz_target

# Minimize corpus
cargo afl cmin \
    -i corpus \
    -o corpus_minimized \
    ./target/release/fuzz_target
```

### Analyzing with ASan

If built with ASan, crashes will show detailed reports:

```
=================================================================
==12345==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000001234 at pc 0x00010abcdef0
READ of size 4 at 0x602000001234 thread T0
    #0 0x10abcdef0 in parse_chunk fuzz_target.rs:42
    #1 0x10abcdf00 in main::{{closure}} fuzz_target.rs:18
    ...

0x602000001234 is located 0 bytes to the right of 20-byte region
allocated by thread T0 here:
    #0 0x10abc1234 in malloc
    #1 0x10abcd000 in alloc::alloc::alloc
    ...
```

---

## Reporting to Apple

### Before Reporting

1. **Verify Reproducibility:**
   - Test on multiple macOS versions if possible
   - Ensure crash is consistent
   - Minimize the test case

2. **Assess Impact:**
   - Can you achieve code execution?
   - Does it leak sensitive data?
   - Is it remotely exploitable?
   - What privileges are required?

3. **Gather Information:**
   - Affected macOS version(s)
   - Crash logs
   - Minimized PoC
   - Fuzz harness source code
   - ASan/UBSan output if available

### Reporting Process

**Email:** product-security@apple.com

**Subject Line:**
```
[Security] <Vulnerability Type> in <Component>
```

**Example:**
```
Subject: [Security] Heap Buffer Overflow in CoreGraphics PNG Parser

Hello Apple Product Security Team,

I discovered a heap buffer overflow vulnerability in CoreGraphics when
parsing malformed PNG images. This issue affects macOS Sonoma 14.1 and
potentially other versions.

SUMMARY:
A heap buffer overflow occurs when CoreGraphics processes a PNG image
with a malformed IDAT chunk, potentially allowing arbitrary code execution.

AFFECTED VERSIONS:
- macOS Sonoma 14.1 (Build 23B74)
- macOS Ventura 13.6 (not tested, likely affected)

IMPACT:
An attacker can trigger this vulnerability by convincing a user to open
a malicious PNG file in any application that uses CoreGraphics (Safari,
Preview, Quick Look, etc.). Successful exploitation could lead to
arbitrary code execution with the privileges of the victim application.

REPRODUCTION STEPS:
1. Build the attached fuzz harness: cargo afl build --release
2. Run with PoC: cat poc.png | ./target/release/fuzz_coregraphics
3. Crash occurs immediately

TECHNICAL DETAILS:
When processing the IDAT chunk, the parser allocates a buffer based on
the declared chunk size but fails to validate the actual data length.
This leads to a heap buffer overflow when decompressing the chunk data.

AddressSanitizer output:
=================================================================
==12345==ERROR: AddressSanitizer: heap-buffer-overflow
[Full ASan output attached]

PROOF OF CONCEPT:
Attached files:
- poc.png (minimized crashing input, 143 bytes)
- fuzz_harness.tar.gz (Rust project source)
- crash.log (full crash log)
- asan_output.txt (AddressSanitizer report)

I am happy to provide additional information or clarification as needed.
I will follow your coordinated disclosure policy and will not publicly
disclose this issue until a fix is available or 90 days have passed.

Best regards,
[Your Name]
[Your Email]

PGP Key: [Optional, if you have one]
```

### What Apple Expects

- **Clear description** of the vulnerability
- **Minimal PoC** that demonstrates the issue
- **Impact assessment** (what can an attacker do?)
- **Professional tone** and responsible disclosure intent

### Timeline Expectations

- **Day 0-3:** Apple acknowledges receipt
- **Day 7-14:** Apple confirms the issue (or asks for clarification)
- **Day 30-90:** Apple develops and tests a fix
- **Day 90+:** Coordinated public disclosure

### Bug Bounty Rewards

Apple's Security Bounty program offers:
- **$100,000+:** Remote code execution on macOS without user interaction
- **$50,000+:** Kernel code execution
- **$25,000+:** Sandbox escape
- **Variable:** Based on severity, impact, and quality of report

**Details:** https://security.apple.com/bounty/

---

## Best Practices

### Do's ✅

- ✅ Test on your own macOS installation
- ✅ Use virtual machines when possible
- ✅ Start with sample files from the internet
- ✅ Minimize test cases before reporting
- ✅ Follow responsible disclosure practices
- ✅ Document your methodology
- ✅ Keep detailed notes of findings

### Don'ts ❌

- ❌ Fuzz production systems without authorization
- ❌ Publicly disclose before vendor has time to fix
- ❌ Access or exfiltrate user data
- ❌ Test vulnerabilities on other people's systems
- ❌ Weaponize or sell vulnerabilities
- ❌ Ignore the 90-day disclosure deadline

---

## Troubleshooting

### AFL Won't Start

**Error:** "Looks like the target binary terminated..."

**Solutions:**
- Disable crash reporter (see setup section)
- Try `AFL_NO_FORKSRV=1`
- Check that binary has AFL instrumentation: `nm target/release/fuzz_target | grep afl`

### Slow Fuzzing Performance

**Typical macOS speeds:** 500-3000 execs/sec (slower than Linux)

**Improvements:**
- Use release builds: `cargo afl build --release`
- Reduce input size in your harness
- Run parallel fuzzing instances
- Consider using Linux VM for better performance

### No New Paths Found

**Solutions:**
- Improve your initial corpus (use real-world files)
- Use a dictionary (`-x` flag)
- Simplify your fuzz target
- Check that you're actually calling the target code

### Compilation Errors on macOS

**Error:** "ld: unknown option: -fuse-ld=gold"

**Solution:** Already fixed in afl.rs 0.4.3+ (gold linker only used on Linux)

---

## Resources

### Official Documentation
- **AFL Homepage:** http://lcamtuf.coredump.cx/afl/
- **afl.rs GitHub:** https://github.com/rust-fuzz/afl.rs
- **Rust Fuzz Book:** https://rust-fuzz.github.io/book/

### Apple Resources
- **Security Bounty:** https://security.apple.com/bounty/
- **Report a Vulnerability:** https://support.apple.com/en-us/HT201220
- **macOS Security Guide:** https://support.apple.com/guide/security/welcome/web

### Learning Resources
- **Fuzzing101:** https://github.com/antonio-morales/Fuzzing101
- **AFL Tutorial:** https://aflplus.plus/docs/tutorials/
- **Google's FuzzTest:** https://github.com/google/fuzztest

---

## Conclusion

Fuzzing is a powerful technique for discovering security vulnerabilities. By following this guide, you can:
1. Set up AFL on macOS
2. Create effective fuzz harnesses
3. Target macOS frameworks and libraries
4. Analyze and triage crashes
5. Report vulnerabilities responsibly to Apple

Remember: **Security research must be conducted ethically and legally.** Always follow responsible disclosure practices and respect the security of others.

**Happy hunting, and stay responsible!** 🔒🐛

---

**Questions or Issues?**
- afl.rs Issues: https://github.com/rust-fuzz/afl.rs/issues
- Apple Product Security: product-security@apple.com
