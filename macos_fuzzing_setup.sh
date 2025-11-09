#!/bin/bash
#
# macOS AFL Fuzzing Setup Script
#
# This script sets up AFL (American Fuzzy Lop) for fuzzing on macOS
# and prepares the environment for security research and vulnerability discovery.
#
# Usage: ./macos_fuzzing_setup.sh
#
# Prerequisites:
# - Xcode Command Line Tools
# - Homebrew (recommended)
# - Rust toolchain

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo_info "Starting AFL macOS Setup"
echo_info "======================================="

# 1. Check system requirements
echo_info "Checking system requirements..."

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo_error "This script is for macOS only. Detected: $(uname)"
    exit 1
fi

echo_success "Running on macOS $(sw_vers -productVersion)"

# 2. Check for Xcode Command Line Tools
echo_info "Checking for Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    echo_warning "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo_info "Please complete the Xcode installation and re-run this script."
    exit 1
else
    echo_success "Xcode Command Line Tools found at $(xcode-select -p)"
fi

# 3. Check for Rust
echo_info "Checking for Rust installation..."
if ! command_exists rustc; then
    echo_warning "Rust not found. Installing via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo_success "Rust found: $(rustc --version)"
fi

# 4. Check for LLVM/Clang
echo_info "Checking for LLVM/Clang..."
if ! command_exists clang; then
    echo_error "Clang not found. Please install Xcode or LLVM via Homebrew."
    exit 1
else
    echo_success "Clang found: $(clang --version | head -n1)"
fi

# 5. Disable macOS crash reporter (required for AFL)
echo_info "Disabling macOS crash reporter..."
echo_warning "This requires sudo privileges and will disable crash reporting system-wide."
read -p "Do you want to disable the crash reporter? (required for AFL) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check current status
    if launchctl list | grep -q "com.apple.ReportCrash"; then
        sudo launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist 2>/dev/null || true
        sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.ReportCrash.Root.plist 2>/dev/null || true
        echo_success "Crash reporter disabled"
    else
        echo_info "Crash reporter already disabled"
    fi

    # Verify it's disabled
    if launchctl list | grep -q "com.apple.ReportCrash"; then
        echo_warning "Crash reporter may still be running. You may need to reboot."
    fi
else
    echo_warning "Crash reporter not disabled. AFL may not work correctly."
    echo_warning "You can disable it later with:"
    echo "  sudo launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist"
    echo "  sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.ReportCrash.Root.plist"
fi

# 6. Install afl.rs
echo_info "Installing afl.rs..."
if [ -d "/home/user/afl.rs" ]; then
    echo_info "Using local afl.rs repository..."
    cd /home/user/afl.rs
    cargo install --force --path .
else
    echo_info "Installing afl.rs from crates.io..."
    cargo install afl
fi

# Verify installation
if command_exists cargo-afl; then
    echo_success "cargo-afl installed successfully"
    cargo afl --version
else
    echo_error "cargo-afl installation failed"
    exit 1
fi

# 7. Create fuzzing workspace
echo_info "Creating fuzzing workspace..."
FUZZ_DIR="$HOME/afl_fuzzing_workspace"
mkdir -p "$FUZZ_DIR"/{targets,findings,corpus}

echo_success "Workspace created at: $FUZZ_DIR"

# 8. Create example fuzz target
echo_info "Creating example fuzz target..."
mkdir -p "$FUZZ_DIR/targets/example_target"
cd "$FUZZ_DIR/targets/example_target"

# Create Cargo.toml
cat > Cargo.toml << 'EOF'
[package]
name = "example_target"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.4"

[[bin]]
name = "fuzz_target"
path = "src/main.rs"
EOF

# Create fuzz target source
mkdir -p src
cat > src/main.rs << 'EOF'
use afl::fuzz;

fn main() {
    fuzz(|data: &[u8]| {
        // Example: Look for a specific pattern that triggers a "vulnerability"
        if data.len() < 6 {
            return;
        }

        if data[0] == b'F' &&
           data[1] == b'U' &&
           data[2] == b'Z' &&
           data[3] == b'Z' &&
           data[4] == b'!' &&
           data[5] == b'!' {
            // Simulate a crash/vulnerability
            panic!("Found vulnerability trigger!");
        }

        // Add your actual fuzzing target here
        // For example: parse_image(data), parse_protocol(data), etc.
    });
}
EOF

echo_success "Example target created"

# 9. Create initial test corpus
echo_info "Creating initial test corpus..."
CORPUS_DIR="$FUZZ_DIR/corpus/example"
mkdir -p "$CORPUS_DIR"
echo "test" > "$CORPUS_DIR/test1.txt"
echo "hello" > "$CORPUS_DIR/test2.txt"
echo "world" > "$CORPUS_DIR/test3.txt"

echo_success "Corpus created with sample inputs"

