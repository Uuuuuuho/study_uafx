#!/bin/bash
# Quick reference for Linux Kernel Analysis with UAFX
# Save this file or run: ./kernel_analysis_quickref.sh

cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║          Linux Kernel Analysis with UAFX - Quick Ref         ║
╚══════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────┐
│ 1. SETUP ENVIRONMENT                                         │
└─────────────────────────────────────────────────────────────┘
  cd /uafx
  source env.sh

┌─────────────────────────────────────────────────────────────┐
│ 2. DOWNLOAD KERNEL (v5.17.11 recommended)                    │
└─────────────────────────────────────────────────────────────┘
  wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.11.tar.xz
  tar -xf linux-5.17.11.tar.xz

┌─────────────────────────────────────────────────────────────┐
│ 3. COMPILE TO LLVM BITCODE                                   │
└─────────────────────────────────────────────────────────────┘
  ./compile_kernel.sh linux-5.17.11 defconfig
  # Output: linux-5.17.11/vmlinux.bc

┌─────────────────────────────────────────────────────────────┐
│ 4. GENERATE ENTRY POINT CONFIG                               │
└─────────────────────────────────────────────────────────────┘
  # All syscalls:
  ./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_all_syscalls

  # File operations:
  ./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_file_syscalls \
    '__x64_sys_(read|write|open|close|ioctl|mmap|munmap)'

  # Network operations:
  ./gen_kernel_conf.sh linux-5.17.11/vmlinux.bc conf_net_syscalls \
    '__x64_sys_(socket|bind|connect|accept|send|recv)'

┌─────────────────────────────────────────────────────────────┐
│ 5. RUN ANALYSIS                                              │
└─────────────────────────────────────────────────────────────┘
  ./run_nohup.sh linux-5.17.11/vmlinux.bc conf_file_syscalls

┌─────────────────────────────────────────────────────────────┐
│ 6. MONITOR PROGRESS                                          │
└─────────────────────────────────────────────────────────────┘
  tail -f conf_file_syscalls.log
  grep "Bug Detection Phase finished" conf_file_syscalls.log

┌─────────────────────────────────────────────────────────────┐
│ 7. EXTRACT RESULTS                                           │
└─────────────────────────────────────────────────────────────┘
  ./ext_uaf_warns.sh conf_file_syscalls.log
  cat warns-conf_file_syscalls-*/uaf

╔══════════════════════════════════════════════════════════════╗
║                      USEFUL COMMANDS                          ║
╚══════════════════════════════════════════════════════════════╝

List all syscalls in kernel:
  llvm-nm linux-5.17.11/vmlinux.bc | grep __x64_sys_ | awk '{print $3}'

Count entry points in config:
  wc -l conf_file_syscalls

Check analysis progress:
  grep -E "(started|finished|Phase)" conf_file_syscalls.log

Monitor system resources:
  docker stats uafx-dev

╔══════════════════════════════════════════════════════════════╗
║                    RECOMMENDED TARGETS                        ║
╚══════════════════════════════════════════════════════════════╝

Filesystem operations:
  __x64_sys_read, __x64_sys_write, __x64_sys_open, __x64_sys_close
  __x64_sys_ioctl, __x64_sys_mmap, __x64_sys_munmap, __x64_sys_stat

Memory management:
  __x64_sys_mmap, __x64_sys_munmap, __x64_sys_mprotect, __x64_sys_brk

Network operations:
  __x64_sys_socket, __x64_sys_bind, __x64_sys_connect, __x64_sys_accept
  __x64_sys_sendto, __x64_sys_recvfrom, __x64_sys_listen

Device operations:
  __x64_sys_ioctl, __x64_sys_poll, __x64_sys_select, __x64_sys_epoll_wait

╔══════════════════════════════════════════════════════════════╗
║                    TROUBLESHOOTING                            ║
╚══════════════════════════════════════════════════════════════╝

Out of memory?
  • Reduce entry points in config file
  • Increase Docker --shm-size and --memory
  • Analyze specific subsystem instead of whole kernel

Analysis too slow?
  • Start with fewer entry points
  • Use tinyconfig instead of defconfig
  • Increase Docker --cpus

Can't find symbols?
  • Ensure kernel compiled successfully
  • Check vmlinux.bc was created
  • Use: llvm-nm vmlinux.bc | grep <symbol_name>

For detailed documentation, see: KERNEL_ANALYSIS.md

EOF
