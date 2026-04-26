#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Re-generate COE/MEM files before simulation.
python3 "$ROOT_DIR/tools/coe_generator.py"

OUT_WORDS=(16 49 81 169 225)
for CASE in 0 1 2 3 4; do
    echo "[RUN] case ${CASE}"
    iverilog -g2012 \
        -DINSTR_MEM_INIT_FILE=\"$ROOT_DIR/generated/instr_mem.mem\" \
        -DDATA_MEM_INIT_FILE=\"$ROOT_DIR/generated/RAM_case${CASE}.mem\" \
        -DGOLDEN_MEM_FILE=\"$ROOT_DIR/generated/golden_case${CASE}.mem\" \
        -DOUT_WORDS=${OUT_WORDS[$CASE]} \
        -o "case${CASE}.vvp" \
        "$ROOT_DIR/rtl/ALU.v" \
        "$ROOT_DIR/rtl/Registers.v" \
        "$ROOT_DIR/rtl/instr_dec.v" \
        "$ROOT_DIR/rtl/PC_Controller.v" \
        "$ROOT_DIR/rtl/Instruction_Memory.v" \
        "$ROOT_DIR/rtl/Data_mem.v" \
        "$ROOT_DIR/rtl/Simple_Processor.v" \
        "$ROOT_DIR/rtl/Simple_CPU.v" \
        "$ROOT_DIR/rtl/CNN_Core.sv" \
        "$ROOT_DIR/rtl/CNN_Engine.sv" \
        "$ROOT_DIR/rtl/CNN.sv" \
        "$ROOT_DIR/rtl/RISCV_CNN.v" \
        "$ROOT_DIR/tb/RISCV_CNN_tb.sv"
    vvp "case${CASE}.vvp"
done
