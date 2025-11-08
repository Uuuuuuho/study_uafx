# Linux Kernel Analysis with UAFX

This guide explains how to analyze the Linux kernel for Use-After-Free vulnerabilities using UAFX.

## Prerequisites

The Docker environment includes all necessary tools:
- LLVM/Clang toolchain (v14.0.4)
- WLLVM (Whole Program LLVM)
- Kernel build dependencies (bc, bison, flex, libelf-dev, etc.)

## Quick Start

### 1. Download Linux Kernel Source

```bash
# Inside the Docker container
cd /uafx
```bash
# Option 1: Download and extract (original method)
wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.11.tar.xz
tar -xf linux-5.17.11.tar.xz

# Option 2: Clone with shallow history (faster, less disk space)
git clone --depth 1 --branch v5.17 https://github.com/torvalds/linux.git --single-branch linux-5.17 --tags
```

### 2. Compile Kernel to LLVM Bitcode

```bash
source env.sh
./compile_kernel.sh linux-5.17 defconfig
```

This will:
- Configure the kernel with `defconfig`
- Compile using WLLVM/Clang
- Extract LLVM bitcode to `linux-5.17.11/vmlinux.bc`

**Alternative configurations:**
```bash
# Minimal kernel (faster compilation)
./compile_kernel.sh linux-5.17.11 tinyconfig

# Custom config
./compile_kernel.sh linux-5.17.11 /path/to/custom.config
```

### 3. Generate Entry Point Configuration

```bash
# All x86-64 syscalls
./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_all_syscalls __x64_sys_

# File-related syscalls only
./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_file_syscalls '__x64_sys_(read|write|open|close|ioctl|mmap|munmap)'

# Network-related syscalls
./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_net_syscalls '__x64_sys_(socket|bind|connect|accept|send|recv|listen)'
```

### 4. Run UAFX Analysis

```bash
# Start analysis (runs in background via nohup)
./run_nohup.sh linux-5.17.11/vmlinux.bc conf_file_syscalls

# Monitor progress
tail -f conf_file_syscalls.log

# Check if finished
grep "Bug Detection Phase finished" conf_file_syscalls.log
```

### 5. Extract and Review Results

```bash
# Extract warnings once analysis completes
./ext_uaf_warns.sh conf_file_syscalls.log

# View results
cat warns-conf_file_syscalls-*/uaf
```

## Advanced Usage

### Analyzing Specific Subsystems

To analyze a specific kernel module or subsystem:

```bash
# Example: Analyze a specific driver
cd linux-5.17.11
make drivers/net/ethernet/intel/e1000/e1000.o
extract-bc drivers/net/ethernet/intel/e1000/e1000.o

# Generate entry points for this module
../gen_kernel_conf.sh drivers/net/ethernet/intel/e1000/e1000.o.bc conf_e1000 ""

# Run analysis
cd ..
./run_nohup.sh linux-5.17.11/drivers/net/ethernet/intel/e1000/e1000.o.bc conf_e1000
```

### Custom Entry Point Lists

You can manually create entry point configuration files:

```bash
cat > conf_custom << 'EOF'
__x64_sys_read
__x64_sys_write
__x64_sys_ioctl
my_custom_entry_function
EOF
```

### Resource Tuning

For large-scale kernel analysis, adjust Docker resources in `docker.sh`:

```bash
--shm-size=32g \    # Increase shared memory
--cpus="16" \       # Use more CPU cores
--memory="64g" \    # Increase RAM limit
```

## Common Entry Points for Kernel Analysis

### System Calls (x86-64)
- Format: `__x64_sys_<syscall_name>`
- Examples: `__x64_sys_read`, `__x64_sys_write`, `__x64_sys_ioctl`

### System Calls (ARM64)
- Format: `__arm64_sys_<syscall_name>`

### Finding Entry Points
```bash
# List all syscalls in the kernel
llvm-nm vmlinux.bc | grep __x64_sys_ | awk '{print $3}' | sort

# List all exported symbols
llvm-nm vmlinux.bc | grep ' T ' | awk '{print $3}' | sort
```

## Expected Analysis Time

- **Minimal kernel** (tinyconfig): 30 min - 2 hours
- **Default kernel** (defconfig): 4 - 24 hours
- **Full kernel** (allmodconfig): 1 - 7 days

Time varies greatly based on:
- Number of entry points
- Hardware (CPU cores, RAM)
- Kernel configuration complexity

## Troubleshooting

### Out of Memory
- Reduce number of entry points in config file
- Increase Docker shared memory (`--shm-size`)
- Analyze specific subsystems instead of whole kernel

### Compilation Errors
- Ensure `source env.sh` was run
- Check kernel version compatibility (tested with 5.17.11)
- Verify all dependencies are installed

### No Bitcode Generated
- Check WLLVM environment variables
- Verify LLVM_COMPILER_PATH is set correctly
- Ensure `extract-bc` command completed successfully

## Tips for Effective Analysis

1. **Start Small**: Begin with a subsystem or specific driver
2. **Focus on High-Risk Areas**: File operations, network protocols, device drivers
3. **Group Related Syscalls**: Analyze syscalls that share global state together
4. **Incremental Approach**: Start with fewer entry points, expand based on findings
5. **Use Meaningful Names**: Name config files descriptively (e.g., `conf_fs_syscalls`)

## References

- UAFX Paper: [Statically Discover Cross-Entry Use-After-Free Vulnerabilities in the Linux Kernel](https://www.ndss-symposium.org/wp-content/uploads/2025-559-paper.pdf)
- Linux Kernel: https://kernel.org
- WLLVM Documentation: https://github.com/travitch/whole-program-llvm
