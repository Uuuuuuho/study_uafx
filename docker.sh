#!/bin/bash

docker build -t uafx:llvm14 .

# Z3 번들을 호스트에서 넣었다면: uafx/llvm_analysis/MainAnalysisPasses/z3 폴더가 존재해야 함
docker run --rm -it \
  -v "$PWD:/uafx" \
  -w /uafx \
  --shm-size=8g \
  --cpus="4" \
  --name uafx-dev \
  uafx:llvm14

# (재실행 권장) LLVM 도구셋 설치/환경 파일 생성
CC=/usr/bin/clang CXX=/usr/bin/clang++ ASM=/usr/bin/clang \
python3 setup_uafx.py -o /opt/uafx_deps

# 환경 적용
source env.sh

# 분석 패스 빌드
cd llvm_analysis
./build.sh

# 데모 실행 (README의 예시)
cd /uafx
./run_nohup.sh benchmark/test_uafx_demo.bc benchmark/conf_test_uafx_demo
