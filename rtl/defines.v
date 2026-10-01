`ifndef DEFINES_V
`define DEFINES_V

// ============================================================================
//  Meowcessor — RISC-V RV32IM Central Defines
// ============================================================================
//
//  This file contains all RISC-V instruction encoding constants (opcodes,
//  funct3, funct7) and internal ALU operation codes used throughout the CPU.
//
//  Reference: RISC-V Unprivileged ISA Specification v20191213
// ============================================================================

// ==========================  Data Widths  ===================================
`define XLEN         32
`define XLEN_BUS     31:0
`define REG_NUM      32
`define REG_ADDR_LEN 5
`define REG_ADDR_BUS 4:0
`define ALU_OP_BUS   3:0

// ==================  Instruction Opcodes (inst[6:0])  =======================
`define OP_LUI       7'b0110111   // Load Upper Immediate
`define OP_AUIPC     7'b0010111   // Add Upper Immediate to PC
`define OP_JAL       7'b1101111   // Jump And Link
`define OP_JALR      7'b1100111   // Jump And Link Register
`define OP_BRANCH    7'b1100011   // Branch (BEQ/BNE/BLT/BGE/BLTU/BGEU)
`define OP_LOAD      7'b0000011   // Load  (LB/LH/LW/LBU/LHU)
`define OP_STORE     7'b0100011   // Store (SB/SH/SW)
`define OP_OP_IMM    7'b0010011   // Register–Immediate ALU ops
`define OP_OP        7'b0110011   // Register–Register ALU ops
`define OP_MISC_MEM  7'b0001111   // FENCE / FENCE.I
`define OP_SYSTEM    7'b1110011   // ECALL / EBREAK / CSR

// ==================  funct3 Fields (inst[14:12])  ===========================

// --- BRANCH ---
`define FUNCT3_BEQ   3'b000
`define FUNCT3_BNE   3'b001
`define FUNCT3_BLT   3'b100
`define FUNCT3_BGE   3'b101
`define FUNCT3_BLTU  3'b110
`define FUNCT3_BGEU  3'b111

// --- LOAD ---
`define FUNCT3_LB    3'b000
`define FUNCT3_LH    3'b001
`define FUNCT3_LW    3'b010
`define FUNCT3_LBU   3'b100
`define FUNCT3_LHU   3'b101

// --- STORE ---
`define FUNCT3_SB    3'b000
`define FUNCT3_SH    3'b001
`define FUNCT3_SW    3'b010

// --- OP-IMM / OP (ALU) ---
`define FUNCT3_ADD_SUB    3'b000   // ADD (funct7=0), SUB (funct7=0x20)
`define FUNCT3_SLL        3'b001
`define FUNCT3_SLT        3'b010
`define FUNCT3_SLTU       3'b011
`define FUNCT3_XOR        3'b100
`define FUNCT3_SRL_SRA    3'b101   // SRL (funct7=0), SRA (funct7=0x20)
`define FUNCT3_OR         3'b110
`define FUNCT3_AND        3'b111

// --- RV32M (Multiply/Divide) — OP only, funct7 = 7'b0000001 ---
`define FUNCT3_MUL    3'b000
`define FUNCT3_MULH   3'b001
`define FUNCT3_MULHSU 3'b010
`define FUNCT3_MULHU  3'b011
`define FUNCT3_DIV    3'b100
`define FUNCT3_DIVU   3'b101
`define FUNCT3_REM    3'b110
`define FUNCT3_REMU   3'b111

// --- MISC-MEM ---
`define FUNCT3_FENCE  3'b000
`define FUNCT3_FENCEI 3'b001

// ==================  funct7 Fields (inst[31:25])  ===========================
`define FUNCT7_ZERO  7'b0000000   // ADD, SRL, SLL, SLT, SLTU, XOR, OR, AND
`define FUNCT7_SUB   7'b0100000   // SUB, SRA
`define FUNCT7_MULDIV 7'b0000001  // RV32M extension

// ==================  Internal ALU Operation Codes (4-bit)  ==================
//
//  These are the internal opcodes consumed by alu.v.  They are derived
//  from instruction fields by the decode stage and select the functional
//  unit + operation inside the ALU wrapper.
//
//  Single-cycle operations:  ALU_OP_ADD  .. ALU_OP_SLTU  (0–9)
//  Multi-cycle operations:   ALU_OP_MUL  .. ALU_OP_REMU  (10–15)
//
`define ALU_OP_ADD   4'd0    // rs1 + rs2                     (Kogge-Stone)
`define ALU_OP_SUB   4'd1    // rs1 - rs2                     (Adder: ~b + 1)
`define ALU_OP_AND   4'd2    // rs1 & rs2                     (combinational)
`define ALU_OP_OR    4'd3    // rs1 | rs2                     (combinational)
`define ALU_OP_XOR   4'd4    // rs1 ^ rs2                     (combinational)
`define ALU_OP_SLL   4'd5    // rs1 << rs2[4:0]               (shift)
`define ALU_OP_SRL   4'd6    // rs1 >> rs2[4:0]  (logical)    (shift)
`define ALU_OP_SRA   4'd7    // rs1 >>> rs2[4:0] (arithmetic) (shift)
`define ALU_OP_SLT   4'd8    // signed(rs1) < signed(rs2)     (Adder sub)
`define ALU_OP_SLTU  4'd9    // rs1 < rs2 (unsigned)          (Adder sub)
`define ALU_OP_MUL   4'd10   // (rs1 × rs2)[31:0]             (Booth radix-4)
`define ALU_OP_MULH  4'd11   // (rs1 × rs2)[63:32] signed     (Booth radix-4)
`define ALU_OP_DIV   4'd12   // signed(rs1) / signed(rs2)     (SRT radix-4)
`define ALU_OP_DIVU  4'd13   // rs1 / rs2 (unsigned)          (SRT radix-4)
`define ALU_OP_REM   4'd14   // signed(rs1) % signed(rs2)     (SRT radix-4)
`define ALU_OP_REMU  4'd15   // rs1 % rs2 (unsigned)          (SRT radix-4)

`endif
