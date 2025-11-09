#!/bin/bash
# Wrapper to filter out GCC-specific flags that clang doesn't support
# Usage: Used transparently by build_driver.sh

args=()
for arg in "$@"; do
  case "$arg" in
    -fconserve-stack|-fno-allow-store-data-races|-Werror=designated-init|-Wno-override-init)
      # Skip GCC-only flags
      ;;
    *)
      args+=("$arg")
      ;;
  esac
done

exec gclang "${args[@]}"
