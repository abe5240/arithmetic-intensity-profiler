#!/bin/bash
set -euo pipefail

PIN_ROOT="/opt/intel/pin"
PIN_TOOL="$(pwd)/build/pintool.so"
VAL_BIN="$(pwd)/build/validation"
LOG_DIR="$(pwd)/logs"

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/{int_counts.out,dram_counts.out,pintool.log}

echo "=== Arithmetic Intensity Validation ==="
echo "Expected: ~4000 ops, <2MB DRAM for kernel, ~3GB for bandwidth test"
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
    DRAM_MB=$(printf "%.2f" $(echo "scale=2; $DRAM_TOTAL_BYTES/1048576" | bc))
    printf "DRAM traffic  : %s MB\n" "$DRAM_MB"
    if [[ -n "${OPS:-}" && -n "${DRAM_TOTAL_BYTES:-}" && "$DRAM_TOTAL_BYTES" != "0" ]]; then
        OPS_PER_MB=$(printf "%.2f" $(echo "scale=2; $OPS/($DRAM_TOTAL_BYTES/1048576)" | bc))
        printf "AI (ops/MB)   : %s\n" "$OPS_PER_MB"
    fi
fi

echo
echo "Done."