#!/bin/bash
#
# AFL Fuzzing Deployment Script
#
# This script helps you integrate AFL fuzzing into:
# 1. Your Rust source code projects
# 2. Existing binary executables
# 3. C/C++ libraries
# 4. System libraries
#
# Usage:
#   ./deploy_fuzzing.sh --source /path/to/rust/project
#   ./deploy_fuzzing.sh --binary /path/to/executable
#   ./deploy_fuzzing.sh --interactive
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
FUZZ_BASE_DIR="${FUZZ_BASE_DIR:-$HOME/fuzzing_workspace}"
AFL_TIMEOUT="${AFL_TIMEOUT:-5000}"
AFL_MEMORY="${AFL_MEMORY:-512}"
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[✓]${NC} $1"; }
echo_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
echo_error() { echo -e "${RED}[✗]${NC} $1"; }
echo_header() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# Display banner
display_banner() {
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║        AFL Fuzzing Deployment Script v1.0            ║
    ║        Automate Fuzzing Integration                  ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
}

# Check if AFL is installed
check_afl_installed() {
    if ! command -v cargo-afl &> /dev/null; then
        echo_error "cargo-afl not found!"
        echo_info "Installing afl.rs..."
        cargo install afl
    else
        echo_success "cargo-afl is installed"
    fi
}

# Interactive mode
interactive_mode() {
    echo_header "Interactive Fuzzing Setup"

    echo "What would you like to fuzz?"
    echo "  1) Rust source code project"
    echo "  2) Existing binary executable"
    echo "  3) Rust library (create harness)"
    echo "  4) C/C++ program"
    echo "  5) File format parser"
    echo "  6) Network protocol"
    echo ""
    read -p "Select option [1-6]: " choice

    case $choice in
        1) fuzz_rust_project ;;
        2) fuzz_binary ;;
        3) fuzz_rust_library ;;
        4) fuzz_c_program ;;
        5) fuzz_file_format ;;
        6) fuzz_network_protocol ;;
        *) echo_error "Invalid option"; exit 1 ;;
    esac
}

# Fuzz Rust project
fuzz_rust_project() {
    echo_header "Fuzzing Rust Project"

    read -p "Enter path to Rust project: " project_path

    if [ ! -f "$project_path/Cargo.toml" ]; then
        echo_error "Not a valid Rust project (no Cargo.toml found)"
        exit 1
    fi

    PROJECT_NAME=$(basename "$project_path")
    FUZZ_DIR="$FUZZ_BASE_DIR/$PROJECT_NAME"

    echo_info "Creating fuzzing workspace at: $FUZZ_DIR"
    mkdir -p "$FUZZ_DIR"/{corpus,findings,crashes_minimized,logs}

    # Create fuzz target directory
    FUZZ_TARGET_DIR="$FUZZ_DIR/fuzz_targets"
    mkdir -p "$FUZZ_TARGET_DIR"

    # Copy project
    echo_info "Copying project to fuzzing workspace..."
    cp -r "$project_path" "$FUZZ_TARGET_DIR/target_project"
    cd "$FUZZ_TARGET_DIR/target_project"

    # Add AFL dependency
    echo_info "Adding AFL dependency to Cargo.toml..."
    if ! grep -q "afl = " Cargo.toml; then
        cat >> Cargo.toml << 'EOF'

[dependencies.afl]
version = "0.4"
optional = true

[[bin]]
name = "fuzz_target"
path = "fuzz/main.rs"
required-features = ["afl"]
EOF
    fi

    # Create fuzz harness
    echo_info "Creating fuzz harness..."
    mkdir -p fuzz

    cat > fuzz/main.rs << 'EOF'
#[cfg(feature = "afl")]
use afl::fuzz;

fn main() {
    #[cfg(feature = "afl")]
    fuzz(|data: &[u8]| {
        // TODO: Add your fuzzing logic here
        // Example: Parse the data with your library

        // If data is too small, skip
        if data.len() < 4 {
            return;
        }

        // Example: Convert to string and process
        if let Ok(s) = std::str::from_utf8(data) {
            // Call your library functions here
            // let _ = your_library::parse(s);
        }

        // Example: Use raw bytes
        // let _ = your_library::process_bytes(data);
    });

    #[cfg(not(feature = "afl"))]
    println!("This binary requires the 'afl' feature to be enabled");
}
EOF

    echo_success "Fuzz harness created at: fuzz/main.rs"
    echo_warning "IMPORTANT: Edit fuzz/main.rs to add your actual fuzzing logic!"

    # Create sample corpus
    echo_info "Creating sample corpus..."
    mkdir -p "$FUZZ_DIR/corpus/initial"
    echo "test" > "$FUZZ_DIR/corpus/initial/test1.txt"
    echo "sample" > "$FUZZ_DIR/corpus/initial/test2.txt"
    echo '{"key": "value"}' > "$FUZZ_DIR/corpus/initial/test3.json"

    # Build
    echo_info "Building with AFL instrumentation..."
    cargo afl build --release --features afl

    # Create run script
    create_run_script "$FUZZ_DIR" "$FUZZ_TARGET_DIR/target_project/target/release/fuzz_target"

    # Create monitoring script
    create_monitoring_script "$FUZZ_DIR"

    echo_success "Setup complete!"
    echo_info "Next steps:"
    echo "  1. Edit the fuzz harness: nano $FUZZ_TARGET_DIR/target_project/fuzz/main.rs"
    echo "  2. Rebuild: cd $FUZZ_TARGET_DIR/target_project && cargo afl build --release --features afl"
    echo "  3. Add corpus files to: $FUZZ_DIR/corpus/initial/"
    echo "  4. Start fuzzing: $FUZZ_DIR/run_fuzzer.sh"
    echo "  5. Monitor: $FUZZ_DIR/monitor.sh"
}

