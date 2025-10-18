/// Helper enum for the RISC-V instruction types. They are designated by their 7 bit opcode. (bits 0 to 6 in an instruction)
const InstructionFormat = enum(u7) {
    R = 0b0110011,
    I = 0b0010011,
    S = 0b0100011,
    B = 0b1100011,
    J = 0b1101111,
    U = 0b0110111,
};

/// An enum for RV32 Base Integer instructions, R type, or register to register instructions
const RV32I_Instruction_R = enum {
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
    AND, // Likewise

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
};

const RV32I_Instruction_I = enum {
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
};

const RV32I_Instruction_S = enum {
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
