#!/bin/bash
#
# Advanced AFL Fuzzing Monitor
#
# Monitors fuzzing campaigns and provides detailed analytics
#

set -e

# Configuration
FINDINGS_DIR="${1:-./findings}"
REFRESH_INTERVAL="${2:-5}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Check if findings directory exists
if [ ! -d "$FINDINGS_DIR" ]; then
    echo -e "${RED}Error: Findings directory not found: $FINDINGS_DIR${NC}"
    echo "Usage: $0 [findings_dir] [refresh_interval]"
    exit 1
fi

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    else
        echo "$((bytes / 1048576))MB"
    fi
}

# Function to format duration
format_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local mins=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $days -gt 0 ]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h ${mins}m ${secs}s"
    elif [ $mins -gt 0 ]; then
        echo "${mins}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Function to get fuzzer stats
get_stat() {
    local stat_name=$1
    local stats_file=$2
    grep "^${stat_name}" "$stats_file" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "0"
}

# Function to display banner
display_banner() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║              AFL Fuzzing Dashboard v2.0                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
}

# Function to display fuzzer status
display_fuzzer_status() {
    local stats_file="$1"

    if [ ! -f "$stats_file" ]; then
        echo -e "${YELLOW}⚠ Fuzzer not running or no stats available${NC}"
        return
    fi

    # Parse stats
    local start_time=$(get_stat "start_time" "$stats_file")
    local last_update=$(get_stat "last_update" "$stats_file")
    local cycles_done=$(get_stat "cycles_done" "$stats_file")
    local execs_done=$(get_stat "execs_done" "$stats_file")
    local execs_per_sec=$(get_stat "execs_per_sec" "$stats_file")
    local paths_total=$(get_stat "paths_total" "$stats_file")
    local paths_found=$(get_stat "paths_found" "$stats_file")
    local paths_imported=$(get_stat "paths_imported" "$stats_file")
    local max_depth=$(get_stat "max_depth" "$stats_file")
    local cur_path=$(get_stat "cur_path" "$stats_file")
    local pending_favs=$(get_stat "pending_favs" "$stats_file")
    local pending_total=$(get_stat "pending_total" "$stats_file")
    local stability=$(get_stat "stability" "$stats_file")
    local bitmap_cvg=$(get_stat "bitmap_cvg" "$stats_file")
    local unique_crashes=$(get_stat "unique_crashes" "$stats_file")
    local unique_hangs=$(get_stat "unique_hangs" "$stats_file")
    local last_path=$(get_stat "last_path" "$stats_file")
    local last_crash=$(get_stat "last_crash" "$stats_file")
    local last_hang=$(get_stat "last_hang" "$stats_file")

    # Calculate runtime
    local current_time=$(date +%s)
    local runtime=$((current_time - start_time))
    local time_since_update=$((current_time - last_update))

    # Status indicator
    if [ $time_since_update -lt 10 ]; then
        local status="${GREEN}● RUNNING${NC}"
    elif [ $time_since_update -lt 60 ]; then
        local status="${YELLOW}● SLOW${NC}"
    else
        local status="${RED}● STALLED${NC}"
    fi

    echo -e "${CYAN}┌─ Fuzzer Status ────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Status: $status"
    echo -e "${CYAN}│${NC} Runtime: $(format_duration $runtime)"
    echo -e "${CYAN}│${NC} Cycles: ${cycles_done}"
    echo -e "${CYAN}│${NC} Speed: ${execs_per_sec} exec/sec"
    echo -e "${CYAN}│${NC} Total Executions: ${execs_done}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Coverage stats
    echo -e "${CYAN}┌─ Coverage ─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Total Paths: ${paths_total}"
    echo -e "${CYAN}│${NC} New Paths: ${paths_found}"
    echo -e "${CYAN}│${NC} Imported: ${paths_imported}"
    echo -e "${CYAN}│${NC} Max Depth: ${max_depth}"
    echo -e "${CYAN}│${NC} Bitmap Coverage: ${bitmap_cvg}"
    echo -e "${CYAN}│${NC} Stability: ${stability}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Findings
    local crashes_color=$GREEN
    if [ $unique_crashes -gt 0 ]; then
        crashes_color=$RED
    fi

    local hangs_color=$GREEN
    if [ $unique_hangs -gt 0 ]; then
        hangs_color=$YELLOW
    fi

    echo -e "${CYAN}┌─ Findings ─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${crashes_color}Crashes: ${unique_crashes}${NC}"

    if [ $last_crash -gt 0 ]; then
        local time_since_crash=$((current_time - last_crash))
        echo -e "${CYAN}│${NC}   Last: $(format_duration $time_since_crash) ago"
    fi

    echo -e "${CYAN}│${NC} ${hangs_color}Hangs: ${unique_hangs}${NC}"

    if [ $last_hang -gt 0 ]; then
        local time_since_hang=$((current_time - last_hang))
        echo -e "${CYAN}│${NC}   Last: $(format_duration $time_since_hang) ago"
    fi

    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Progress
    local pending_pct=0
    if [ $pending_total -gt 0 ]; then
        pending_pct=$(( (pending_total - pending_favs) * 100 / pending_total ))
    fi

    echo -e "${CYAN}┌─ Progress ─────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Current Input: ${cur_path} / ${paths_total}"
    echo -e "${CYAN}│${NC} Pending: ${pending_total} (${pending_favs} favored)"
    echo -e "${CYAN}│${NC} Progress: ${pending_pct}%"

    # Progress bar
    local bar_width=40
    local filled=$((pending_pct * bar_width / 100))
    local empty=$((bar_width - filled))

    echo -ne "${CYAN}│${NC} ["
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    for ((i=0; i<empty; i++)); do echo -n "░"; done
    echo "]"

    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
}