# Fuzz existing binary
fuzz_binary() {
    echo_header "Fuzzing Binary Executable"

    read -p "Enter path to binary: " binary_path

    if [ ! -f "$binary_path" ]; then
        echo_error "Binary not found: $binary_path"
        exit 1
    fi

    if [ ! -x "$binary_path" ]; then
        echo_error "File is not executable"
        exit 1
    fi

    BINARY_NAME=$(basename "$binary_path")
    FUZZ_DIR="$FUZZ_BASE_DIR/${BINARY_NAME}_fuzz"

    echo_info "Creating fuzzing workspace at: $FUZZ_DIR"
    mkdir -p "$FUZZ_DIR"/{corpus,findings,crashes_minimized,logs}

    # Copy binary
    cp "$binary_path" "$FUZZ_DIR/target_binary"
    chmod +x "$FUZZ_DIR/target_binary"

    echo_info "How does the binary accept input?"
    echo "  1) From stdin (e.g., cat file | ./binary)"
    echo "  2) From file argument (e.g., ./binary input.txt)"
    echo "  3) From command line args"
    read -p "Select [1-3]: " input_method

    # Create wrapper based on input method
    create_binary_wrapper "$FUZZ_DIR" "$input_method"

    # Create sample corpus
    echo_info "Creating sample corpus..."
    mkdir -p "$FUZZ_DIR/corpus/initial"
    echo "test" > "$FUZZ_DIR/corpus/initial/test1.txt"
    dd if=/dev/urandom bs=1024 count=1 2>/dev/null > "$FUZZ_DIR/corpus/initial/random1.bin"

    # Create run script for binary
    create_binary_run_script "$FUZZ_DIR" "$input_method"

    # Create monitoring script
    create_monitoring_script "$FUZZ_DIR"

    echo_success "Setup complete!"
    echo_info "Next steps:"
    echo "  1. Add sample inputs to: $FUZZ_DIR/corpus/initial/"
    echo "  2. Start fuzzing: $FUZZ_DIR/run_fuzzer.sh"
    echo "  3. Monitor: $FUZZ_DIR/monitor.sh"
}

