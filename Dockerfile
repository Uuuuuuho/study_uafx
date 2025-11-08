# Ubuntu 22.04 + 빌드툴
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git python3 python3-pip \
    ca-certificates wget curl unzip \
    zlib1g-dev libtinfo-dev libxml2-dev \
    clang lld \
    bc bison flex libelf-dev libssl-dev \
    libncurses-dev kmod cpio \
 && rm -rf /var/lib/apt/lists/*

# Install wllvm for whole-program LLVM compilation
RUN pip3 install --no-cache-dir wllvm

WORKDIR /uafx
# 캐시 효율을 위해 필요한 파일만 먼저 복사
COPY setup_uafx.py ./
COPY llvm_analysis ./llvm_analysis
COPY benchmark ./benchmark
COPY README.md ./
COPY compile_kernel.sh gen_kernel_conf.sh ./
RUN chmod +x compile_kernel.sh gen_kernel_conf.sh

# (선택) Z3 번들을 이미지에 포함하려면 z3.zip을 빌드 컨텍스트에 두고 아래 2줄 주석 해제
# COPY z3.zip /tmp/z3.zip
# RUN mkdir -p /uafx/llvm_analysis/MainAnalysisPasses/z3 && unzip -q /tmp/z3.zip -d /uafx/llvm_analysis/MainAnalysisPasses/

SHELL ["/bin/bash","-lc"]

# LLVM 도구셋 설치 스크립트 실행 (env.sh 생성)
# clang 경로를 명시해 CMake 찾기 문제 방지
RUN CC=/usr/bin/clang CXX=/usr/bin/clang++ ASM=/usr/bin/clang \
    python3 setup_uafx.py -o /opt/uafx_deps || true

# 기본 셸
CMD ["bash"]
