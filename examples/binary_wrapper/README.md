# Example: Fuzzing Binary Executables

This example shows how to fuzz binary executables that you don't have source code for.

## Use Cases

- Fuzzing third-party binaries
- Testing closed-source applications
- Fuzzing system utilities
- Quick testing without recompilation

## Methods

### 1. Black-Box Fuzzing (No Source Required)

Fuzz a binary without instrumentation:

```bash
./fuzz_binary.sh /path/to/binary
```

**Pros:**
- No source code needed
- Works with any binary
- Quick setup

**Cons:**
- Much slower than instrumented fuzzing
- Less coverage feedback
- May miss subtle bugs

### 2. Instrumented Binary Fuzzing

If you can recompile the target:

```bash
# For C programs
CC=afl-gcc make
CC=afl-clang make

# For C++ programs
CXX=afl-g++ make
CXX=afl-clang++ make
```

Then use the automated script:

```bash
./fuzz_binary.sh /path/to/instrumented_binary
```

## Input Methods

The script auto-detects how the binary accepts input:

### Method 1: stdin

```bash
# Binary reads from standard input
cat input.txt | ./binary
```

Wrapper:
```bash
#!/bin/bash
cat "$1" | ./binary
```

### Method 2: File Argument

```bash
# Binary takes filename as argument
./binary input.txt
```

Wrapper:
```bash
#!/bin/bash
./binary "$1"
```

### Method 3: Command-Line Arguments

```bash
# Binary takes input as args
./binary "some input data"
```

Wrapper:
```bash
#!/bin/bash
./binary "$(cat "$1")"
```

## Manual Setup

If you prefer manual setup:

### 1. Create Wrapper Script

```bash
#!/bin/bash
# wrapper.sh
cat "$1" | /path/to/binary 2>&1
```

Make executable:
```bash
chmod +x wrapper.sh
```

### 2. Create Corpus

```bash
mkdir -p corpus/initial
echo "test1" > corpus/initial/test1.txt
echo "test2" > corpus/initial/test2.txt
```

### 3. Run AFL

For instrumented binaries:
```bash
afl-fuzz -i corpus/initial -o findings ./binary @@
```

For black-box fuzzing:
```bash
afl-fuzz -i corpus/initial -o findings -n ./wrapper.sh @@
```

## Real-World Examples

### Example 1: Fuzzing `file` Command

```bash
# Create wrapper
cat > fuzz_file.sh << 'EOF'
#!/bin/bash
file "$1" 2>&1
EOF
chmod +x fuzz_file.sh

# Create corpus with various file types
mkdir -p corpus
cp /usr/share/pixmaps/*.png corpus/
cp /usr/share/doc/*.txt corpus/

# Run fuzzer
afl-fuzz -i corpus -o findings -n ./fuzz_file.sh @@
```

### Example 2: Fuzzing Image Decoders

```bash
# Fuzz pngcheck
cat > fuzz_png.sh << 'EOF'
#!/bin/bash
pngcheck "$1" 2>&1
EOF
chmod +x fuzz_png.sh

# Corpus of valid PNG files
mkdir -p corpus
cp ~/Pictures/*.png corpus/

# Fuzz
afl-fuzz -i corpus -o findings -n ./fuzz_png.sh @@
```

### Example 3: Fuzzing PDF Readers

```bash
# Fuzz pdftotext
cat > fuzz_pdf.sh << 'EOF'
#!/bin/bash
pdftotext "$1" /dev/null 2>&1
EOF
chmod +x fuzz_pdf.sh

# Corpus of PDF files
mkdir -p corpus
cp ~/Documents/*.pdf corpus/

# Fuzz
afl-fuzz -i corpus -o findings -n ./fuzz_pdf.sh @@
```

## Improving Binary Fuzzing

### 1. Use QEMU Mode (Linux only)

For better performance without recompilation:

```bash
# Build AFL with QEMU support
cd AFL/qemu_mode
./build_qemu_support.sh

# Fuzz with QEMU mode
afl-fuzz -Q -i corpus -o findings ./binary @@
```

**Note:** QEMU mode is not available on macOS.

### 2. Use Dyninst Mode

Instrument binaries without source:

```bash
# Install Dyninst
# Build AFL with dyninst support

# Instrument binary
afl-dyninst -i ./binary -o ./binary-instrumented

# Fuzz instrumented binary
afl-fuzz -i corpus -o findings ./binary-instrumented @@
```

### 3. Add Better Corpus

```bash
# Collect real-world inputs
# Minimize corpus
afl-cmin -i corpus -o corpus_minimized ./binary @@

# Use minimized corpus
afl-fuzz -i corpus_minimized -o findings ./binary @@
```

## Fuzzing macOS Binaries

### System Utilities

```bash
# Fuzz textutil (text converter)
./fuzz_binary.sh /usr/bin/textutil

# Fuzz qlmanage (Quick Look)
./fuzz_binary.sh /usr/bin/qlmanage

# Fuzz sips (image processor)
./fuzz_binary.sh /usr/bin/sips
```

### Create macOS-Specific Wrapper

```bash
#!/bin/bash
# fuzz_quicklook.sh
#
# Fuzzes Quick Look thumbnail generation

INPUT="$1"
OUTPUT="/tmp/ql_output.png"

qlmanage -t -s 256 -o /tmp "$INPUT" 2>&1
rm -f "$OUTPUT"
```

## Monitoring Binary Fuzzing

### Check Status

```bash
# View AFL stats
watch -n 1 'cat findings/fuzzer_stats'

# Count crashes
find findings/crashes -type f ! -name "README.txt" | wc -l

# Monitor CPU usage
top | grep afl-fuzz
```

### Analyze Crashes

```bash
# Test crash
./binary < findings/crashes/id:000000,sig:11,...

# With debugger
lldb ./binary
(lldb) run < findings/crashes/id:000000,sig:11,...

# Get crash details
./binary < findings/crashes/id:000000,sig:11,... 2>&1 | head -50
```

### Minimize Crashes

```bash
# Minimize crash input
afl-tmin -i findings/crashes/id:000000,sig:11,... \
         -o minimized.bin \
         ./wrapper.sh @@

# Verify minimized crash
./binary < minimized.bin
```

## Automated Binary Fuzzing Script

Use the deployment script for automatic setup:

```bash
# Interactive mode
/path/to/deploy_fuzzing.sh --binary /path/to/binary

# Or specify directly
/path/to/deploy_fuzzing.sh --binary /usr/bin/some_utility
```

This will:
1. Detect input method automatically
2. Create appropriate wrapper
3. Generate sample corpus
4. Set up monitoring scripts
5. Create run scripts

## Tips for Binary Fuzzing

1. **Start with good inputs**: Use real-world files for corpus
2. **Check binary requirements**: Some binaries need specific environments
3. **Monitor memory**: Binaries may leak memory during fuzzing
4. **Use timeouts**: Set appropriate timeout for slow operations
5. **Parallel fuzzing**: Run multiple instances
6. **Instrumentation is better**: Always try to get instrumented builds

## Limitations

- **Slower**: Black-box fuzzing is 5-100x slower
- **Less coverage**: Without instrumentation, harder to explore code paths
- **macOS QEMU unavailable**: Can't use QEMU mode on macOS
- **Dependencies**: Binary may need specific libraries or environments

## Resources

- [AFL QEMU Mode](https://github.com/google/AFL/tree/master/qemu_mode)
- [AFL Dyninst](https://github.com/talos-vulndev/afl-dyninst)
- [Binary Fuzzing Guide](https://github.com/google/AFL/blob/master/docs/binaryonly_fuzzing.txt)
