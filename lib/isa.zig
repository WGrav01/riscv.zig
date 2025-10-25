//! Definitions for instruction sets and extensions

/// Enum for which base instruction set is in use
pub const Base = enum {
    /// 32 bit base integer instruction set
    rv32i,

    /// Embedded version of the 32 bit base integer instruction set, with 16 registers
    rv32e,

    /// 64 bit base integer instruction set
    rv64i,

    /// 128 bit base integer instruction set
    rv128i,
};

/// Struct that defines what extensions are in use
pub const Extensions = enum {
    /// Standard Extension for Integer Multiplication and Division
    m,

    /// Standard Extension for Atomic Instructions
    a,

    /// Standard Extension for Single-Precision Floating-Point
    f,

    /// Standard Extension for Double-Precision Floating-Point
    d,

    /// Shorthand for the base and above extensions
    g,

    /// Standard Extension for Quad-Precision Floating-Point
    q,

    /// Standard Extension for Decimal Floating-Point
    l,

    /// Standard Extension for Compressed Instructions
    c,

    /// Standard Extension for Bit Manipulation
    b,

    /// Standard Extension for Dynamically Translated Languages
    j,

    /// Standard Extension for Transactional Memory
    t,

    /// Standard Extension for Packed-SIMD Instructions
    p,

    /// Standard Extension for Vector Operations
    v,

    /// Standard Extension for User-Level Interrupts
    n,

    /// Standard Extension for Hypervisor
    h,

    /// Standard Extension for Supervisor-level Instructions
    s,
};

/// Helper enum for the RISC-V instruction types. They are designated by their 7 bit opcode. (bits 0 to 6 in an instruction)
pub const InstructionFormat = enum(u7) {
    R = 0b0110011,
    I = 0b0010011,
    S = 0b0100011,
    B = 0b1100011,
    J = 0b1101111,
    U = 0b0110111,
};

/// Enum for RV32 operations. (opcodes/instructions) Currently only base integer instructions are left in here.
pub const RV32Operation = enum {
    /// Add:
    /// rd = rs1 + rs2
    add,

    /// Sub:
    /// rd = rs1 - rs2
    sub,

    /// Bitwise exclusive OR:
    /// rd = rs1 ˆ rs2
    xor,

    /// Bitwise OR:
    /// rd = rs1 | rs2
    OR, // Uppercase because "or" is a zig keyword

    /// Bitwise AND:
    /// rd = rs1 & rs2
    AND, // Likewise for or

    /// Shift left logical:
    /// rd = rs1 << rs2
    sll,

    /// Shift right logical:
    /// rd = rs1 >> rs2
    srl,

    /// Shift Right Arith
    /// rd = rs1 >> rs2
    /// msb-extends
    sra,

    /// Set Less Than
    /// rd = (rs1 < rs2)?1:0
    slt,

    /// Set Less then (U)
    /// rd = (rs1 < rs2)?1:0
    /// zero-extends
    sltu,

    /// ADD Immediate
    /// rd = rs1 + imm
    addi,

    /// XOR Immediate
    /// rd = rs1 ˆ imm
    xori,

    /// OR Immediate
    /// rd = rs1 | imm
    ori,

    /// AND Immediate
    /// rd = rs1 & imm
    andi,

    /// Shift Left Logical Imm
    /// rd = rs1 << imm[0:4]
    slli,

    /// Shift Right Logical Imm
    /// rd = rs1 >> imm[0:4]
    srli,

    /// Shift Right Arith Imm
    /// rd = rs1 >> imm[0:4]
    /// msb-extends
    srai,

    /// Set Less Than Imm
    /// rd = (rs1 < imm)?1:0
    slti,

    /// Set Less Than Imm (u)
    /// rd = (rs1 < imm)?1:0
    /// zero-extends
    sltiu,

    /// Load Byte
    /// rd = M[rs1+imm][0:7]
    lb,

    /// Load Half
    /// rd = M[rs1+imm][0:15]
    lh,

    /// Load Word
    /// rd = M[rs1+imm][0:31]
    lw,

    /// Load Byte (U)
    /// rd = M[rs1+imm][0:7]
    /// zero-extends
    lbu,

    /// Load Half (U)
    /// rd = M[rs1+imm][0:15]
    /// zero-extends
    lhu,

    /// Environment call
    /// Transfer control to OS
    ecall,

    /// Environment Break
    /// Transfer control to debugger
    ebreak,

    /// Store Byte
    /// M[rs1+imm][0:7] = rs2[0:7]
    sb,

    /// Store Half
    /// M[rs1+imm][0:15] = rs2[0:15]
    sh,

    /// Store Word
    /// M[rs1+imm][0:31] = rs2[0:31]
    sw,
};