# Fuzz Rust library
fuzz_rust_library() {
    echo_header "Creating Fuzz Harness for Rust Library"

    read -p "Enter library name (from crates.io or local): " lib_name
    read -p "Enter function/module to fuzz: " fuzz_target_fn

    FUZZ_DIR="$FUZZ_BASE_DIR/${lib_name}_fuzz"
    echo_info "Creating fuzzing workspace at: $FUZZ_DIR"
    mkdir -p "$FUZZ_DIR"/{corpus,findings}

    cd "$FUZZ_DIR"
    cargo init --name "fuzz_${lib_name}" --bin
    cd "fuzz_${lib_name}"

    # Create Cargo.toml
    cat > Cargo.toml << EOF
[package]
name = "fuzz_${lib_name}"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
$lib_name = "*"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    # Create fuzz harness
    cat > src/main.rs << EOF
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Example: Fuzz string parsing
        if let Ok(s) = std::str::from_utf8(data) {
            // TODO: Call your library function
            // let _ = ${lib_name}::${fuzz_target_fn}(s);
        }

        // Example: Fuzz binary data
        // let _ = ${lib_name}::${fuzz_target_fn}(data);

        // Example: Fuzz structured data
        // if data.len() >= 4 {
        //     let value = u32::from_le_bytes([data[0], data[1], data[2], data[3]]);
        //     let _ = ${lib_name}::${fuzz_target_fn}(value);
        // }
    });
}
EOF

    echo_warning "IMPORTANT: Edit src/main.rs to call your actual library functions!"
    echo_info "Building..."
    cargo afl build --release

    # Create corpus
    mkdir -p "$FUZZ_DIR/corpus/initial"
    echo "sample" > "$FUZZ_DIR/corpus/initial/test.txt"

    create_run_script "$FUZZ_DIR" "$FUZZ_DIR/fuzz_${lib_name}/target/release/fuzz_target"
    create_monitoring_script "$FUZZ_DIR"

    echo_success "Library fuzz harness created!"
    echo_info "Edit: $FUZZ_DIR/fuzz_${lib_name}/src/main.rs"
    echo_info "Build: cd $FUZZ_DIR/fuzz_${lib_name} && cargo afl build --release"
    echo_info "Run: $FUZZ_DIR/run_fuzzer.sh"
}

# Fuzz C/C++ program
fuzz_c_program() {
    echo_header "Fuzzing C/C++ Program"

    read -p "Enter path to C/C++ source directory: " source_dir

    if [ ! -d "$source_dir" ]; then
        echo_error "Directory not found"
        exit 1
    fi

    PROJECT_NAME=$(basename "$source_dir")
    FUZZ_DIR="$FUZZ_BASE_DIR/${PROJECT_NAME}_fuzz"

    mkdir -p "$FUZZ_DIR"/{corpus,findings}

    # Create Rust wrapper
    cd "$FUZZ_DIR"
    cargo init --name "fuzz_wrapper" --bin
    cd fuzz_wrapper

    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_wrapper"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
libc = "0.2"

[build-dependencies]
cc = "1.0"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    # Create build.rs for compiling C code
    cat > build.rs << EOF
fn main() {
    cc::Build::new()
        .file("$source_dir/main.c")  // Adjust this path
        .compile("target_c_code");
}
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;

// Declare C function
extern "C" {
    // fn your_c_function(data: *const u8, len: usize) -> i32;
}

fn main() {
    fuzz(|data: &[u8]| {
        unsafe {
            // Call your C function
            // let _ = your_c_function(data.as_ptr(), data.len());
        }
    });
}
EOF

    echo_warning "IMPORTANT: Edit build.rs and src/main.rs to match your C code!"
    echo_info "You need to:"
    echo "  1. Update build.rs with correct C source files"
    echo "  2. Declare C functions in src/main.rs"
    echo "  3. Call C functions from the fuzz closure"

    echo_success "C/C++ wrapper created at: $FUZZ_DIR/fuzz_wrapper"
}

