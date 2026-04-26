#!/usr/bin/env python3
import math
import random
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parents[1]
GEN_DIR = OUT_DIR / "generated"
GEN_DIR.mkdir(exist_ok=True)

MEM_DEPTH = 1024
OUT_START_WORD = 384
CONST_BASE_WORD = 896
CNN_PRIVATE_BASE_WORD = 768
INPUT_BASE_WORD = 16

# -----------------------------
# RISC-V RV32I subset assembler
# -----------------------------
REG = {f"x{i}": i for i in range(32)}


def s32(x):
    return x & 0xFFFFFFFF


def check_imm_signed(value, bits, name):
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi:
        raise ValueError(f"{name}={value} out of signed {bits}-bit range [{lo}, {hi}]")


def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def i_type(imm, rs1, funct3, rd, opcode):
    check_imm_signed(imm, 12, "I-imm")
    imm12 = imm & 0xFFF
    return (imm12 << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
           ((rd & 0x1F) << 7) | (opcode & 0x7F)


def s_type(imm, rs2, rs1, funct3, opcode):
    check_imm_signed(imm, 12, "S-imm")
    imm12 = imm & 0xFFF
    return ((imm12 >> 5) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | ((imm12 & 0x1F) << 7) | (opcode & 0x7F)


def b_type(offset, rs2, rs1, funct3, opcode):
    check_imm_signed(offset, 13, "B-offset")
    if offset % 2 != 0:
        raise ValueError(f"Branch offset must be 2-byte aligned: {offset}")
    imm = offset & 0x1FFF
    bit12 = (imm >> 12) & 1
    bit11 = (imm >> 11) & 1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           ((funct3 & 0x7) << 12) | (bits4_1 << 8) | (bit11 << 7) | (opcode & 0x7F)


def add(rd, rs1, rs2):
    return r_type(0x00, REG[rs2], REG[rs1], 0x0, REG[rd], 0x33)


def sub(rd, rs1, rs2):
    return r_type(0x20, REG[rs2], REG[rs1], 0x0, REG[rd], 0x33)


def addi(rd, rs1, imm):
    return i_type(imm, REG[rs1], 0x0, REG[rd], 0x13)


def lw(rd, imm, rs1):
    return i_type(imm, REG[rs1], 0x2, REG[rd], 0x03)


def sw(rs2, imm, rs1):
    return s_type(imm, REG[rs2], REG[rs1], 0x2, 0x23)


def beq(rs1, rs2, offset):
    return b_type(offset, REG[rs2], REG[rs1], 0x0, 0x63)


def blt(rs1, rs2, offset):
    return b_type(offset, REG[rs2], REG[rs1], 0x4, 0x63)


def jalr(rd, rs1, imm):
    return i_type(imm, REG[rs1], 0x0, REG[rd], 0x67)


class Assembler:
    def __init__(self):
        self.items = []
        self.labels = {}

    def label(self, name):
        self.labels[name] = len(self.items) * 4

    def emit(self, op, *args):
        self.items.append((op, args))

    def assemble(self):
        words = []
        for idx, (op, args) in enumerate(self.items):
            pc = idx * 4
            if op == "addi":
                words.append(addi(*args))
            elif op == "lw":
                words.append(lw(*args))
            elif op == "sw":
                words.append(sw(*args))
            elif op == "add":
                words.append(add(*args))
            elif op == "sub":
                words.append(sub(*args))
            elif op == "beq_label":
                rs1, rs2, label = args
                words.append(beq(rs1, rs2, self.labels[label] - pc))
            elif op == "blt_label":
                rs1, rs2, label = args
                words.append(blt(rs1, rs2, self.labels[label] - pc))
            elif op == "jalr":
                words.append(jalr(*args))
            else:
                raise ValueError(f"Unsupported op {op}")
        return [s32(w) for w in words]


def build_cpu_program():
    a = Assembler()
    a.label("poll_sys_start")
    a.emit("lw", "x1", 48, "x0")          # mem[12]
    a.emit("beq_label", "x1", "x0", "poll_sys_start")
    a.emit("sw", "x0", 48, "x0")          # clear mem[12]

    a.emit("addi", "x10", "x0", 1536)     # x10 = byte address 3072 = word 768
    a.emit("addi", "x10", "x10", 1536)
    a.emit("addi", "x11", "x0", 1792)     # x11 = byte address 3584 = word 896
    a.emit("addi", "x11", "x11", 1792)

    a.emit("lw", "x2", 0, "x11")          # start control word for CNN private addr 768
    a.emit("lw", "x3", 4, "x11")          # CNN output start word address
    a.emit("lw", "x6", 8, "x11")          # finish constant 0x40000000
    a.emit("lw", "x7", 12, "x11")         # public status word for mem[13]

    a.emit("sw", "x3", 4, "x10")          # mem[769] = output start address
    a.emit("lw", "x4", 0, "x0")           # Weight0 word0
    a.emit("sw", "x4", 8, "x10")          # mem[770]
    a.emit("lw", "x4", 4, "x0")           # Weight0 word1
    a.emit("sw", "x4", 12, "x10")         # mem[771]
    a.emit("lw", "x4", 8, "x0")           # Weight0 word2
    a.emit("sw", "x4", 16, "x10")         # mem[772]
    a.emit("sw", "x2", 0, "x10")          # mem[768] = start

    a.label("wait_cnn_finish")
    a.emit("lw", "x5", 0, "x10")          # poll mem[768]
    a.emit("beq_label", "x5", "x6", "write_public_done")
    a.emit("beq_label", "x0", "x0", "wait_cnn_finish")

    a.label("write_public_done")
    a.emit("sw", "x7", 52, "x0")          # mem[13] = {output_start[9:0], finish}

    a.label("halt")
    a.emit("beq_label", "x0", "x0", "halt")
    return a.assemble()


# -----------------------------
# Data generation and Q1.6 model
# -----------------------------

def to_u8(x):
    return x & 0xFF


def to_s8(x):
    x &= 0xFF
    return x - 256 if x & 0x80 else x


def pack4(values):
    b = [to_u8(v) for v in values]
    while len(b) < 4:
        b.append(0)
    return ((b[0] & 0xFF) << 24) | ((b[1] & 0xFF) << 16) | ((b[2] & 0xFF) << 8) | (b[3] & 0xFF)


def round_nearest_ties_even_div64(raw):
    q = math.floor(raw / 64.0)
    r = raw - q * 64
    if r < 32:
        return q
    if r > 32:
        return q + 1
    return q if (q % 2 == 0) else q + 1


def sat_int8(x):
    if x > 127:
        return 127
    if x < -128:
        return -128
    return x


def conv2d_valid_q16(input_flat, weight_flat, f_size):
    out_size = f_size - 2
    out = []
    for r in range(out_size):
        for c in range(out_size):
            acc = 0
            for kr in range(3):
                for kc in range(3):
                    xv = to_s8(input_flat[(r + kr) * f_size + (c + kc)])
                    wv = to_s8(weight_flat[kr * 3 + kc])
                    acc += xv * wv
            out.append(sat_int8(round_nearest_ties_even_div64(acc)))
    return out


def write_coe(path, words):
    with open(path, "w", encoding="utf-8") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, w in enumerate(words):
            end = ";\n" if i == len(words) - 1 else ",\n"
            f.write(f"{w & 0xFFFFFFFF:08X}{end}")


def write_mem(path, words):
    with open(path, "w", encoding="utf-8") as f:
        for w in words:
            f.write(f"{w & 0xFFFFFFFF:08X}\n")


def build_ram_case(case_idx, f_size, seed):
    rng = random.Random(seed)
    mem = [0] * MEM_DEPTH
    # Keep values moderate to reduce excessive saturation in smoke tests.
    weights = [rng.randint(-24, 24) for _ in range(9)]
    fmap = [rng.randint(-64, 63) for _ in range(f_size * f_size)]

    # Spec public weights: Weight0 at 0..2. Other weights are filled for future extension.
    for base in (0, 3, 6, 9):
        w = weights if base == 0 else [rng.randint(-24, 24) for _ in range(9)]
        mem[base + 0] = pack4(w[0:4])
        mem[base + 1] = pack4(w[4:8])
        mem[base + 2] = pack4([w[8], 0, 0, 0])

    mem[12] = ((f_size & 0x3F) << 1) | 0x1
    mem[13] = 0

    for word_i in range((len(fmap) + 3) // 4):
        mem[INPUT_BASE_WORD + word_i] = pack4(fmap[word_i * 4:word_i * 4 + 4])

    start_ctrl = 0x80000000 | ((f_size & 0xFF) << 16)
    status_word = ((OUT_START_WORD & 0x3FF) << 1) | 0x1
    mem[CONST_BASE_WORD + 0] = start_ctrl
    mem[CONST_BASE_WORD + 1] = OUT_START_WORD
    mem[CONST_BASE_WORD + 2] = 0x40000000
    mem[CONST_BASE_WORD + 3] = status_word

    golden = conv2d_valid_q16(fmap, weights, f_size)
    golden_words = [pack4(golden[i:i + 4]) for i in range(0, len(golden), 4)]
    return mem, golden, golden_words, weights, fmap


def main():
    instr_words = build_cpu_program()
    instr_full = instr_words + [0] * (MEM_DEPTH - len(instr_words))
    write_coe(GEN_DIR / "instr_mem.coe", instr_full)
    write_mem(GEN_DIR / "instr_mem.mem", instr_full)

    sizes = [10, 16, 20, 28, 32]
    summary_lines = []
    summary_lines.append("case,f_size,output_start_word,output_word_count,weight0_hex")
    for idx, f_size in enumerate(sizes):
        mem, golden, golden_words, weights, fmap = build_ram_case(idx, f_size, 20260425 + idx)
        write_coe(GEN_DIR / f"RAM_case{idx}.coe", mem)
        write_mem(GEN_DIR / f"RAM_case{idx}.mem", mem)
        write_mem(GEN_DIR / f"golden_case{idx}.mem", golden_words)
        with open(GEN_DIR / f"golden_case{idx}.txt", "w", encoding="utf-8") as f:
            for i, w in enumerate(golden_words):
                f.write(f"addr {OUT_START_WORD + i:04d}: {w:08X}\n")
        w_hex = " ".join(f"{to_u8(w):02X}" for w in weights)
        summary_lines.append(f"{idx},{f_size},{OUT_START_WORD},{len(golden_words)},{w_hex}")

    with open(GEN_DIR / "case_summary.csv", "w", encoding="utf-8") as f:
        f.write("\n".join(summary_lines) + "\n")

    print(f"Generated files under: {GEN_DIR}")
    print(f"Instruction words used: {len(instr_words)}")


if __name__ == "__main__":
    main()
