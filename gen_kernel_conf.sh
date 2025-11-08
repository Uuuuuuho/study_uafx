#!/bin/bash
# Helper script to generate entry point configuration files for Linux kernel analysis
# Usage: ./gen_kernel_conf.sh <vmlinux.bc> <output_conf> [filter_pattern]

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <vmlinux.bc> <output_conf> [filter_pattern]"
    echo ""
    echo "Examples:"
    echo "  Generate all x64 syscalls:"
    echo "    $0 vmlinux.bc conf_all_syscalls __x64_sys_"
    echo ""
    echo "  Generate file-related syscalls:"
    echo "    $0 vmlinux.bc conf_file_syscalls '__x64_sys_(read|write|open|close)'"
    echo ""
    echo "  Generate network syscalls:"
    echo "    $0 vmlinux.bc conf_net_syscalls '__x64_sys_(socket|bind|connect|send|recv)'"
    exit 1
fi

BC_FILE="$1"
OUTPUT_CONF="$2"
FILTER="${3:-__x64_sys_}"

if [ ! -f "$BC_FILE" ]; then
    echo "Error: Bitcode file '$BC_FILE' not found"
    exit 1
fi

# Ensure LLVM tools are available
if [ -z "$LLVM_ROOT" ]; then
    echo "[!] LLVM_ROOT not set. Please run: source env.sh"
    exit 1
fi

echo "[*] Extracting entry points from $BC_FILE"
echo "[*] Filter pattern: $FILTER"

# Use llvm-nm to list symbols and filter for entry points
if echo "$FILTER" | grep -q '('; then
    # Filter is a regex pattern
    llvm-nm "$BC_FILE" | grep -E "$FILTER" | awk '{print $3}' | sort -u > "$OUTPUT_CONF"
else
    # Filter is a simple prefix
    llvm-nm "$BC_FILE" | grep "$FILTER" | awk '{print $3}' | sort -u > "$OUTPUT_CONF"
fi

NUM_ENTRIES=$(wc -l < "$OUTPUT_CONF")
echo "[+] Generated $OUTPUT_CONF with $NUM_ENTRIES entry points"
echo ""
echo "[*] First 10 entries:"
head -n 10 "$OUTPUT_CONF"

if [ "$NUM_ENTRIES" -gt 10 ]; then
    echo "... ($(($NUM_ENTRIES - 10)) more entries)"
fi

echo ""
echo "[*] To analyze with UAFX, run:"
echo "    ./run_nohup.sh $BC_FILE $OUTPUT_CONF"
