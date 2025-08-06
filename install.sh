#!/bin/bash
set -euo pipefail

echo "=== Installing Pin System-Wide ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    echo "Run: sudo $0"
    exit 1
fi

# Install Pin to /opt
mkdir -p /opt/intel/pin
tar -xzf src/pin-3.31-linux.tar.gz -C /opt/intel/pin --strip-components=1
chmod -R 755 /opt/intel/pin

# Set up environment
tee /etc/profile.d/intel-pin.sh > /dev/null << 'EOF'
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
echo -1 > /proc/sys/kernel/perf_event_paranoid
echo "✓ Perf counters enabled"

echo "✓ Done. Run ./run_validation.sh to test"