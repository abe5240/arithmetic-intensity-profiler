# Arithmetic Intensity Profiler

A system-wide profiling toolset for measuring arithmetic intensity (operations per byte) in C++ programs, particularly optimized for OpenFHE benchmarks.

## Overview

This toolkit provides:
- **Integer operation counting** via Intel PIN dynamic binary instrumentation
- **DRAM traffic measurement** using hardware performance counters
- **Arithmetic intensity calculation** (ops/byte ratio)

## Directory Structure

```
arithmetic-intensity-profiler/
├── install-profiling-tools.sh   # System-wide installation script
├── pin-3.31-linux.tar.gz        # Intel PIN binary (download separately)
└── src/
    ├── dram_counter.hpp         # DRAM traffic measurement header
    ├── pintool.cpp              # PIN tool for counting integer operations
    └── validation.cpp           # Test program to validate the tools
```

## Prerequisites

- Ubuntu/Linux x86_64 system
- GCC compiler (g++ 7.0 or later)
- Root access for installation
- Intel CPU with uncore PMU support (for DRAM measurements)

## Installation

### 1. Run Installation Script

```bash
# Install everything to /opt/
sudo ./install-profiling-tools.sh
```

This installs:
- Intel PIN to `/opt/intel/pin/`
- Your profiling tools to `/opt/profiling-tools/`
- System headers to `/opt/profiling-tools/include/`
- PIN tool library to `/opt/profiling-tools/lib/pintool.so`

### 2. Load Environment Variables

```bash
# Load for current session
source /etc/profile.d/profiling-tools.sh

# Verify installation
echo $PINTOOL_PATH  # Should show /opt/profiling-tools/lib/pintool.so
```

## System Architecture

```
/opt/
├── intel/pin/                   # Intel PIN framework
│   ├── pin                      # PIN executable
│   └── ...                      # PIN libraries
│
└── profiling-tools/             # Your custom tools
    ├── bin/
    │   ├── validation           # Test program
    │   └── run-with-pin         # Convenience wrapper
    ├── include/
    │   └── dram_counter.hpp     # System-wide header
    └── lib/
        └── pintool.so           # PIN instrumentation tool
```

## Components

### 1. DRAM Counter (dram_counter.hpp)

Measures memory traffic using Intel uncore performance monitoring units (PMUs).

**Features:**
- Reads CAS_COUNT events from memory controllers
- Measures read/write traffic separately
- Reports in binary units (KiB, MiB, GiB)

**Usage in C++:**
```cpp
#include <dram_counter.hpp>  // System header, no path needed

DRAMCounter counter;
counter.init();
counter.start();
// ... your code ...
counter.stop();
counter.print_results();  // Saves to logs/dram_counts.out
```

### 2. PIN Tool (pintool.cpp)

Counts integer arithmetic operations (ADD, SUB, MUL, DIV) between marker functions.

**Features:**
- Instruments only meaningful 64-bit integer operations
- Excludes stack operations and immediates
- Uses PIN_MARKER_START/END for targeted profiling

**Markers in your code:**
```cpp
extern "C" {
    void __attribute__((noinline)) PIN_MARKER_START() { asm volatile(""); }
    void __attribute__((noinline)) PIN_MARKER_END() { asm volatile(""); }
}

// In your code:
PIN_MARKER_START();
// ... operations to count ...
PIN_MARKER_END();
```

### 3. Validation Program (validation.cpp)

Tests both tools with known workloads.

## Usage

### Method 1: Direct PIN Invocation

```bash
sudo /opt/intel/pin/pin -t /opt/profiling-tools/lib/pintool.so -- ./your_program
```

### Method 2: Convenience Wrapper

```bash
sudo run-with-pin ./your_program --args
```

### Method 3: In Your Programs

```cpp
#include <dram_counter.hpp>

extern "C" {
    void __attribute__((noinline)) PIN_MARKER_START() { asm volatile(""); }
    void __attribute__((noinline)) PIN_MARKER_END() { asm volatile(""); }
}

int main() {
    DRAMCounter dram;
    dram.init();
    
    dram.start();
    PIN_MARKER_START();
    
    // Your computation here
    
    PIN_MARKER_END();
    dram.stop();
    
    dram.print_results();  // Creates logs/dram_counts.out
    // PIN tool creates logs/int_counts.out
    
    return 0;
}
```

## Output Files

The tools create two files in `logs/` directory:

### logs/int_counts.out
```
TOTAL counted: 123456
```

### logs/dram_counts.out
```
DRAM_READ_BYTES=12345678
DRAM_WRITE_BYTES=87654321
DRAM_TOTAL_BYTES=100000000
```

## Calculating Arithmetic Intensity

```bash
# After running with PIN
ops=$(grep -o '[0-9]*' logs/int_counts.out)
bytes=$(grep DRAM_TOTAL_BYTES logs/dram_counts.out | cut -d= -f2)
echo "Arithmetic Intensity: $(echo "scale=6; $ops / $bytes" | bc) ops/byte"
```

## Python Integration

```python
import subprocess
import re

# Run with PIN
result = subprocess.run(
    ["sudo", "/opt/intel/pin/pin", "-t", "/opt/profiling-tools/lib/pintool.so", 
     "--", "./your_program"],
    capture_output=True,
    text=True
)

# Parse PIN output from stderr
pin_match = re.search(r"TOTAL: (\d+)", result.stderr)
if pin_match:
    int_ops = int(pin_match.group(1))

# Parse DRAM from stdout  
dram_match = re.search(r"DRAM_TOTAL_BYTES=(\d+)", result.stdout)
if dram_match:
    dram_bytes = int(dram_match.group(1))
    ai = int_ops / dram_bytes
    print(f"Arithmetic Intensity: {ai:.6f} ops/byte")
```

## Important Notes

### Timing Issue
PIN writes `logs/int_counts.out` AFTER the program completes. If your program tries to read this file during execution, it won't find the data. Solutions:
1. Run twice (once with PIN, once without)
2. Parse PIN's stderr output directly
3. Use the Python integration approach

### Performance Overhead
- PIN instrumentation adds ~10x overhead to DRAM traffic
- Integer operation counting adds ~5-10x runtime overhead
- Use small test cases for profiling

### Security
- Requires root access for hardware performance counters
- Set `/proc/sys/kernel/perf_event_paranoid` to -1

## Troubleshooting

### PIN not counting operations
```bash
# Check if markers are in binary
nm ./your_program | grep PIN_MARKER

# Test with validation program
sudo run-with-pin /opt/profiling-tools/bin/validation
cat logs/int_counts.out
```

### DRAM counters not working
```bash
# Check permissions
cat /proc/sys/kernel/perf_event_paranoid
# Should be -1, if not:
sudo sh -c 'echo -1 > /proc/sys/kernel/perf_event_paranoid'

# Check for uncore PMUs
ls /sys/bus/event_source/devices/uncore_imc*
```

### Path issues
```bash
# Reload environment
source /etc/profile.d/profiling-tools.sh

# Use full paths
/opt/profiling-tools/bin/run-with-pin ./program
```

## Example Output

```bash
$ sudo run-with-pin ./addition --ring-dim=8192

[PIN] Analysis started...
=== Configuration ===
Ring dimension: 8192
...
=== DRAM Traffic (Region) ===
Read : 53.42 MiB
Write: 38.03 MiB
Total: 91.45 MiB
...
[PIN] Final counts
  ADD: 19230
  SUB: 17274
  MUL: 6
  DIV: 9
  TOTAL: 36519

$ echo "AI: $(echo "scale=6; 36519 / 95894400" | bc) ops/byte"
AI: .000380 ops/byte
```