# Function to display crashes
display_crashes() {
    local crashes_dir="$1/crashes"

    echo ""
    echo -e "${MAGENTA}┌─ Recent Crashes ───────────────────────────────────────┐${NC}"

    if [ ! -d "$crashes_dir" ]; then
        echo -e "${MAGENTA}│${NC} No crashes directory found"
        echo -e "${MAGENTA}└────────────────────────────────────────────────────────┘${NC}"
        return
    fi

    local crash_count=$(find "$crashes_dir" -type f ! -name "README.txt" | wc -l)

    if [ $crash_count -eq 0 ]; then
        echo -e "${MAGENTA}│${NC} ${GREEN}No crashes found ✓${NC}"
    else
        echo -e "${MAGENTA}│${NC} ${RED}Total: $crash_count crashes${NC}"
        echo -e "${MAGENTA}│${NC}"

        # Show recent crashes
        find "$crashes_dir" -type f ! -name "README.txt" -printf "%T@ %s %p\n" | \
            sort -rn | head -5 | while read timestamp size path; do
            local crash_name=$(basename "$path")
            local crash_size=$(format_bytes $size)
            local sig=$(echo "$crash_name" | grep -oP 'sig:\K\d+' || echo "?")

            # Determine signal name
            local sig_name="UNKNOWN"
            case $sig in
                6) sig_name="SIGABRT" ;;
                11) sig_name="SIGSEGV" ;;
                8) sig_name="SIGFPE" ;;
                4) sig_name="SIGILL" ;;
            esac

            echo -e "${MAGENTA}│${NC}   • ${crash_size} - ${sig_name} - ${crash_name:0:40}..."
        done
    fi

    echo -e "${MAGENTA}└────────────────────────────────────────────────────────┘${NC}"
}

# Function to display hangs
display_hangs() {
    local hangs_dir="$1/hangs"

    echo ""
    echo -e "${YELLOW}┌─ Recent Hangs ─────────────────────────────────────────┐${NC}"

    if [ ! -d "$hangs_dir" ]; then
        echo -e "${YELLOW}│${NC} No hangs directory found"
        echo -e "${YELLOW}└────────────────────────────────────────────────────────┘${NC}"
        return
    fi

    local hang_count=$(find "$hangs_dir" -type f ! -name "README.txt" | wc -l)

    if [ $hang_count -eq 0 ]; then
        echo -e "${YELLOW}│${NC} ${GREEN}No hangs found ✓${NC}"
    else
        echo -e "${YELLOW}│${NC} Total: $hang_count hangs"
        echo -e "${YELLOW}│${NC}"

        # Show recent hangs
        find "$hangs_dir" -type f ! -name "README.txt" -printf "%T@ %s %p\n" | \
            sort -rn | head -3 | while read timestamp size path; do
            local hang_name=$(basename "$path")
            local hang_size=$(format_bytes $size)
            echo -e "${YELLOW}│${NC}   • ${hang_size} - ${hang_name:0:45}..."
        done
    fi

    echo -e "${YELLOW}└────────────────────────────────────────────────────────┘${NC}"
}

