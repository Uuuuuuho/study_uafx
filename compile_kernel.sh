#!/bin/bash
# Helper script to compile Linux kernel to LLVM bitcode for UAFX analysis
# Usage: ./compile_kernel.sh <kernel_source_dir> [config_type] [mode]
#   config_type: defconfig (default), tinyconfig, allnoconfig, or path to .config
#   mode: wllvm (default) | gllvm | auto
#
# This script will try to embed LLVM bitcode (.llvm_bc sections) into every
# object file so that a final vmlinux.bc can be produced via extract-bc/get-bc.
# If embedding fails, it will print detailed diagnostics and suggested fixes.

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <kernel_source_dir> [config_type] [mode]" >&2
    echo "  config_type: defconfig (default), tinyconfig, allnoconfig, or path to .config" >&2
    echo "  mode       : wllvm | gllvm | auto (default:auto)" >&2
    exit 1
fi

KERNEL_SRC="$1"
CONFIG_TYPE="${2:-defconfig}"
MODE="${3:-auto}"

if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory '$KERNEL_SRC' not found"
    exit 1
fi

echo "[*] Compiling Linux kernel to LLVM bitcode"
echo "[*] Kernel source : $KERNEL_SRC"
echo "[*] Config type   : $CONFIG_TYPE"
echo "[*] Mode          : $MODE"

# Ensure LLVM environment is set
if [ -z "$LLVM_ROOT" ]; then
    echo "[!] LLVM_ROOT not set. Please run: source env.sh"
    exit 1
fi

export LLVM_COMPILER=clang
export LLVM_COMPILER_PATH=$LLVM_ROOT/bin
# Increase verbosity of wllvm if used
export WLLVM_OUTPUT_LEVEL=INFO
# Help wllvm locate the real compilers explicitly
export REAL_CC=clang
export REAL_CXX=clang++

echo "[*] LLVM / Wrapper environment:"
echo "    LLVM_COMPILER       = $LLVM_COMPILER"
echo "    LLVM_COMPILER_PATH  = $LLVM_COMPILER_PATH"
echo "    WLLVM_OUTPUT_LEVEL  = $WLLVM_OUTPUT_LEVEL"
echo "    REAL_CC             = $REAL_CC"
echo "    REAL_CXX            = $REAL_CXX"

cd "$KERNEL_SRC"

# Configure kernel
echo "[*] Configuring kernel..."
if [ -f "$CONFIG_TYPE" ]; then
    echo "[*] Using custom config: $CONFIG_TYPE"
    cp "$CONFIG_TYPE" .config
    make olddefconfig
elif [ "$CONFIG_TYPE" = "defconfig" ] || [ "$CONFIG_TYPE" = "tinyconfig" ] || [ "$CONFIG_TYPE" = "allnoconfig" ]; then
    make "$CONFIG_TYPE"
else
    echo "[!] Unknown config type: $CONFIG_TYPE"
    echo "[!] Using defconfig instead"
    make defconfig
fi

# Clean previous build to ensure fresh compilation
echo "[*] Cleaning previous build..."
# Use mrproper instead of clean to avoid Documentation/Kbuild issue
# mrproper removes all generated files including .config, so we save/restore it
if [ -f ".config" ]; then
    cp .config .config.backup
    make mrproper || make clean || echo "[!] Clean failed, continuing anyway..."
    mv .config.backup .config
else
    make mrproper || make clean || echo "[!] Clean failed, continuing anyway..."
fi

# Decide wrapper based on MODE
WRAPPER_CC=""
WRAPPER_CXX=""
case "$MODE" in
  wllvm)
    WRAPPER_CC=wllvm; WRAPPER_CXX=wllvm++ ;;
  gllvm)
    WRAPPER_CC=gclang; WRAPPER_CXX=gclang++ ;;
  auto|*)
    if command -v gclang >/dev/null 2>&1; then
        WRAPPER_CC=gclang; WRAPPER_CXX=gclang++
        echo "[*] auto-mode: using gllvm (gclang)"
    elif command -v wllvm >/dev/null 2>&1; then
        WRAPPER_CC=wllvm; WRAPPER_CXX=wllvm++
        echo "[*] auto-mode: using wllvm"
    else
        echo "[!] Neither gclang nor wllvm found in PATH. Install one: pip3 install gllvm wllvm" >&2
        exit 1
    fi
    ;;
esac

if [ "$WRAPPER_CC" = "wllvm" ] && ! command -v extract-bc >/dev/null 2>&1; then
    echo "[!] extract-bc not found; wllvm installation may be incomplete" >&2
fi
if [ "$WRAPPER_CC" = "gclang" ] && ! command -v get-bc >/dev/null 2>&1; then
    echo "[!] get-bc not found; gllvm installation may be incomplete" >&2
fi

echo "[*] Wrapper selected: CC=$WRAPPER_CC CXX=$WRAPPER_CXX"

echo "[*] Performing a probe compilation to confirm bitcode embedding..."
TMP_PROBE=/tmp/uafx_bc_probe.c
cat > $TMP_PROBE <<'EOF_PROBE'
int probe_func(void){return 42;}
EOF_PROBE
set +e
$WRAPPER_CC -c $TMP_PROBE -o /tmp/uafx_bc_probe.o 2> /tmp/uafx_bc_probe.log
set -e
if readelf -S /tmp/uafx_bc_probe.o 2>/dev/null | grep -q ".llvm_bc"; then
    echo "[+] Probe object has .llvm_bc section (good)"
