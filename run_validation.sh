#!/bin/bash
set -euo pipefail

PIN_ROOT="/opt/intel/pin"
PIN_TOOL="$(pwd)/build/pintool.so"
VAL_BIN="$(pwd)/build/validation"
LOG_DIR="$(pwd)/logs"

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/{int_counts.out,dram_counts.out,pintool.log}

echo "=== Arithmetic Intensity Validation ==="
echo "Expected: ~4000 ops, <2 MiB DRAM for kernel, ~3 GiB for bandwidth test"
echo

echo "Running test..."
sudo "$PIN_ROOT/pin" -logfile "$LOG_DIR/pintool.log" \
     -t "$PIN_TOOL" -quiet -- "$VAL_BIN"

echo
echo "Results:"
echo "──────────────────────────"

if [[ -f "$LOG_DIR/int_counts.out" ]]; then
    OPS=$(awk '/TOTAL/ {print $3}' "$LOG_DIR/int_counts.out")
    printf "Integer ops   : %d\n" $OPS
fi

if [[ -f "$LOG_DIR/dram_counts.out" ]]; then
    source "$LOG_DIR/dram_counts.out"
    
    # Convert to binary units (1 GiB = 1073741824 bytes, 1 MiB = 1048576 bytes)
    DRAM_GIB=$(printf "%.2f" $(echo "scale=2; $DRAM_TOTAL_BYTES/1073741824" | bc))
    DRAM_MIB=$(printf "%.2f" $(echo "scale=2; $DRAM_TOTAL_BYTES/1048576" | bc))
    
    # Display in most appropriate unit
    if (( $(echo "$DRAM_GIB >= 1" | bc -l) )); then
        printf "DRAM traffic  : %s GiB\n" "$DRAM_GIB"
    else
        printf "DRAM traffic  : %s MiB\n" "$DRAM_MIB"
    fi
    
    if [[ -n "${OPS:-}" && -n "${DRAM_TOTAL_BYTES:-}" && "$DRAM_TOTAL_BYTES" != "0" ]]; then
        OPS_PER_BYTE=$(printf "%.9f" $(echo "scale=9; $OPS/$DRAM_TOTAL_BYTES" | bc))
        printf "AI (ops/byte) : %s\n" "$OPS_PER_BYTE"
    fi
fi

echo
echo "Done."