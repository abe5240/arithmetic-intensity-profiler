#!/bin/bash
# install.sh - Minimal setup for arithmetic intensity profiling
set -euo pipefail

echo "=== Arithmetic Intensity Profiler Setup ==="

# 1. Extract PIN
echo "Extracting Intel Pin..."
if [ ! -d "pin/source" ]; then
    tar -xzf pin/pin-3.31-linux.tar.gz -C pin/ --strip-components=1
fi
PIN_ROOT="$(pwd)/pin"

# 2. Build PIN tool with proper flags
echo "Building PIN tool..."
mkdir -p build

# Use the Config includes to get proper flags
CONFIG_ROOT="${PIN_ROOT}/source/tools/Config"

# Compile with all necessary PIN flags
g++ -Wall -Werror -Wno-unknown-pragmas -DPIN_CRT=1 \
    -fno-stack-protector -fno-exceptions -funwind-tables \
    -fasynchronous-unwind-tables -fno-rtti \
    -DTARGET_IA32E -DHOST_IA32E -fPIC -DTARGET_LINUX \
    -fabi-version=2 -faligned-new \
    -I${PIN_ROOT}/source/include/pin \
    -I${PIN_ROOT}/source/include/pin/gen \
    -isystem ${PIN_ROOT}/extras/cxx/include \
    -isystem ${PIN_ROOT}/extras/crt/include \
    -isystem ${PIN_ROOT}/extras/crt/include/arch-x86_64 \
    -isystem ${PIN_ROOT}/extras/crt/include/kernel/uapi \
    -isystem ${PIN_ROOT}/extras/crt/include/kernel/uapi/asm-x86 \
    -I${PIN_ROOT}/extras/components/include \
    -I${PIN_ROOT}/extras/xed-intel64/include/xed \
    -I${PIN_ROOT}/source/tools/Utils \
    -I${PIN_ROOT}/source/tools/InstLib \
    -O3 -fomit-frame-pointer -fno-strict-aliasing \
    -Wno-dangling-pointer \
    -c -o build/pintool.o src/pintool.cpp

# Link with PIN libraries
g++ -shared -Wl,--hash-style=sysv \
    ${PIN_ROOT}/intel64/runtime/pincrt/crtbeginS.o \
    -Wl,-Bsymbolic \
    -Wl,--version-script=${PIN_ROOT}/source/include/pin/pintool.ver \
    -fabi-version=2 \
    -o build/pintool.so build/pintool.o \
    -L${PIN_ROOT}/intel64/runtime/pincrt \
    -L${PIN_ROOT}/intel64/lib \
    -L${PIN_ROOT}/intel64/lib-ext \
    -L${PIN_ROOT}/extras/xed-intel64/lib \
    -lpin -lxed \
    ${PIN_ROOT}/intel64/runtime/pincrt/crtendS.o \
    -lpindwarf -ldwarf -ldl-dynamic -nostdlib \
    -lc++ -lc++abi -lm-dynamic -lc-dynamic -lunwind-dynamic

echo "✓ PIN tool built successfully"

# 3. Build validation test
echo "Building validation test..."
g++ -std=c++17 -O0 -g -o build/validation src/validation.cpp

# 4. Enable perf counters
echo "Configuring system for DRAM measurements..."
if [ "$EUID" -eq 0 ]; then
    echo -1 > /proc/sys/kernel/perf_event_paranoid
    echo "✓ Perf counters enabled"
else
    echo "⚠ You may need sudo to enable DRAM counters"
    echo "  Run: echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid"
fi

echo
echo "✓ Installation complete!"
echo "Run ./run_validation.sh to verify everything works"