# 10. Build the example target
echo_info "Building example fuzz target..."
cd "$FUZZ_DIR/targets/example_target"
cargo afl build --release

if [ $? -eq 0 ]; then
    echo_success "Build successful"
else
    echo_error "Build failed"
    exit 1
fi

# 11. Create helper scripts
echo_info "Creating helper scripts..."

# Fuzzing start script
cat > "$FUZZ_DIR/start_fuzzing.sh" << 'EOF'
#!/bin/bash
# Start AFL fuzzing

TARGET_NAME="${1:-example_target}"
TARGET_DIR="$HOME/afl_fuzzing_workspace/targets/$TARGET_NAME"
CORPUS_DIR="$HOME/afl_fuzzing_workspace/corpus/example"
OUTPUT_DIR="$HOME/afl_fuzzing_workspace/findings/$TARGET_NAME"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: $TARGET_DIR"
    exit 1
fi

cd "$TARGET_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Starting AFL fuzzer..."
echo "Target: $TARGET_NAME"
echo "Corpus: $CORPUS_DIR"
echo "Output: $OUTPUT_DIR"
echo ""
echo "Press Ctrl+C to stop fuzzing"
echo ""

# Run AFL with macOS-specific settings
AFL_NO_FORKSRV=1 cargo afl fuzz \
    -i "$CORPUS_DIR" \
    -o "$OUTPUT_DIR" \
    target/release/fuzz_target
EOF
chmod +x "$FUZZ_DIR/start_fuzzing.sh"

# Crash analysis script
cat > "$FUZZ_DIR/analyze_crashes.sh" << 'EOF'
#!/bin/bash
# Analyze crashes found by AFL

TARGET_NAME="${1:-example_target}"
OUTPUT_DIR="$HOME/afl_fuzzing_workspace/findings/$TARGET_NAME"
CRASH_DIR="$OUTPUT_DIR/crashes"

if [ ! -d "$CRASH_DIR" ]; then
    echo "No crashes directory found at: $CRASH_DIR"
    exit 1
fi

echo "Analyzing crashes in: $CRASH_DIR"
echo "======================================="

CRASH_COUNT=$(find "$CRASH_DIR" -type f ! -name "README.txt" | wc -l)
echo "Total crashes found: $CRASH_COUNT"
echo ""

if [ $CRASH_COUNT -eq 0 ]; then
    echo "No crashes to analyze"
    exit 0
fi

# List unique crashes
echo "Unique crash files:"
find "$CRASH_DIR" -type f ! -name "README.txt" -exec basename {} \;
echo ""

# Offer to replay crashes
echo "To replay a crash, run:"
echo "  cat $CRASH_DIR/id:XXXXXX... | target/release/fuzz_target"
EOF
chmod +x "$FUZZ_DIR/analyze_crashes.sh"

echo_success "Helper scripts created"

# 12. Display setup summary
echo ""
echo_success "======================================="
echo_success "AFL Setup Complete!"
echo_success "======================================="
echo ""
echo_info "Workspace location: $FUZZ_DIR"
echo_info ""
echo_info "Quick Start:"
echo_info "  1. Build your target:    cd $FUZZ_DIR/targets/example_target && cargo afl build --release"
echo_info "  2. Start fuzzing:        $FUZZ_DIR/start_fuzzing.sh"
echo_info "  3. Analyze results:      $FUZZ_DIR/analyze_crashes.sh"
echo_info ""
echo_info "To create a new fuzz target:"
echo_info "  1. Copy example_target:  cp -r $FUZZ_DIR/targets/example_target $FUZZ_DIR/targets/my_target"
echo_info "  2. Edit src/main.rs to fuzz your code"
echo_info "  3. Build and run:        cd $FUZZ_DIR/targets/my_target && cargo afl build --release"
echo_info ""
echo_warning "Important Notes for macOS:"
echo_warning "  - AFL runs slower on macOS than Linux due to fork() semantics"
echo_warning "  - Use AFL_NO_FORKSRV=1 if you encounter issues (already set in start_fuzzing.sh)"
echo_warning "  - QEMU mode is not available on macOS"
echo_warning "  - For best performance, consider running Linux VM"
echo_info ""
echo_info "For fuzzing system libraries or macOS components:"
echo_info "  1. Create a fuzz harness that calls the target API"
echo_info "  2. Link against the system framework (e.g., -framework Security)"
echo_info "  3. Monitor for crashes, hangs, or assertion failures"
echo_info ""
echo_info "Responsible Disclosure:"
echo_info "  - Report macOS vulnerabilities to: https://support.apple.com/en-us/HT201220"
echo_info "  - Use Apple's Product Security team: product-security@apple.com"
echo_info "  - Allow 90 days for fix before public disclosure"
echo_info ""
echo_success "Happy Fuzzing! 🐛"
