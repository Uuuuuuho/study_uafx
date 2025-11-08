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
export LLVM_COMPILER_PATH=$LLVM_ROOT/bin

echo "[*] WLLVM environment configured:"
echo "    LLVM_COMPILER=$LLVM_COMPILER"
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

# Compile kernel with WLLVM
# Important: Pass CC explicitly to make, but use native compilers for host tools
echo "[*] Compiling kernel (this may take a while)..."
NUM_CORES=$(nproc)
echo "[*] Using $NUM_CORES cores"

# Use LLVM=1 to force kernel to use LLVM toolchain
# Only wrap target CC with wllvm, use native clang/ld for host tools
# This avoids "unknown linker" errors in host tool compilation
make LLVM=1 \
     CC=wllvm \
     HOSTCC=clang \
     HOSTLD=ld.lld \
     HOSTAR=llvm-ar \
     AR=llvm-ar \
     NM=llvm-nm \
     STRIP=llvm-strip \
     OBJCOPY=llvm-objcopy \
     OBJDUMP=llvm-objdump \
     READELF=llvm-readelf \
     -j"$NUM_CORES"

# Extract bitcode
echo "[*] Extracting LLVM bitcode from vmlinux..."
if [ -f "vmlinux" ]; then
    # Verify that vmlinux has the .llvm_bc section
    if readelf -S vmlinux | grep -q ".llvm_bc"; then
        echo "[*] .llvm_bc section found in vmlinux"
    else
        echo "[!] WARNING: .llvm_bc section NOT found in vmlinux"
        echo "[!] This means the kernel was not compiled with WLLVM properly"
        echo "[!] Trying to extract anyway..."
    fi
    
    extract-bc vmlinux
    
    if [ -f "vmlinux.bc" ]; then
        echo "[+] Success! vmlinux.bc created"
        ls -lh vmlinux.bc
        echo ""
        echo "[*] To analyze with UAFX, create an entry point config file and run:"
        echo "    ./run_nohup.sh $(pwd)/vmlinux.bc /path/to/conf_file"
        echo ""
        echo "[*] Or use the helper script to generate entry points:"
        echo "    ./gen_kernel_conf.sh $(pwd)/vmlinux.bc conf_syscalls __x64_sys_"
    else
        echo "[!] Failed to extract bitcode"
        echo "[!] Possible causes:"
        echo "    1. Kernel build system didn't use wllvm (check build logs)"
        echo "    2. LLVM toolchain version mismatch"
        echo "    3. Some kernel files compiled without LLVM"
        exit 1
    fi
else
    echo "[!] vmlinux not found. Compilation may have failed."
    exit 1
fi