# Function to display performance stats
display_performance() {
    local stats_file="$1"

    if [ ! -f "$stats_file" ]; then
        return
    fi

    local execs_per_sec=$(get_stat "execs_per_sec" "$stats_file")
    local execs_ps_last_min=$(get_stat "execs_ps_last_min" "$stats_file")

    echo ""
    echo -e "${BLUE}┌─ Performance ──────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} Current Speed: ${execs_per_sec} exec/sec"
    echo -e "${BLUE}│${NC} Last Minute Avg: ${execs_ps_last_min} exec/sec"

    # Performance indicator
    if [ $execs_per_sec -gt 1000 ]; then
        echo -e "${BLUE}│${NC} Performance: ${GREEN}Excellent ⚡${NC}"
    elif [ $execs_per_sec -gt 500 ]; then
        echo -e "${BLUE}│${NC} Performance: ${GREEN}Good ✓${NC}"
    elif [ $execs_per_sec -gt 100 ]; then
        echo -e "${BLUE}│${NC} Performance: ${YELLOW}Average ⚠${NC}"
    else
        echo -e "${BLUE}│${NC} Performance: ${RED}Poor ✗${NC}"
        echo -e "${BLUE}│${NC}   ${RED}Tip: Consider simplifying your fuzz target${NC}"
    fi

    echo -e "${BLUE}└────────────────────────────────────────────────────────┘${NC}"
}

# Function to display tips
display_tips() {
    local stats_file="$1"

    if [ ! -f "$stats_file" ]; then
        return
    fi

    local stability=$(get_stat "stability" "$stats_file")
    local execs_per_sec=$(get_stat "execs_per_sec" "$stats_file")
    local pending_favs=$(get_stat "pending_favs" "$stats_file")
    local unique_crashes=$(get_stat "unique_crashes" "$stats_file")

    echo ""
    echo -e "${CYAN}┌─ Tips & Recommendations ───────────────────────────────┐${NC}"

    # Stability check
    local stability_num=$(echo "$stability" | sed 's/%//')
    if [ "$stability_num" -lt 90 ]; then
        echo -e "${CYAN}│${NC} ${YELLOW}⚠ Low stability ($stability)${NC}"
        echo -e "${CYAN}│${NC}   Consider: Use AFL_NO_ARITH=1 or better corpus"
    fi

    # Performance check
    if [ $execs_per_sec -lt 100 ]; then
        echo -e "${CYAN}│${NC} ${YELLOW}⚠ Slow execution speed${NC}"
        echo -e "${CYAN}│${NC}   Try: Simplify target, use release build"
    fi

    # Pending work
    if [ $pending_favs -gt 1000 ]; then
        echo -e "${CYAN}│${NC} ${BLUE}ℹ Many pending inputs ($pending_favs)${NC}"
        echo -e "${CYAN}│${NC}   This is normal for complex targets"
    fi

    # Crashes found
    if [ $unique_crashes -gt 0 ]; then
        echo -e "${CYAN}│${NC} ${RED}❗Crashes found! Next steps:${NC}"
        echo -e "${CYAN}│${NC}   1. Stop fuzzer and analyze crashes"
        echo -e "${CYAN}│${NC}   2. cargo afl tmin -i crash -o min ./target"
        echo -e "${CYAN}│${NC}   3. cat min | ./target (to reproduce)"
    fi

    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
}

# Function to display footer
display_footer() {
    echo ""
    echo -e "${CYAN}Monitoring: ${NC}$FINDINGS_DIR"
    echo -e "${CYAN}Updated:    ${NC}$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}Refresh:    ${NC}${REFRESH_INTERVAL}s (Press Ctrl+C to exit)"
}

# Main monitoring loop
main() {
    while true; do
        display_banner

        # Find fuzzer stats (supports multiple fuzzers)
        local stats_files=$(find "$FINDINGS_DIR" -name "fuzzer_stats" 2>/dev/null)

        if [ -z "$stats_files" ]; then
            echo -e "${YELLOW}No fuzzer stats found in $FINDINGS_DIR${NC}"
            echo "Make sure AFL is running and writing to this directory"
            sleep $REFRESH_INTERVAL
            continue
        fi

        # Display stats for first fuzzer (or master)
        local primary_stats=$(echo "$stats_files" | head -1)
        display_fuzzer_status "$primary_stats"

        # Display crashes and hangs
        local findings_base=$(dirname "$primary_stats")
        display_crashes "$findings_base"
        display_hangs "$findings_base"

        # Display performance
        display_performance "$primary_stats"

        # Display tips
        display_tips "$primary_stats"

        # Footer
        display_footer

        # Wait for refresh
        sleep $REFRESH_INTERVAL
    done
}

# Handle Ctrl+C
trap 'echo -e "\n${GREEN}Monitoring stopped${NC}"; exit 0' INT

# Start monitoring
main
