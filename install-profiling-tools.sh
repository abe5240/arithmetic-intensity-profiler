#!/bin/bash
set -euo pipefail

echo "=== Installing Profiling Tools System-Wide ==="

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run with sudo"
    exit 1
fi

# Install PIN
echo "Installing Intel PIN..."
if [ ! -f "pin-3.31-linux.tar.gz" ]; then
    echo "Error: pin-3.31-linux.tar.gz not found"
    exit 1
fi

mkdir -p /opt/intel/pin
tar -xzf pin-3.31-linux.tar.gz -C /opt/intel/pin --strip-components=1
chmod -R 755 /opt/intel/pin

# Set up PIN environment
tee /etc/profile.d/intel-pin.sh > /dev/null << 'EOF'
export PIN_ROOT="/opt/intel/pin"
export PATH="$PIN_ROOT:$PATH"
EOF

export PIN_ROOT="/opt/intel/pin"
echo "✓ PIN installed"

# Create profiling-tools structure
echo "Setting up profiling tools..."
mkdir -p /opt/profiling-tools/{bin,include,lib}

# Copy dram_counter.hpp
cp src/dram_counter.hpp /opt/profiling-tools/include/
chmod 644 /opt/profiling-tools/include/dram_counter.hpp
echo "✓ Installed dram_counter.hpp"

# Build PIN tool
echo "Building PIN tool..."
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

cp build/pintool.so /opt/profiling-tools/lib/
chmod 755 /opt/profiling-tools/lib/pintool.so
echo "✓ PIN tool installed"

# Set up environment
tee /etc/profile.d/profiling-tools.sh > /dev/null << 'EOF'
export PROFILING_TOOLS_ROOT="/opt/profiling-tools"
export PINTOOL_PATH="/opt/profiling-tools/lib/pintool.so"
export CPLUS_INCLUDE_PATH="/opt/profiling-tools/include:$CPLUS_INCLUDE_PATH"
export PATH="/opt/profiling-tools/bin:$PATH"
EOF

# Create convenience wrapper
tee /opt/profiling-tools/bin/run-with-pin > /dev/null << 'EOF'
#!/bin/bash
if [ $# -lt 1 ]; then
    echo "Usage: run-with-pin <program> [args...]"
    exit 1
fi
exec /opt/intel/pin/pin -t /opt/profiling-tools/lib/pintool.so -quiet -- "$@"
EOF
chmod 755 /opt/profiling-tools/bin/run-with-pin

# Enable perf counters
echo -1 > /proc/sys/kernel/perf_event_paranoid

echo ""
echo "✓ Installation Complete!"
echo ""
echo "Directory structure:"
echo "  /opt/intel/pin/          - Intel PIN"
echo "  /opt/profiling-tools/    - Your profiling tools"
echo ""
echo "Run: source /etc/profile.d/profiling-tools.sh"
