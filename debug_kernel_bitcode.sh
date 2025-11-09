#!/bin/bash
# Diagnostic script to check why bitcode extraction failed
# Usage: ./debug_kernel_bitcode.sh <kernel_source_dir>

if [ $# -lt 1 ]; then
    echo "Usage: $0 <kernel_source_dir>"
    exit 1
fi

KERNEL_SRC="$1"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Kernel Bitcode Extraction Diagnostics                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

cd "$KERNEL_SRC" || exit 1

echo "[1] Checking for vmlinux binary..."
if [ -f "vmlinux" ]; then
    echo "    ✓ vmlinux exists"
    ls -lh vmlinux
else
    echo "    ✗ vmlinux NOT found - compilation failed"
    exit 1
fi

echo ""
echo "[2] Checking for .llvm_bc section in vmlinux..."
if readelf -S vmlinux 2>/dev/null | grep -q ".llvm_bc"; then
    echo "    ✓ .llvm_bc section found"
    readelf -S vmlinux | grep ".llvm_bc"
else
    echo "    ✗ .llvm_bc section NOT found"
    echo "    This means vmlinux was not compiled with wllvm/gllvm"
fi

echo ""
echo "[3] Checking LLVM environment variables..."
echo "    LLVM_COMPILER=$LLVM_COMPILER"
echo "    LLVM_COMPILER_PATH=$LLVM_COMPILER_PATH"
echo "    LLVM_ROOT=$LLVM_ROOT"

if [ -z "$LLVM_COMPILER" ]; then
    echo "    ✗ LLVM_COMPILER not set"
else
    echo "    ✓ LLVM_COMPILER is set"
fi

echo ""
echo "[4] Checking for wllvm/gllvm installation..."
if command -v wllvm &> /dev/null; then
    echo "    ✓ wllvm found: $(which wllvm)"
else
    echo "    ✗ wllvm NOT found"
fi

if command -v gclang &> /dev/null; then
    echo "    ✓ gclang (gllvm) found: $(which gclang)"
else
    echo "    ✗ gclang (gllvm) NOT found"
fi

if command -v extract-bc &> /dev/null; then
    echo "    ✓ extract-bc found: $(which extract-bc)"
else
    echo "    ✗ extract-bc NOT found"
fi

if command -v get-bc &> /dev/null; then
    echo "    ✓ get-bc found: $(which get-bc)"
else
    echo "    ✗ get-bc NOT found"
fi

echo ""
echo "[5] Checking build log for compiler usage..."
if [ -f "kernel_build.log" ]; then
    echo "    Sample of CC commands from build log:"
    grep -E '^\s+CC\s+' kernel_build.log | head -5 | sed 's/^/    /'
    
    echo ""
    echo "    Checking if wllvm/gclang was actually used:"
    if grep -q "wllvm\|gclang" kernel_build.log; then
        echo "    ✓ Found wllvm/gclang in build log"
        grep -m 3 "wllvm\|gclang" kernel_build.log | sed 's/^/    /'
    else
        echo "    ✗ No wllvm/gclang found in build log"
        echo "    The kernel may have been compiled with regular clang"
    fi
else
    echo "    ✗ kernel_build.log not found"
fi

echo ""
echo "[6] Checking for .o files with embedded bitcode..."
OBJ_WITH_BC=$(find . -name "*.o" -type f -exec sh -c 'readelf -S "$1" 2>/dev/null | grep -q ".llvm_bc" && echo "$1"' _ {} \; 2>/dev/null | head -3)
if [ -n "$OBJ_WITH_BC" ]; then
    echo "    ✓ Found .o files with .llvm_bc section:"
    echo "$OBJ_WITH_BC" | sed 's/^/      /'
else
    echo "    ✗ No .o files found with .llvm_bc section"
    echo "    This confirms the build didn't use wllvm/gllvm"
fi

echo ""
echo "[7] Checking for vmlinux.bc..."
if [ -f "vmlinux.bc" ]; then
    echo "    ✓ vmlinux.bc exists"
    ls -lh vmlinux.bc
    
    echo ""
    echo "    Validating bitcode..."
    if llvm-dis vmlinux.bc -o /dev/null 2>/dev/null; then
        echo "    ✓ Bitcode is valid"
    else
        echo "    ✗ Bitcode appears corrupted"
    fi
else
    echo "    ✗ vmlinux.bc NOT found"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Recommendations                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"

if readelf -S vmlinux 2>/dev/null | grep -q ".llvm_bc"; then
    echo "✓ Bitcode is embedded. Try running extract-bc/get-bc manually:"
    if command -v get-bc &> /dev/null; then
        echo "  get-bc vmlinux"
    else
        echo "  extract-bc vmlinux"
    fi
else
    echo "✗ Bitcode not embedded. The kernel needs to be recompiled."
    echo ""
    echo "Possible solutions:"
    echo "1. Ensure LLVM_COMPILER is set before compilation:"
    echo "   export LLVM_COMPILER=clang"
    echo ""
    echo "2. Try using gllvm instead of wllvm:"
    echo "   pip3 install gllvm"
    echo ""
    echo "3. Compile with explicit wrapper:"
    echo "   make LLVM=1 CC=gclang -j\$(nproc)"
    echo ""
    echo "4. Try a minimal config to reduce complexity:"
    echo "   ./compile_kernel.sh linux-5.17 tinyconfig"
    echo ""
    echo "5. Clean and rebuild:"
    echo "   cd $KERNEL_SRC"
    echo "   make mrproper"
    echo "   Then run compile_kernel.sh again"
fi