else
    echo "[!] Probe object missing .llvm_bc section. Wrapper may not embed bitcode." >&2
    echo "    Inspect /tmp/uafx_bc_probe.log for details." >&2
fi

echo "[*] Compiling kernel (this may take a while)..."
NUM_CORES=$(nproc)
echo "[*] Using $NUM_CORES cores"

MAKE_LOG=kernel_build.log
time make LLVM=1 \
     CC="$WRAPPER_CC" \
     HOSTCC=clang \
     HOSTCXX=clang++ \
     HOSTLD=ld.lld \
     HOSTAR=llvm-ar \
     -j"$NUM_CORES" 2>&1 | tee $MAKE_LOG

echo "[*] Kernel compilation finished. Log: $MAKE_LOG"

echo "[*] Sampling compiler invocations (first 10 CC lines):"
grep -E '^ *CC ' $MAKE_LOG | head -10 || true

echo "[*] Checking whether wrapper appeared in build log..."
if grep -q "$WRAPPER_CC" $MAKE_LOG; then
    echo "[+] Wrapper name '$WRAPPER_CC' found in build log."
else
    echo "[!] Wrapper name '$WRAPPER_CC' NOT found in build log; Kbuild may have bypassed it." >&2
fi

echo "[*] Scanning a few object files for embedded bitcode (.llvm_bc)..."
FOUND_OBJ=$(find . -type f -name '*.o' -exec sh -c 'readelf -S "$1" 2>/dev/null | grep -q ".llvm_bc" && echo "$1" && exit 0' _ {} \; | head -1)
if [ -n "$FOUND_OBJ" ]; then
    echo "[+] Found embedded bitcode in: $FOUND_OBJ"
else
    echo "[!] No .o with .llvm_bc section detected so far." >&2
    echo "    Possible causes: wrapper ignored, using LTO, or build stopped early." >&2
fi

# Extract bitcode
echo "[*] Extracting LLVM bitcode from vmlinux..."
if [ -f "vmlinux" ]; then
    echo "[*] vmlinux found, size: $(ls -lh vmlinux | awk '{print $5}')"
    
    # Verify that vmlinux has the .llvm_bc section
    echo "[*] Checking for .llvm_bc section..."
    if [ -z "$FOUND_OBJ" ]; then
        echo "[!] Skipping extract step early: no object with embedded bitcode located." >&2
        echo "    -> Re-run with: MODE=gllvm (preferred)" >&2
        echo "    -> Or try: make LLVM=1 CC=gclang clean && make LLVM=1 CC=gclang -j$(nproc)" >&2
    fi

    if command -v get-bc >/dev/null 2>&1; then
        echo "[*] Attempting unified extraction via get-bc ..."
        set +e; get-bc vmlinux; RC=$?; set -e
    elif command -v extract-bc >/dev/null 2>&1; then
        echo "[*] Attempting unified extraction via extract-bc ..."
        set +e; extract-bc vmlinux; RC=$?; set -e
    else
        echo "[!] Neither get-bc nor extract-bc available. Install gllvm or wllvm." >&2
        RC=1
    fi

    if [ $RC -ne 0 ]; then
        echo "[!] Extraction tool returned non-zero ($RC)." >&2
    fi
    
    if [ -f "vmlinux.bc" ]; then
        echo "[+] Success! vmlinux.bc created"
        ls -lh vmlinux.bc
        
        # Verify the bitcode file is valid
        if llvm-dis vmlinux.bc -o /dev/null 2>/dev/null; then
            echo "[+] Bitcode file is valid"
        else
            echo "[!] WARNING: Bitcode file may be corrupted"
        fi
        
        echo ""
        echo "[*] To analyze with UAFX, create an entry point config file and run:"
        echo "    ./run_nohup.sh $(pwd)/vmlinux.bc /path/to/conf_file"
        echo ""
        echo "[*] Or use the helper script to generate entry points:"
        echo "    ./gen_kernel_conf.sh $(pwd)/vmlinux.bc conf_syscalls __x64_sys_"
    else
        echo "[!] Failed to extract bitcode - vmlinux.bc was not created"
        echo ""
        echo "[*] Troubleshooting QUICK ACTIONS:"
        echo "    A. Switch to gllvm: pip3 install gllvm; ./compile_kernel.sh $KERNEL_SRC $CONFIG_TYPE gllvm" 
        echo "    B. Confirm wrapper usage: grep -m5 '$WRAPPER_CC' kernel_build.log" 
        echo "    C. Inspect first object: find . -name built-in.a | head -1" 
        echo "    D. Minimal test: (cd $KERNEL_SRC; make mrproper; make tinyconfig; ./compile_kernel.sh $KERNEL_SRC tinyconfig gllvm)"
        echo ""
        echo "[*] If still stuck, run: ./debug_kernel_bitcode.sh $KERNEL_SRC > diag.txt and review." 
        exit 1
    fi
else
    echo "[!] vmlinux not found. Compilation failed."
    echo "[*] Check kernel_build.log for compilation errors"
    exit 1
fi