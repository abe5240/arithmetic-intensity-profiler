#!/bin/bash
set -euo pipefail

echo "=== Installing Pin System-Wide ==="

# Install Pin to /opt
sudo mkdir -p /opt/intel/pin
sudo tar -xzf src/pin-3.31-linux.tar.gz -C /opt/intel/pin --strip-components=1

# Set up environment
sudo tee /etc/profile.d/intel-pin.sh > /dev/null << 'EOF'
export PIN_ROOT="/opt/intel/pin"
export PATH="$PIN_ROOT:$PATH"
EOF

# Export for current session
export PIN_ROOT="/opt/intel/pin"

echo "✓ Pin installed to /opt/intel/pin"

# Build pintool
echo "Building pintool..."
mkdir -p build

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

echo "✓ Pintool built"

# Build validation
echo "Building validation..."
g++ -std=c++17 -O0 -g -o build/validation src/validation.cpp

# Enable perf counters
sudo sh -c 'echo -1 > /proc/sys/kernel/perf_event_paranoid'

echo "✓ Done. Run ./run_validation.sh to test"