# Fuzz file format
fuzz_file_format() {
    echo_header "Fuzzing File Format Parser"

    echo "What file format?"
    echo "  1) Image (PNG, JPEG, GIF)"
    echo "  2) Document (PDF, DOCX)"
    echo "  3) Archive (ZIP, TAR, RAR)"
    echo "  4) Audio/Video (MP3, MP4)"
    echo "  5) Custom format"
    read -p "Select [1-5]: " format_choice

    read -p "Enter project name: " project_name

    FUZZ_DIR="$FUZZ_BASE_DIR/${project_name}"
    mkdir -p "$FUZZ_DIR"/{corpus,findings}

    cd "$FUZZ_DIR"
    cargo init --name "$project_name" --bin
    cd "$project_name"

    case $format_choice in
        1) create_image_fuzzer ;;
        2) create_document_fuzzer ;;
        3) create_archive_fuzzer ;;
        4) create_media_fuzzer ;;
        5) create_custom_fuzzer ;;
    esac
}

# Create image format fuzzer
create_image_fuzzer() {
    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_image"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
image = "0.24"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;
use image::ImageReader;
use std::io::Cursor;

fn main() {
    fuzz(|data: &[u8]| {
        let cursor = Cursor::new(data);

        // Try to decode as various image formats
        if let Ok(reader) = ImageReader::new(cursor).with_guessed_format() {
            // Try to decode - this will catch crashes/panics
            let _ = reader.decode();
        }
    });
}
EOF

    echo_info "Building image fuzzer..."
    cargo afl build --release

    # Create image corpus
    echo_info "Creating image corpus..."
    mkdir -p "../corpus/images"

    echo_success "Image fuzzer created!"
    echo_info "Add sample images to: $FUZZ_DIR/corpus/images/"
}

# Create archive fuzzer
create_archive_fuzzer() {
    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_archive"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
zip = "0.6"
tar = "0.4"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;
use std::io::Cursor;

fn main() {
    fuzz(|data: &[u8]| {
        // Try as ZIP
        let cursor = Cursor::new(data);
        if let Ok(mut archive) = zip::ZipArchive::new(cursor) {
            for i in 0..archive.len().min(100) {
                let _ = archive.by_index(i);
            }
        }

        // Try as TAR
        let cursor = Cursor::new(data);
        let mut archive = tar::Archive::new(cursor);
        if let Ok(entries) = archive.entries() {
            for entry in entries.take(100) {
                let _ = entry;
            }
        }
    });
}
EOF

    cargo afl build --release
    echo_success "Archive fuzzer created!"
}

# Create custom format fuzzer
create_custom_fuzzer() {
    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_custom"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;

// Your custom format parser
fn parse_custom_format(data: &[u8]) -> Result<(), &'static str> {
    if data.len() < 8 {
        return Err("Too short");
    }

    // Example: Parse header
    let magic = &data[0..4];
    if magic != b"CUST" {
        return Err("Invalid magic");
    }

    let size = u32::from_le_bytes([data[4], data[5], data[6], data[7]]) as usize;

    if data.len() < 8 + size {
        return Err("Truncated");
    }

    let payload = &data[8..8+size];

    // TODO: Parse payload
    // This is where bugs might be!

    Ok(())
}

fn main() {
    fuzz(|data: &[u8]| {
        let _ = parse_custom_format(data);
    });
}
EOF

    echo_success "Custom format fuzzer template created!"
    echo_warning "Edit src/main.rs to implement your format parser"
}

# Network protocol fuzzing
fuzz_network_protocol() {
    echo_header "Fuzzing Network Protocol"

    read -p "Enter protocol name (e.g., HTTP, DNS, custom): " protocol_name

    FUZZ_DIR="$FUZZ_BASE_DIR/${protocol_name}_protocol_fuzz"
    mkdir -p "$FUZZ_DIR"/{corpus,findings}

    cd "$FUZZ_DIR"
    cargo init --name "fuzz_${protocol_name}" --bin
    cd "fuzz_${protocol_name}"

    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_protocol"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;

fn parse_protocol_message(data: &[u8]) -> Result<(), &'static str> {
    if data.is_empty() {
        return Err("Empty message");
    }

    // TODO: Implement your protocol parser
    // Example structure:
    // - Parse header
    // - Validate checksums
    // - Parse payload
    // - Handle different message types

    Ok(())
}

