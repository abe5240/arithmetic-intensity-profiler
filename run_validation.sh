#!/usr/bin/env bash
###############################################################################
# run_validation.sh – self-test for pintool + DRAM counters
###############################################################################
set -euo pipefail
IFS=$'\n\t'

ROOT=$(pwd)
PIN_ROOT="$ROOT/pin"
PIN_TOOL="$ROOT/build/pintool.so"
VAL_BIN="$ROOT/build/validation"
LOG_DIR="$ROOT/logs"

ESC=$'\033['
BOLD="${ESC}1m" RESET="${ESC}0m"
BLUE="${ESC}34m" CYAN="${ESC}36m" GREEN="${ESC}32m" YELLOW="${ESC}33m" RED="${ESC}31m"
tick="${GREEN}✓${RESET}" cross="${RED}✗${RESET}"

[[ -f $PIN_TOOL && -f $VAL_BIN ]] || {
    printf "${RED}Error:${RESET} build artifacts missing – run ./install.sh first\n"; exit 1; }

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/{int_counts.out,dram_counts.out,pintool.log}

banner() {
  printf "${BOLD}${BLUE}╭────────────────────────────────────────────╮\n"
  printf "│      Arithmetic-Intensity Validation      │\n"
  printf "╰────────────────────────────────────────────╯${RESET}\n\n"
}
banner

cat <<EOF
${BOLD}Expected:${RESET}
  • ~4 000 integer ops
  • <2 MB DRAM for arithmetic kernel
  • ~3 GB DRAM for bandwidth test

EOF

printf "${BOLD}Running test …${RESET}\n"
CMD=( "$PIN_ROOT/pin" -logfile "$LOG_DIR/pintool.log" \
      -t "$PIN_TOOL" -quiet -- "$VAL_BIN" )
(( EUID )) && printf "Using sudo for PMU access\n" && sudo "${CMD[@]}" \
           || "${CMD[@]}"

printf "\n${CYAN}────────────────────────────────────────${RESET}\n"

INT_FILE="$LOG_DIR/int_counts.out"
DRAM_FILE="$LOG_DIR/dram_counts.out"

if [[ -f $INT_FILE ]]; then
    OPS=$(awk '/TOTAL/ {print $3}' "$INT_FILE")
    (( OPS >= 3900 && OPS <= 4200 )) && pass=$tick || pass=$cross
    printf "Integer ops : %d  %s\n" "$OPS" "$pass"
else
    printf "${cross} int_counts.out missing\n"
fi

if [[ -f $DRAM_FILE ]]; then
    # shellcheck source=/dev/null
    source "$DRAM_FILE"
    printf "DRAM total  : %.2f MB\n" "$(echo "$DRAM_TOTAL_BYTES/1048576" | bc -l)"
    if (( DRAM_TOTAL_BYTES && OPS )); then
        INT=$(awk "BEGIN{printf \"%.6f\", $OPS/$DRAM_TOTAL_BYTES}")
        printf "Intensity   : %s ops/byte\n" "$INT"
    fi
else
    printf "${cross} dram_counts.out missing\n"
fi

printf "${CYAN}────────────────────────────────────────${RESET}\n"
printf "${BOLD}Validation complete${RESET}\n"