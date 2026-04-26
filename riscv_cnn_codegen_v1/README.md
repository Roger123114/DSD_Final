# RISCV_CNN Codegen V1

This package is the first integration-code drop for connecting the existing CNN block to the RISC-V CPU through a shared data memory.

## Scope

- Keep the existing CNN implementation as-is:
  - `CNN.sv`
  - `CNN_Core.sv`
  - `CNN_Engine.sv`
- Modify CPU memory IO so CPU Port A accesses the shared memory externally.
- Add a top-level integration wrapper:
  - `RISCV_CNN.v`
- Add memory behavior models / wrapper:
  - `Data_mem.v`
  - `Instruction_Memory.v`
- Add COE/MEM generator:
  - `tools/coe_generator.py`
- Generate 5 data-memory test cases:
  - `generated/RAM_case0.coe` ... `generated/RAM_case4.coe`
  - `generated/RAM_case0.mem` ... `generated/RAM_case4.mem`
- Generate instruction memory content:
  - `generated/instr_mem.coe`
  - `generated/instr_mem.mem`

## File naming

All copied files remove the original `(number)` suffix.

## Integration model

The CPU uses Data Memory Port A. The CNN uses Data Memory Port B.

The current CNN private protocol is preserved:

| Word address | Meaning |
|---:|---|
| 768 | CNN private start / finish / feature-size word |
| 769 | CNN private output-start word address |
| 770 | `{w00,w01,w02,w10}` |
| 771 | `{w11,w12,w20,w21}` |
| 772 | `{w22,24'd0}` |

The public spec-visible memory map is also preserved for the first smoke test:

| Word address | Meaning |
|---:|---|
| 0-2 | Weight0 |
| 12 | `{feature_map_size[6:1], start[0]}` |
| 13 | `{output_start[10:1], finish[0]}` |
| 16+ | Input feature map, row-major, four signed Q1.6 bytes per 32-bit word, big-endian |

The CPU program does this first smoke flow:

1. Poll `mem[12]` until nonzero.
2. Clear `mem[12]`.
3. Copy Weight0 from public addresses `0..2` to CNN private addresses `770..772`.
4. Copy constants from address `896..899` into the CNN private control region.
5. Start the existing CNN once.
6. Poll `mem[768]` until it equals `0x40000000`.
7. Write public finish/status word to `mem[13]`.
8. Halt.

This first code drop verifies CPU-to-CNN connectivity. It does not yet implement the full two-layer CNN schedule or CPU-side partial-output addition.

## Generated memory constants

`coe_generator.py` reserves address `896..899` for CPU control constants:

| Word address | Value |
|---:|---|
| 896 | CNN private start word: `0x80000000 | (f_size << 16)` |
| 897 | CNN output-start word address: `384` |
| 898 | CNN finish constant: `0x40000000` |
| 899 | public status word: `(384 << 1) | 1` |

Addresses `960..1023` are not written by the generator.

## Simulation

If `iverilog` is installed, run:

```bash
cd riscv_cnn_codegen_v1
bash tools/run_5_cases.sh
```

The script compiles and runs all 5 generated cases.

## Vivado use

- Use `RAM.xci` as the real shared memory IP.
- Use `Instruction_Memory.xci` as the instruction ROM IP initialized by `generated/instr_mem.coe`.
- Use `generated/RAM_caseX.coe` to initialize the shared RAM IP.
- `Data_mem.v` is written as a wrapper/behavior model. In simulation, it uses `$readmemh`. In Vivado, define `USE_XILINX_IP` or instantiate the `RAM` IP through this wrapper.

## Important limitation in V1

This version is intentionally a first integration drop:

- Existing CNN IO is preserved.
- CPU controls the existing CNN through its private `768..772` protocol.
- Only one CNN run using Weight0 is scheduled.
- The full final-project two-stage CNN schedule and CPU-side addition are left for V2 code generation.