fn main() {
    fuzz(|data: &[u8]| {
        let _ = parse_protocol_message(data);
    });
}
EOF

    echo_success "Protocol fuzzer template created!"
}

# Create wrapper for binary with different input methods
create_binary_wrapper() {
    local fuzz_dir=$1
    local input_method=$2

    case $input_method in
        1) # stdin
            cat > "$fuzz_dir/wrapper.sh" << 'EOF'
#!/bin/bash
cat "$1" | ./target_binary 2>&1
EOF
            ;;
        2) # file argument
            cat > "$fuzz_dir/wrapper.sh" << 'EOF'
#!/bin/bash
./target_binary "$1" 2>&1
EOF
            ;;
        3) # command args
            cat > "$fuzz_dir/wrapper.sh" << 'EOF'
#!/bin/bash
./target_binary $(cat "$1") 2>&1
EOF
            ;;
    esac

    chmod +x "$fuzz_dir/wrapper.sh"
}

# Create run script
create_run_script() {
    local fuzz_dir=$1
    local target_binary=$2

    cat > "$fuzz_dir/run_fuzzer.sh" << EOF
#!/bin/bash
# AFL Fuzzing Run Script

set -e

FUZZ_DIR="$fuzz_dir"
TARGET="$target_binary"
CORPUS="\$FUZZ_DIR/corpus/initial"
OUTPUT="\$FUZZ_DIR/findings"

# Check if corpus exists and has files
if [ ! -d "\$CORPUS" ] || [ -z "\$(ls -A \$CORPUS)" ]; then
    echo "Error: Corpus directory is empty or doesn't exist"
    echo "Add sample inputs to: \$CORPUS"
    exit 1
fi

# Check if target exists
if [ ! -f "\$TARGET" ]; then
    echo "Error: Target binary not found: \$TARGET"
    exit 1
fi

echo "Starting AFL fuzzer..."
echo "Target: \$TARGET"
echo "Corpus: \$CORPUS"
echo "Output: \$OUTPUT"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Run AFL
cd "\$FUZZ_DIR"
AFL_NO_FORKSRV=1 cargo afl fuzz \\
    -i "\$CORPUS" \\
    -o "\$OUTPUT" \\
    -m $AFL_MEMORY \\
    -t $AFL_TIMEOUT \\
    "\$TARGET"
EOF

    chmod +x "$fuzz_dir/run_fuzzer.sh"
}

# Create binary run script
create_binary_run_script() {
    local fuzz_dir=$1
    local input_method=$2

    cat > "$fuzz_dir/run_fuzzer.sh" << EOF
#!/bin/bash
set -e

FUZZ_DIR="$fuzz_dir"
CORPUS="\$FUZZ_DIR/corpus/initial"
OUTPUT="\$FUZZ_DIR/findings"
WRAPPER="\$FUZZ_DIR/wrapper.sh"

echo "Starting AFL fuzzer for binary..."
echo "Corpus: \$CORPUS"
echo "Output: \$OUTPUT"
echo ""

cd "\$FUZZ_DIR"

# For black-box binary fuzzing without instrumentation
afl-fuzz \\
    -i "\$CORPUS" \\
    -o "\$OUTPUT" \\
    -m $AFL_MEMORY \\
    -t $AFL_TIMEOUT \\
    -n \\
    "\$WRAPPER" @@
EOF

    chmod +x "$fuzz_dir/run_fuzzer.sh"
}

