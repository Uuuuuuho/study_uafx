#!/bin/bash
# Build a single in-tree Linux kernel driver (module) with LLVM bitcode embedding.
# Usage: ./build_driver.sh <kernel_root> <driver_rel_dir> [mode] [extra_make_args]
#   <kernel_root>   : Path to the Linux kernel source root (e.g., linux-5.17)
#   <driver_rel_dir>: Path relative to kernel root of the driver folder (e.g., drivers/net/ethernet/intel/e1000)
#   mode            : wllvm | gllvm | auto (default: auto)
#   extra_make_args : Optional additional MAKE flags (quoted if multiple)
#
# Output:
#   - Builds the module .ko
#   - Attempts to extract <module>.ko.bc bitcode (written next to the .ko)
#   - Produces a summary and suggestions for UAFX analysis

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <kernel_root> <driver_rel_dir> [mode] [extra_make_args]" >&2
    exit 1
fi

KROOT="$1"
DRV_REL="$2"
MODE="${3:-auto}"
EXTRA_ARGS="${4:-}"

# Normalize KROOT: remove trailing slash for consistency
KROOT="${KROOT%/}"

if [ ! -d "$KROOT" ]; then
    echo "[!] Kernel root '$KROOT' not found" >&2
    exit 1
fi

DRV_ABS="$KROOT/$DRV_REL"
if [ ! -d "$DRV_ABS" ]; then
    echo "[!] Driver directory '$DRV_ABS' not found" >&2
    exit 1
fi

if [ -z "${LLVM_ROOT:-}" ]; then
    echo "[!] LLVM_ROOT not set. Run: source env.sh" >&2
    exit 1
fi

export LLVM_COMPILER=clang
export LLVM_COMPILER_PATH=$LLVM_ROOT/bin

select_wrapper() {
  case "$MODE" in
    gllvm) [ -x "$(command -v gclang || true)" ] && echo gclang && return 0 || { echo "[!] gclang not found" >&2; exit 1; } ;;
    wllvm) [ -x "$(command -v wllvm || true)" ] && echo wllvm && return 0 || { echo "[!] wllvm not found" >&2; exit 1; } ;;
    auto|*) if command -v gclang >/dev/null 2>&1; then echo gclang; elif command -v wllvm >/dev/null 2>&1; then echo wllvm; else echo "[!] Install gllvm or wllvm (pip3 install gllvm wllvm)" >&2; exit 1; fi ;;
  esac
}

WRAPPER_CC=$(select_wrapper)
WRAPPER_CXX=${WRAPPER_CC/clang/clang++}

# If using gclang, check if wrapper exists but don't use it for now
# The wrapper can interfere with kernel build infrastructure (fixdep, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$WRAPPER_CC" = "gclang" ]; then
  # Use gclang directly; let kernel build system handle flags
  echo "[*] Using gclang directly (some GCC-specific warnings may appear)"
fi

echo "[*] Building driver module"
echo "    Kernel root : $KROOT"
echo "    Driver dir  : $DRV_REL"
echo "    Mode        : $MODE ($WRAPPER_CC)"
echo "    Extra args  : ${EXTRA_ARGS:-<none>}"

pushd "$KROOT" >/dev/null

if [ ! -f .config ]; then
  echo "[!] No .config present in kernel root. Run defconfig or copy an existing config first." >&2
  exit 1
fi

# Ensure kernel is configured to build modules
if ! grep -q '^CONFIG_MODULES=y' .config; then
   echo "[!] CONFIG_MODULES is not enabled in $KROOT/.config, so Kbuild refuses to build modules." >&2
   echo "    Fix (non-interactive):" >&2
   echo "      cd $KROOT" >&2
   echo "      make defconfig   # if you don't have a .config yet" >&2
   echo "      ./scripts/config --enable MODULES" >&2
   echo "      # Optional: set your driver to module, e.g. E1000 -> m" >&2
   echo "      ./scripts/config --module E1000   # adjust symbol for your driver" >&2
   echo "      make olddefconfig && make modules_prepare" >&2
   echo "    Then re-run: $0 $KROOT $DRV_REL $MODE" >&2
   exit 1
fi

# If using LLVM/clang, remove GCC-specific flags from Makefile
if [ "$WRAPPER_CC" = "gclang" ] || [ "$WRAPPER_CC" = "wllvm" ]; then
  echo "[*] Patching kernel Makefile to remove GCC-specific flags incompatible with clang..."
  # Backup Makefile if not already backed up
  [ ! -f Makefile.backup ] && cp Makefile Makefile.backup
  # Remove -fconserve-stack and other GCC-only flags
  sed -i \
    -e 's/-fconserve-stack//g' \
    -e 's/-fno-allow-store-data-races//g' \
    -e 's/-Werror=designated-init//g' \
    Makefile
  echo "[*] Makefile patched (backup saved as Makefile.backup)"
fi

echo "[*] Invoking make for module..."
# Disable -fconserve-stack which clang doesn't support
export KCFLAGS="-Wno-unknown-warning-option"
time make LLVM=1 CC="$WRAPPER_CC" M="$DRV_REL" modules ${EXTRA_ARGS}

echo "[*] Locating built module (.ko)..."
# We're already in KROOT after pushd, so use relative path
KO_FILES=$(find "$DRV_REL" -maxdepth 2 -name '*.ko')
if [ -z "$KO_FILES" ]; then
  echo "[!] No .ko produced in $DRV_REL" >&2
  echo "    Check if the driver is enabled in .config and if make succeeded." >&2
  exit 1
fi

for ko in $KO_FILES; do
  echo "[*] Module: $ko"
  if command -v get-bc >/dev/null 2>&1 && [ "$WRAPPER_CC" = "gclang" ]; then
     echo "    -> Extracting bitcode via get-bc"
     ( cd "$(dirname "$ko")" && get-bc "$(basename "$ko")" ) || true
  elif command -v extract-bc >/dev/null 2>&1 && [ "$WRAPPER_CC" = "wllvm" ]; then
     echo "    -> Extracting bitcode via extract-bc"
     ( cd "$(dirname "$ko")" && extract-bc "$(basename "$ko")" ) || true
  else
     echo "    -> No suitable extraction tool found for wrapper '$WRAPPER_CC'" >&2
  fi
  if [ -f "${ko}.bc" ]; then
     echo "    [+] Bitcode: ${ko}.bc"
  else
     # gllvm names output: <module>.ko.bc -> rename convenience
     if [ -f "${ko%.ko}.bc" ]; then
        echo "    [+] Bitcode: ${ko%.ko}.bc"
     else
        echo "    [!] Bitcode NOT extracted for $ko" >&2
     fi
  fi
done

popd >/dev/null

echo ""
echo "[*] NEXT STEPS (Example):"
echo "    1. Identify driver entry points (callbacks) -> create conf_driver_entries"
echo "    2. Run: ./run_nohup.sh <path/to/module.bc> conf_driver_entries"
echo "    3. Extract warnings: ./ext_uaf_warns.sh conf_driver_entries.log"
echo ""
echo "[*] To auto-generate a config of typical callbacks, use:"
echo "    ./gen_driver_conf.sh $KROOT $DRV_REL conf_driver_entries"
