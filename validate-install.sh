#!/bin/bash
set -euo pipefail

# Compile validation test
g++ -O3 -march=native -I/opt/profiling-tools/include -o validation src/validation.cpp

# Run DRAM test
echo "=== DRAM Test ==="
DRAM_OUTPUT=$(sudo ./validation)
echo "$DRAM_OUTPUT"

# Run PIN test  
echo -e "\n=== PIN Test ==="
PIN_OUTPUT=$(sudo /opt/intel/pin/pin -t /opt/profiling-tools/lib/pintool.so -- ./validation 2>&1)
echo "$PIN_OUTPUT"

# Parse results
echo -e "\n=== Summary ==="
OPS=$(echo "$PIN_OUTPUT" | grep -o '"total":[0-9]*' | grep -o '[0-9]*')
BYTES=$(echo "$DRAM_OUTPUT" | grep "DRAM_TOTAL_BYTES=" | head -1 | cut -d'=' -f2)
GIB=$(echo "scale=2; $BYTES / 1073741824" | bc)

echo "Operations: $OPS"
echo "DRAM (GiB): $GIB"