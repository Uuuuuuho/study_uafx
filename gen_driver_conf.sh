#!/bin/bash
# Generate a UAFX entry configuration file for a kernel driver by scanning
# exported symbols and common callback struct patterns.
# Usage: ./gen_driver_conf.sh <kernel_root> <driver_rel_dir> <output_conf>

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <kernel_root> <driver_rel_dir> <output_conf>" >&2
  exit 1
fi

KROOT="$1"
DRV_REL="$2"
OUT_CONF="$3"

if [ ! -d "$KROOT" ]; then
  echo "[!] Kernel root '$KROOT' not found" >&2
  exit 1
fi
if [ ! -d "$KROOT/$DRV_REL" ]; then
  echo "[!] Driver directory '$KROOT/$DRV_REL' not found" >&2
  exit 1
fi

echo "[*] Generating driver entry config: $OUT_CONF"
echo "    Kernel root : $KROOT"
echo "    Driver dir  : $DRV_REL"

# Strategy:
# 1. Use nm on built module .ko (if exists) to list defined, global functions.
# 2. Grep source for common callback struct initializations (file_operations,
#    pci_driver, platform_driver, net_device_ops, etc.). Extract referenced
#    function names heuristically.
# 3. Aggregate unique names into output.

DRV_ABS="$KROOT/$DRV_REL"
KO_FILE=$(find "$DRV_ABS" -maxdepth 2 -name '*.ko' | head -1 || true)
TMP=$(mktemp)
trap 'rm -f $TMP' EXIT

echo "[*] Collecting symbols..."
if [ -n "$KO_FILE" ]; then
  echo "    Using module binary: $KO_FILE"
  if command -v llvm-nm >/dev/null 2>&1; then
    llvm-nm "$KO_FILE" | awk '/ T / {print $3}' >> "$TMP" || true
  else
    nm "$KO_FILE" | awk '/ T / {print $3}' >> "$TMP" || true
  fi
else
  echo "    No .ko found yet - skipping nm symbol collection"
fi

echo "[*] Scanning source for callback structs..."
grep -R "file_operations" "$DRV_ABS" 2>/dev/null | \
  sed -n 's/.*\.\([a-zA-Z0-9_]*\)\s*=\s*\([a-zA-Z0-9_]*\).*/\2/p' >> "$TMP" || true
grep -R "pci_driver" "$DRV_ABS" 2>/dev/null | \
  sed -n 's/.*\.\([a-zA-Z0-9_]*\)\s*=\s*\([a-zA-Z0-9_]*\).*/\2/p' >> "$TMP" || true
grep -R "platform_driver" "$DRV_ABS" 2>/dev/null | \
  sed -n 's/.*\.\([a-zA-Z0-9_]*\)\s*=\s*\([a-zA-Z0-9_]*\).*/\2/p' >> "$TMP" || true
grep -R "net_device_ops" "$DRV_ABS" 2>/dev/null | \
  sed -n 's/.*\.\([a-zA-Z0-9_]*\)\s*=\s*\([a-zA-Z0-9_]*\).*/\2/p' >> "$TMP" || true
grep -R "block_device_operations" "$DRV_ABS" 2>/dev/null | \
  sed -n 's/.*\.\([a-zA-Z0-9_]*\)\s*=\s*\([a-zA-Z0-9_]*\).*/\2/p' >> "$TMP" || true

sort -u "$TMP" | grep -E '^[a-zA-Z0-9_]+$' > "$OUT_CONF"
COUNT=$(wc -l < "$OUT_CONF")
echo "[+] Wrote $COUNT potential entry functions to $OUT_CONF"
echo "    Preview:"; head -n 10 "$OUT_CONF" || true
if [ $COUNT -gt 10 ]; then echo "    ..."; fi

echo "[*] Use this with UAFX: ./run_nohup.sh <module.bc> $OUT_CONF"
