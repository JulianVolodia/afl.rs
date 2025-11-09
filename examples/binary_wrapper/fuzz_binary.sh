#!/bin/bash
#
# Example: Fuzzing a Binary Executable
#
# This script demonstrates how to fuzz a binary you don't have source for
#

set -e

BINARY_PATH="${1:-./target_binary}"
CORPUS_DIR="${2:-./corpus}"
FINDINGS_DIR="${3:-./findings}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[✓]${NC} $1"; }
echo_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check if binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo_error "Binary not found: $BINARY_PATH"
    echo_info "Usage: $0 <binary_path> [corpus_dir] [findings_dir]"
    exit 1
fi

if [ ! -x "$BINARY_PATH" ]; then
    echo_error "File is not executable: $BINARY_PATH"
    exit 1
fi

echo_info "Binary Fuzzing Setup"
echo_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo_info "Binary:   $BINARY_PATH"
echo_info "Corpus:   $CORPUS_DIR"
echo_info "Findings: $FINDINGS_DIR"
echo ""

# Create directories
mkdir -p "$CORPUS_DIR" "$FINDINGS_DIR"

# Detect input method by testing the binary
echo_info "Detecting input method..."

# Test 1: Does it read from stdin?
if echo "test" | timeout 1 "$BINARY_PATH" &>/dev/null; then
    INPUT_METHOD="stdin"
    echo_success "Binary accepts stdin input"
elif timeout 1 "$BINARY_PATH" --help &>/dev/null; then
    INPUT_METHOD="args"
    echo_success "Binary accepts command-line arguments"
else
    echo_info "Cannot auto-detect input method"
    echo "How does the binary accept input?"
    echo "  1) From stdin (cat file | ./binary)"
    echo "  2) From file argument (./binary file.txt)"
    echo "  3) From command-line arguments (./binary <args>)"
    read -p "Select [1-3]: " choice

    case $choice in
        1) INPUT_METHOD="stdin" ;;
        2) INPUT_METHOD="file" ;;
        3) INPUT_METHOD="args" ;;
        *) echo_error "Invalid choice"; exit 1 ;;
    esac
fi

# Create wrapper script based on input method
WRAPPER_SCRIPT="./wrapper_$(basename $BINARY_PATH).sh"

case $INPUT_METHOD in
    stdin)
        cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash
# Wrapper for stdin input
cat "$1" | exec "${BINARY_PATH}" 2>&1
EOF
        ;;

    file)
        cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash
# Wrapper for file argument input
exec "${BINARY_PATH}" "$1" 2>&1
EOF
        ;;

    args)
        cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash
# Wrapper for command-line arguments
exec "${BINARY_PATH}" "$(cat "$1")" 2>&1
EOF
        ;;
esac

# Make wrapper executable
chmod +x "$WRAPPER_SCRIPT"
echo_success "Created wrapper: $WRAPPER_SCRIPT"

# Add BINARY_PATH to wrapper
sed -i.bak "s|\${BINARY_PATH}|$BINARY_PATH|g" "$WRAPPER_SCRIPT"
rm "${WRAPPER_SCRIPT}.bak"

# Create sample corpus if empty
if [ -z "$(ls -A $CORPUS_DIR 2>/dev/null)" ]; then
    echo_info "Creating sample corpus..."
    echo "test" > "$CORPUS_DIR/test1.txt"
    echo "hello world" > "$CORPUS_DIR/test2.txt"
    printf '\x00\x01\x02\x03' > "$CORPUS_DIR/binary1.bin"
    dd if=/dev/urandom bs=64 count=1 2>/dev/null > "$CORPUS_DIR/random1.bin"
    echo_success "Created 4 sample inputs"
    echo_info "Add more representative inputs to: $CORPUS_DIR"
fi

# Check if afl-fuzz is available
if ! command -v afl-fuzz &> /dev/null; then
    echo_error "afl-fuzz not found!"
    echo_info "The binary needs to be instrumented for best results."
    echo_info "For black-box fuzzing, install AFL:"
    echo_info "  git clone https://github.com/google/AFL"
    echo_info "  cd AFL && make"
    exit 1
fi

# Create run script
RUN_SCRIPT="./run_fuzz_$(basename $BINARY_PATH).sh"

cat > "$RUN_SCRIPT" << EOF
#!/bin/bash
# AFL Fuzzing Run Script for Binary

set -e

echo "Starting AFL fuzzer for binary..."
echo "Binary:   $BINARY_PATH"
echo "Wrapper:  $WRAPPER_SCRIPT"
echo "Corpus:   $CORPUS_DIR"
echo "Findings: $FINDINGS_DIR"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Black-box fuzzing (no instrumentation)
# Use -n flag for non-instrumented binaries
afl-fuzz \\
    -i "$CORPUS_DIR" \\
    -o "$FINDINGS_DIR" \\
    -m none \\
    -t 5000 \\
    -n \\
    "$WRAPPER_SCRIPT" @@
EOF

chmod +x "$RUN_SCRIPT"
echo_success "Created run script: $RUN_SCRIPT"

echo ""
echo_success "Setup complete!"
echo_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo_info "Next steps:"
echo "  1. Add sample inputs to: $CORPUS_DIR"
echo "  2. Start fuzzing: $RUN_SCRIPT"
echo "  3. Monitor findings: ls -la $FINDINGS_DIR/crashes/"
echo ""
echo_info "For better results, recompile the binary with AFL instrumentation:"
echo "  CC=afl-gcc make"
echo "  or: CC=afl-clang make"
