#!/bin/bash
# Helper script to compile Linux kernel to LLVM bitcode for UAFX analysis
# Usage: ./compile_kernel.sh <kernel_source_dir> [config_type]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <kernel_source_dir> [config_type]"
    echo "  config_type: defconfig (default), tinyconfig, allnoconfig, or path to .config"
    exit 1
fi

KERNEL_SRC="$1"
CONFIG_TYPE="${2:-defconfig}"

if [ ! -d "$KERNEL_SRC" ]; then
    echo "Error: Kernel source directory '$KERNEL_SRC' not found"
    exit 1
fi

echo "[*] Compiling Linux kernel to LLVM bitcode"
echo "[*] Kernel source: $KERNEL_SRC"
echo "[*] Config type: $CONFIG_TYPE"

# Ensure LLVM environment is set
if [ -z "$LLVM_ROOT" ]; then
    echo "[!] LLVM_ROOT not set. Please run: source env.sh"
    exit 1
fi

# Set up WLLVM environment
export LLVM_COMPILER=clang
export CC=wllvm
export CXX=wllvm++
export LLVM_COMPILER_PATH=$LLVM_ROOT/bin

echo "[*] WLLVM environment configured:"
echo "    LLVM_COMPILER=$LLVM_COMPILER"
echo "    CC=$CC"
echo "    CXX=$CXX"
echo "    LLVM_COMPILER_PATH=$LLVM_COMPILER_PATH"

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

# Compile kernel
echo "[*] Compiling kernel (this may take a while)..."
NUM_CORES=$(nproc)
echo "[*] Using $NUM_CORES cores"
make -j"$NUM_CORES"

# Extract bitcode
echo "[*] Extracting LLVM bitcode from vmlinux..."
if [ -f "vmlinux" ]; then
    extract-bc vmlinux
    if [ -f "vmlinux.bc" ]; then
        echo "[+] Success! vmlinux.bc created"
        ls -lh vmlinux.bc
        echo ""
        echo "[*] To analyze with UAFX, create an entry point config file and run:"
        echo "    ./run_nohup.sh $(pwd)/vmlinux.bc /path/to/conf_file"
    else
        echo "[!] Failed to extract bitcode"
        exit 1
    fi
else
    echo "[!] vmlinux not found. Compilation may have failed."
    exit 1
fi