# Create monitoring script
create_monitoring_script() {
    local fuzz_dir=$1

    cat > "$fuzz_dir/monitor.sh" << 'EOF'
#!/bin/bash
# AFL Fuzzing Monitor

FUZZ_DIR="$(dirname "$0")"
OUTPUT="$FUZZ_DIR/findings"

if [ ! -d "$OUTPUT" ]; then
    echo "No fuzzing output found. Have you started fuzzing yet?"
    exit 1
fi

echo "╔═══════════════════════════════════════════════╗"
echo "║         AFL Fuzzing Monitor                   ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# Show stats
if [ -f "$OUTPUT/fuzzer_stats" ]; then
    echo "📊 Fuzzer Statistics:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    start_time=$(grep "start_time" "$OUTPUT/fuzzer_stats" | cut -d: -f2 | tr -d ' ')
    current_time=$(date +%s)
    runtime=$((current_time - start_time))
    runtime_hours=$((runtime / 3600))
    runtime_mins=$(((runtime % 3600) / 60))

    echo "⏱️  Runtime: ${runtime_hours}h ${runtime_mins}m"
    echo "🔄 Cycles: $(grep "cycles_done" "$OUTPUT/fuzzer_stats" | cut -d: -f2 | tr -d ' ')"
    echo "📈 Paths: $(grep "paths_total" "$OUTPUT/fuzzer_stats" | cut -d: -f2 | tr -d ' ')"
    echo "⚡ Speed: $(grep "execs_per_sec" "$OUTPUT/fuzzer_stats" | cut -d: -f2 | tr -d ' ') exec/s"
    echo ""
fi

# Count crashes and hangs
crashes=$(find "$OUTPUT" -path "*/crashes/*" -type f ! -name "README.txt" 2>/dev/null | wc -l)
hangs=$(find "$OUTPUT" -path "*/hangs/*" -type f ! -name "README.txt" 2>/dev/null | wc -l)

echo "🐛 Findings:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💥 Crashes: $crashes"
echo "⏸️  Hangs: $hangs"
echo ""

if [ $crashes -gt 0 ]; then
    echo "🔍 Recent Crashes:"
    find "$OUTPUT" -path "*/crashes/*" -type f ! -name "README.txt" -printf "%T@ %p\n" 2>/dev/null | \
        sort -rn | head -5 | cut -d' ' -f2- | while read crash; do
        size=$(stat -f%z "$crash" 2>/dev/null || stat -c%s "$crash" 2>/dev/null)
        echo "  • $(basename "$crash") (${size} bytes)"
    done
    echo ""
fi

echo "📁 Directories:"
echo "  Corpus:   $FUZZ_DIR/corpus/initial"
echo "  Findings: $OUTPUT"
echo "  Crashes:  $OUTPUT/crashes"
echo "  Hangs:    $OUTPUT/hangs"
echo ""

echo "💡 Commands:"
echo "  Minimize crash:  cargo afl tmin -i $OUTPUT/crashes/id:XXX -o min.bin ./target"
echo "  Replay crash:    cat $OUTPUT/crashes/id:XXX | ./target"
echo "  View stats:      cat $OUTPUT/fuzzer_stats"
EOF

    chmod +x "$fuzz_dir/monitor.sh"
}

# Create crash analysis script
create_crash_analysis_script() {
    local fuzz_dir=$1
    local target=$2

    cat > "$fuzz_dir/analyze_crashes.sh" << EOF
#!/bin/bash
# Crash Analysis Script

FUZZ_DIR="$fuzz_dir"
TARGET="$target"
CRASHES_DIR="\$FUZZ_DIR/findings/crashes"
OUTPUT_DIR="\$FUZZ_DIR/crashes_minimized"

if [ ! -d "\$CRASHES_DIR" ]; then
    echo "No crashes directory found"
    exit 1
fi

mkdir -p "\$OUTPUT_DIR"

echo "Analyzing crashes..."
echo ""

# Count crashes
crash_count=\$(find "\$CRASHES_DIR" -type f ! -name "README.txt" | wc -l)
echo "Total crashes: \$crash_count"

if [ \$crash_count -eq 0 ]; then
    echo "No crashes to analyze"
    exit 0
fi

# Minimize each crash
echo ""
echo "Minimizing crashes..."

find "\$CRASHES_DIR" -type f ! -name "README.txt" | while read crash; do
    crash_name=\$(basename "\$crash")
    echo "  Minimizing: \$crash_name"

    cargo afl tmin \\
        -i "\$crash" \\
        -o "\$OUTPUT_DIR/\${crash_name}_minimized" \\
        "\$TARGET" 2>&1 | grep -E "(bytes|reduced)"
done

echo ""
echo "Minimized crashes saved to: \$OUTPUT_DIR"
echo ""
echo "To replay a crash:"
echo "  cat \$OUTPUT_DIR/XXX_minimized | \$TARGET"
EOF

    chmod +x "$fuzz_dir/analyze_crashes.sh"
}

# Create parallel fuzzing script
create_parallel_fuzzing_script() {
    local fuzz_dir=$1
    local target=$2

    cat > "$fuzz_dir/run_parallel.sh" << EOF
#!/bin/bash
# Parallel Fuzzing Script

FUZZ_DIR="$fuzz_dir"
TARGET="$target"
CORPUS="\$FUZZ_DIR/corpus/initial"
OUTPUT="\$FUZZ_DIR/findings"
JOBS=$PARALLEL_JOBS

echo "Starting \$JOBS parallel fuzzing instances..."

# Master instance
echo "Starting master fuzzer..."
AFL_NO_FORKSRV=1 cargo afl fuzz \\
    -i "\$CORPUS" \\
    -o "\$OUTPUT" \\
    -M fuzzer01 \\
    "\$TARGET" &

sleep 2

# Slave instances
for i in \$(seq 2 \$JOBS); do
    fuzzer_id=\$(printf "fuzzer%02d" \$i)
    echo "Starting slave fuzzer: \$fuzzer_id"

    AFL_NO_FORKSRV=1 cargo afl fuzz \\
        -i "\$CORPUS" \\
        -o "\$OUTPUT" \\
        -S "\$fuzzer_id" \\
        "\$TARGET" &

    sleep 1
done

echo ""
echo "All fuzzing instances started!"
echo "Monitor with: cargo afl whatsup \$OUTPUT"
echo ""
echo "To stop all fuzzers: pkill -9 afl-fuzz"

wait
EOF

    chmod +x "$fuzz_dir/run_parallel.sh"
}

# Document fuzzer fuzzing template
create_document_fuzzer() {
    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_document"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"
# Add document parsing libraries here

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // TODO: Add document parser
        // Example for PDF:
        // if let Ok(doc) = pdf_parser::parse(data) {
        //     let _ = doc.page_count();
        // }
    });
}
EOF

    echo_success "Document fuzzer template created!"
}

# Media fuzzer template
create_media_fuzzer() {
    cat > Cargo.toml << 'EOF'
[package]
name = "fuzz_media"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

    cat > src/main.rs << 'EOF'
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // TODO: Add media decoder
        // Write data to temp file and try to decode
    });
}
EOF

    echo_success "Media fuzzer template created!"
}

# Main execution
main() {
    display_banner
    check_afl_installed

    # Parse arguments
    case "${1:-}" in
        --source)
            project_path="${2:-}"
            if [ -z "$project_path" ]; then
                echo_error "Please provide path to source"
                exit 1
            fi
            fuzz_rust_project
            ;;
        --binary)
            binary_path="${2:-}"
            if [ -z "$binary_path" ]; then
                echo_error "Please provide path to binary"
                exit 1
            fi
            fuzz_binary
            ;;
        --interactive|-i)
            interactive_mode
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --source PATH      Fuzz a Rust project at PATH"
            echo "  --binary PATH      Fuzz an existing binary at PATH"
            echo "  --interactive, -i  Interactive mode (recommended)"
            echo "  --help, -h         Show this help"
            echo ""
            echo "Environment variables:"
            echo "  FUZZ_BASE_DIR      Base directory for fuzzing (default: ~/fuzzing_workspace)"
            echo "  AFL_TIMEOUT        Timeout in ms (default: 5000)"
            echo "  AFL_MEMORY         Memory limit in MB (default: 512)"
            echo "  PARALLEL_JOBS      Number of parallel fuzzers (default: 4)"
            ;;
        *)
            interactive_mode
            ;;
    esac
}

main "$@"
