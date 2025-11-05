const std = @import("std");
const isa = @import("isa");

/// Errors returned by an invalid usage of the decoding stages
pub const DecodeError = error{
    /// The decoder was set to an invalid alignment
    MisalignedMemoryBase,

    /// The opcode was invalid.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    UnknownOpcode,

    /// The instruction's RD was set to x0, which is ignored by an actual RV cpu.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    WritesToX0,

    /// The funct3 of the instruction is invalid.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    UnknownFunct3,

    /// The funct3 of the instruction is invalid.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    UnknownFunct7,

    /// The first 5 to 11 bits of the I-type immediate are invalid.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    UnknownShamtHigh,

    /// The imm of the ecall/ebreak instructions are unknown.
    /// This is only used while decoding a single instruction, as it is skipped over when decoding in a batch.
    UnknownImm,
};

/// A structure of arrays storing a batch of instructions and the functions needed to validate, decode, and store their fields.
/// Only values from the instructions that are actually needed during execution are kept, such as the location, the operation, rd, rs1, and rs2, and the imm.
/// NB: The vector_len parameter stores the initial vector_length of the inputted vector to decode, and is used internally to determine the vector_length of the vectors. This does not define the vector_length of the ArrayLists!
pub fn Batch(comptime vector_len: usize) !type {
    return struct {
        /// The address (in DRAM) where instructions are stored
        loc: std.mem.ArrayList(usize),

        /// The operation name (opcode)
        op: std.mem.ArrayList(isa.RV32Operation),

        /// Register fields packed together (3 x 5 bits = 15 bits, fits in u16)
        /// Format: [unused:1][rd:5][rs1:5][rs2:5]
        regs: std.mem.ArrayList(u16),

        /// Immediate value (only one immediate per instruction type, if it is even used anyways)
        /// Use i32 for all immediates because they're sign extended
        imm: std.mem.ArrayList(i32),

        /// Returns an empty instruction SoA with initialized (empty) ArrayList values
        pub fn init() Batch(vector_len) {
            return Batch(vector_len){
                .loc = std.mem.ArrayList(usize).empty,
                .op = std.mem.ArrayList(isa.RV32Operation).empty,
                .regs = std.mem.ArrayList(u16).empty,
                .imm = std.mem.ArrayList(i32).empty,
            };
        }

        /// Deallocate the ArrayLists in the struct
        pub fn deinit(self: *Batch(vector_len), allocator: std.mem.Allocator) void {
            self.loc.deinit(allocator);
            self.op.deinit(allocator);
            self.regs.deinit(allocator);
            self.imm.deinit(allocator);
        }

        /// Decode a batch of instructions, extracting every field for every instruction, using SIMD for parallelization.
        /// While the every field decoding is redundant, it reduces control flow which is more ideal for stage 2. (in theory)
        pub inline fn decode(self: *@This(), allocator: std.mem.Allocator, instruction: @Vector(vector_len, u32)) !void {
            // Masks needed for common field bit extraction, splatted into a vector. 2^[# of bits] - 1
            const mask_7bit: @Vector(vector_len, u32) = @splat(0x7f);
            const mask_5bit: @Vector(vector_len, u32) = @splat(0x1f);
            const mask_3bit: @Vector(vector_len, u32) = @splat(0x07);

            // Extract common fields using shift + mask pattern: (instruction >> bit_offset) & mask
            const opcode: @Vector(vector_len, u7) = @truncate(instruction & mask_7bit);
            const rd: @Vector(vector_len, u5) = @truncate((instruction >> @splat(7)) & mask_5bit);
            const funct3: @Vector(vector_len, u3) = @truncate((instruction >> @splat(12)) & mask_3bit);
            const rs1: @Vector(vector_len, u5) = @truncate((instruction >> @splat(15)) & mask_5bit);
            const rs2: @Vector(vector_len, u7) = @truncate((instruction >> @splat(20)) & mask_5bit);
            const funct7: @Vector(vector_len, u7) = @truncate(instruction >> @splat(25) & mask_7bit);

            const signed_instructions: @Vector(vector_len, i32) = @bitCast(instruction); // Cast to signed for use in the immediate fields

            // Bit field masks for immediate extraction
            const mask_bit_0: @Vector(vector_len, i32) = @splat(0x1);
            const mask_bits_3_0: @Vector(vector_len, i32) = @splat(0xf);
            const mask_bits_4_0: @Vector(vector_len, i32) = @splat(0x1f);
            const mask_bits_5_0: @Vector(vector_len, i32) = @splat(0x3f);
            const mask_j_imm_10_1: @Vector(vector_len, i32) = @splat(0x7fe);
            const mask_bit_11: @Vector(vector_len, i32) = @splat(0x800);
            const mask_j_imm_19_12: @Vector(vector_len, i32) = @splat(0xff000);
            const mask_u_imm_31_12: @Vector(vector_len, u32) = @splat(0xFFFFF000);

            // Inverse masks for preserving upper bits
            const inv_mask_bits_4_0: @Vector(vector_len, i32) = @splat(~@as(i32, 0x1f));
            const inv_mask_bits_11_0: @Vector(vector_len, i32) = @splat(~@as(i32, 0xfff));
            const inv_mask_bits_20_0: @Vector(vector_len, i32) = @splat(~@as(i32, 0x1fffff));

            const imm_i: @Vector(vector_len, i32) = signed_instructions >> @splat(20); // I-type: imm[11:0] at bits [31:20]

            // S-type: imm[11:5] at [31:25] | imm[4:0] at [11:7]
            // Reassemble split immediate with sign extension from bit 31
            const s_upper: @Vector(vector_len, i32) = signed_instructions >> @splat(20); // Sign-extends from bit 31
            const s_lower: @Vector(vector_len, i32) = signed_instructions >> @splat(7) & mask_bits_4_0;
            const imm_s: @Vector(vector_len, i32) = (s_upper & inv_mask_bits_4_0) | s_lower;

            // B-type: imm[12] at [31] | imm[10:5] at [30:25] | imm[4:1] at [11:8] | imm[11] at [7]
            // Note: bit 0 is implicitly 0 (instruction are 2-byte aligned)
            const b_12: @Vector(vector_len, i32) = signed_instructions >> @splat(19); // Sign-extend from bit 12
            const b_11: @Vector(vector_len, i32) = (signed_instructions >> @splat(7)) & mask_bit_0;
            const b_10_5: @Vector(vector_len, i32) = (signed_instructions >> @splat(25)) & mask_bits_5_0;
            const b_4_1: @Vector(vector_len, i32) = (signed_instructions >> @splat(8)) & mask_bits_3_0;
            const imm_b: @Vector(vector_len, i32) = (b_12 & inv_mask_bits_11_0) | (b_11 << @splat(11)) | (b_10_5 << @splat(5)) | (b_4_1 << @splat(1));

            // U-type: imm[31:12] at [31:12], lower 12 bits are zero
            // Used by LUI (load upper immediate) and AUIPC (add upper immediate to PC)
            const imm_u: @Vector(vector_len, i32) = @bitCast(instruction & mask_u_imm_31_12);

            // J-type: imm[20] at [31] | imm[10:1] at [30:21] | imm[11] at [20] | imm[19:12] at [19:12]
            // Note: bit 0 is implicitly 0 (instructions are 2-byte aligned)
            const j_20: @Vector(vector_len, i32) = signed_instructions >> @splat(11);
            const j_19_12: @Vector(vector_len, i32) = signed_instructions & mask_j_imm_19_12;
            const j_11: @Vector(vector_len, i32) = (signed_instructions >> @splat(9)) & mask_bit_11;
            const j_10_1: @Vector(vector_len, i32) = (signed_instructions >> @splat(20)) & mask_j_imm_10_1;
            const imm_j: @Vector(vector_len, i32) = (j_20 & inv_mask_bits_20_0) | j_19_12 | j_11 | j_10_1;

            for (0..vector_len) |i| {
                switch (opcode[i]) {
                    0b0110011 => { // R type instruction
                        if (rd[i] == 0b00000) {
                            @branchHint(.cold);
                            std.log.warn("R-type instruction 0x{X} of opcode 0b0110011 has rd set to x0, skipping. (i = {d})\n", .{ instruction[i], i });
                            continue;
                        }

                        switch (funct3[i]) {
                            0x0 => {
                                switch (funct7[i]) {
                                    0x00 => try self.appendInstruction(allocator, i, isa.RV32Operation.add, packRegs(rd[i], rs1[i], rs2[i]), 0), // R type instructions do not have an imm, appending zero
                                    0x20 => try self.appendInstruction(allocator, i, isa.RV32Operation.sub, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x0, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] }),
                                }
                            },
                            0x1 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.sll, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x1, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x2 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.slt, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x2, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x3 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.sltu, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x3, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x4 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.xor, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x4, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x5 => {
                                switch (funct7[i]) {
                                    0x00 => try self.appendInstruction(allocator, i, isa.RV32Operation.srl, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    0x20 => try self.appendInstruction(allocator, i, isa.RV32Operation.sra, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    else => {
                                        std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x5, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                        continue;
                                    },
                                }
                            },
                            0x6 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.OR, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x6, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x7 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.AND, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011, funct3 of 0x7, but an unknown funct7 of 0x{X}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011 but unknown funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b0010011 => { // I type instruction
                        if (rd[i] == 0b00000) {
                            @branchHint(.cold);
                            std.log.warn("I-type instruction 0x{X} of opcode 0b0010011 has rd set to x0, skipping. (i = {d})\n", .{ instruction[i], i });
                            continue;
                        }

                        switch (funct3[i]) {
                            0x0 => try self.appendInstruction(allocator, i, isa.RV32Operation.addi, packRegs(rd[i], rs1[i], 0), imm_i[i]),
                            0x1 => {
                                const shamt_high: u7 = @truncate((imm_i[i] >> 5) & 0x7f);
                                if (shamt_high == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.slli, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]) else {
                                    std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid I-type opcode of 0b0010011 and valid funct3 of 0x1 but invalid shamt_high of 0x{X}\n", .{ instruction[i], i, shamt_high });
                                }
                            },
                            0x2 => try self.appendInstruction(allocator, i, isa.RV32Operation.slti, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x3 => try self.appendInstruction(allocator, i, isa.RV32Operation.sltiu, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x4 => try self.appendInstruction(allocator, i, isa.RV32Operation.xori, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x5 => {
                                const shamt_high: u7 = @truncate((imm_i[i] >> 5) & 0x7f);
                                switch (shamt_high) {
                                    0x00 => try self.appendInstruction(allocator, i, isa.RV32Operation.srli, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                                    0x20 => try self.appendInstruction(allocator, i, isa.RV32Operation.srai, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                                    else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid I-type opcode of 0b0010011, valid funct3 of 0x5, but invalid shamt_high of 0x{X}\n", .{ instruction[i], i, shamt_high }),
                                }
                            },
                            0x6 => try self.appendInstruction(allocator, i, isa.RV32Operation.ori, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x7 => try self.appendInstruction(allocator, i, isa.RV32Operation.ori, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid I-type opcode of 0b0010011 but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b0000011 => { // I type instruction (load)
                        if (rd[i] == 0b00000) {
                            std.log.warn("I-type instruction 0x{X} of opcode 0b0000011 has rd set to x0, skipping. (i = {d})\n", .{ instruction[i], i });
                            continue;
                        }

                        switch (funct3[i]) {
                            0x0 => try self.appendInstruction(allocator, i, isa.RV32Operation.lb, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x1 => try self.appendInstruction(allocator, i, isa.RV32Operation.lh, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x2 => try self.appendInstruction(allocator, i, isa.RV32Operation.lw, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x4 => try self.appendInstruction(allocator, i, isa.RV32Operation.lbu, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            0x5 => try self.appendInstruction(allocator, i, isa.RV32Operation.lhu, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid I type opcode of 0b0000011 (load) but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b0100011 => { // S type instruction
                        if (rd[i] == 0b00000) {
                            @branchHint(.cold);
                            std.log.warn("S-type instruction 0x{X} of opcode has 0b0100011 rd set to x0, skipping. (i = {d})\n", .{ instruction[i], i });
                            continue;
                        }

                        switch (funct3[i]) {
                            0x0 => try self.appendInstruction(allocator, i, isa.RV32Operation.sb, packRegs(rd[i], rs1[i], rs2[i]), imm_s[i]),
                            0x1 => try self.appendInstruction(allocator, i, isa.RV32Operation.sh, packRegs(rd[i], rs1[i], rs2[i]), imm_s[i]),
                            0x2 => try self.appendInstruction(allocator, i, isa.RV32Operation.sw, packRegs(rd[i], rs1[i], rs2[i]), imm_s[i]),
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid S type opcode of 0b0100011 but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b1100011 => { // B type instruction
                        switch (funct3[i]) {
                            0x0 => try self.appendInstruction(allocator, i, isa.RV32Operation.beq, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            0x1 => try self.appendInstruction(allocator, i, isa.RV32Operation.bne, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            0x4 => try self.appendInstruction(allocator, i, isa.RV32Operation.blt, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            0x5 => try self.appendInstruction(allocator, i, isa.RV32Operation.bge, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            0x6 => try self.appendInstruction(allocator, i, isa.RV32Operation.bltu, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            0x7 => try self.appendInstruction(allocator, i, isa.RV32Operation.bgeu, packRegs(rd[i], rs1[i], rs2[i]), imm_b[i]),
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid B type opcode but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b1100111 => {
                        if (funct3[i] == 0x0) {
                            try self.appendInstruction(allocator, i, isa.RV32Operation.jalr, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]);
                        } else std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid jalr opcode of 0b1100111 but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] });
                    },
                    0b1101111 => {
                        if (funct3[i] == 0x0) {
                            try self.appendInstruction(allocator, i, isa.RV32Operation.jal, packRegs(rd[i], rs1[i], rs2[i]), imm_j[i]);
                        } else std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid jal opcode of 0b1101111 but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] });
                    },
                    0b0110111 => try self.appendInstruction(allocator, i, isa.RV32Operation.lui, packRegs(rd[i], rs1[i], rs2[i]), imm_u[i]),
                    0b0010111 => try self.appendInstruction(allocator, i, isa.RV32Operation.auipc, packRegs(rd[i], rs1[i], rs2[i]), imm_u[i]),
                    0b1110011 => { // ecall and ebreak
                        if (funct3[i] == 0x0) {
                            switch (imm_i[i]) {
                                0x0 => try self.appendInstructionI(allocator, i, isa.RV32Operation.ecall, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                                0x1 => try self.appendInstructionI(allocator, i, isa.RV32Operation.ebreak, packRegs(rd[i], rs1[i], rs2[i]), imm_i[i]),
                                else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid ecall/ebreak opcode of 0b1110011 and valid funct3 of 0x0 but invalid imm of 0x{X}\n", .{ instruction[i], i, imm_i[i] }),
                            }
                        } else std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid ecall/ebreak opcode of 0b1110011 but invalid funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] });
                    },
                    else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having an unknown opcode of 0x{X}\n", .{ instruction[i], i, opcode[i] }),
                }
            }
        }

        /// Appends the fields for an instruction to the validated instruction structure of arrays
        pub inline fn appendInstruction(self: *Batch(vector_len), allocator: std.mem.Allocator, i: usize, opcode: isa.RV32Operation, regs: u16, imm: i32) !void {
            std.log.debug("Validated and appending instruction of operation of opcode {}, with packed registers 0x{X}, imm 0x{X} from address 0x{X}. i = {d}\n", .{ opcode, regs, imm, self.base + (i * 4), i });

            try self.loc.append(allocator, self.base + (i * 4));
            try self.op.append(allocator, opcode);
            try self.regs.append(allocator, regs);
            try self.imm.append(allocator, imm);
        }
    };
}

/// A single decoded instruction.
/// This is optimized for just one instruction and should not be used to decode multiple instructions in a loop.
pub const Single = struct {
    /// The address that the instruction is stored in, used for the program counter if need be.
    addr: ?usize,

    /// The enumerated operation itself
    op: isa.RV32Operation,

    /// The registers, packed into a single sixteen bit integer
    regs: u16,

    /// The immediate value, sign extended.
    /// This will be null if the instruction does not have an imm field. (r-type instructions for example)
    imm: ?i32,

    pub fn decode(instruction: u32, addr: ?usize) DecodeError!Single {
        const mask_7bit = 0x7f;
        const mask_5bit = 0x1f;
        const mask_3bit = 0x07;

        const opcode: u7 = instruction & mask_7bit;
        switch (opcode) { // The following is optimized by "lazy" extracting fields, only once they are truly needed. This make make code look repetitive.
            0b0110011 => {
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) {
                    @branchHint(.cold); // This is a rare error, so tell the compiler that.
                    return DecodeError.WritesToX0;
                }

                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                switch (funct3) {
                    0x0 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        switch (funct7) {
                            0x00 => {
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                                return Single{
                                    .addr = addr,
                                    .op = isa.RV32Operation.add,
                                    .regs = packRegs(rd, rs1, rs2),
                                    .imm = null,
                                };
                            },
                            0x20 => {
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                                return Single{
                                    .addr = addr,
                                    .op = isa.RV32Operation.sub,
                                    .regs = packRegs(rd, rs1, rs2),
                                    .imm = null,
                                };
                            },
                            else => return DecodeError.UnknownFunct7,
                        }
                    },
                    0x1 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.sll, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                    0x2 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.slt, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                    0x3 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.sltu, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                    0x4 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.xor, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                    0x5 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        switch (funct7) {
                            0x00 => {
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                                return Single{
                                    .addr = addr,
                                    .op = isa.RV32Operation.srl,
                                    .regs = packRegs(rd, rs1, rs2),
                                    .imm = null,
                                };
                            },
                            0x20 => {
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                                return Single{
                                    .addr = addr,
                                    .op = isa.RV32Operation.sra,
                                    .regs = packRegs(rd, rs1, rs2),
                                    .imm = null,
                                };
                            },
                            else => return DecodeError.UnknownFunct7,
                        }
                    },
                    0x6 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.OR, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                    0x7 => {
                        const funct7: u7 = @truncate((instruction >> 25) & mask_7bit);
                        if (funct7 == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                            return Single{ .addr = addr, .op = isa.RV32Operation.AND, .regs = packRegs(rd, rs1, rs2), .imm = null };
                        } else return DecodeError.UnknownFunct7;
                    },
                }
            },
            0b0010011 => { // I type instruction
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) {
                    @branchHint(.unlikely); // This is a rare error, so tell the compiler that.
                    return DecodeError.WritesToX0;
                }

                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                switch (funct3) {
                    0x0 => { // addi
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.addi, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x1 => { // slli
                        const signed_instruction: i32 = @bitCast(instruction);
                        const imm = signed_instruction >> 20;

                        const shamt_high: u7 = @truncate((imm >> 5) & mask_7bit);
                        if (shamt_high == 0x00) {
                            const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                            return Single{ .addr = addr, .op = isa.RV32Operation.slli, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                        }

                        return DecodeError.UnknownShamtHigh;
                    },
                    0x2 => { // slti
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.slti, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x3 => { // sltiu
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.sltiu, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x4 => { // xori
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);

                        const signed_instruction: i32 = @bitCast(instruction);
                        const imm = signed_instruction >> 20;

                        return Single{ .addr = addr, .op = isa.RV32Operation.xori, .regs = packRegs(rd, rs1, 0), .imm = imm };
                    },
                    0x5 => { // srli or srai, depending on imm
                        const imm = getImmI(instruction);

                        const shamt_high: u7 = @truncate((imm >> 5) & mask_7bit);

                        switch (shamt_high) {
                            0x00 => { // srli
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                return Single{ .addr = addr, .op = isa.RV32Operation.srli, .regs = packRegs(rd, rs1, 0), .imm = imm };
                            },
                            0x20 => { // srai
                                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                                return Single{ .addr = addr, .op = isa.RV32Operation.srai, .regs = packRegs(rd, rs1, 0), .imm = imm };
                            },
                            else => return DecodeError.UnknownFunct7,
                        }
                    },
                    0x6 => { // ori
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.ori, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x7 => { // andi
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.andi, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    else => return DecodeError.UnknownFunct3,
                }
            },
            0b0000011 => { // load instruction (I-type)
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) {
                    @branchHint(.unlikely); // This is a rare error, so tell the compiler that.
                    return DecodeError.WritesToX0;
                }

                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                switch (funct3) {
                    0x0 => { // load byte
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.lb, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) }; // rs2 isn't used in this instruction type, so it is set to 0
                    },
                    0x1 => { // load half
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.lh, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x2 => { // load word
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.lw, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x4 => { // load byte (u)
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.lbu, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    0x5 => { // load half (u)
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.lhu, .regs = packRegs(rd, rs1, 0), .imm = getImmI(instruction) };
                    },
                    else => return DecodeError.UnknownFunct3,
                }
            },
            0b0100011 => { // S-type instruction
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) {
                    @branchHint(.cold); // This is a rare error, so tell the optimizer that it is.
                    return DecodeError.WritesToX0;
                }

                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                switch (funct3) {
                    0x0 => { // sb
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.sb, .regs = packRegs(rd, rs1, rs2), .imm = getImmS(instruction) };
                    },
                    0x1 => { // sh
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.sh, .regs = packRegs(rd, rs1, rs2), .imm = getImmS(instruction) };
                    },
                    0x2 => { // sw
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.sw, .regs = packRegs(rd, rs1, rs2), .imm = getImmS(instruction) };
                    },
                    else => return DecodeError.UnknownFunct3,
                }
            },
            0b1100011 => { // b-type (branch) instruction
                // no rd check because b type instructions only change the program counter
                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                switch (funct3) {
                    0x0 => { // beq
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.beq, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    0x1 => { // bne
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.bne, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    0x4 => { // blt
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.blt, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    0x5 => { // bge
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.bge, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    0x6 => { // bltu
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.bltu, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    0x7 => { // bgeu
                        const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                        const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);
                        return Single{ .addr = addr, .op = isa.RV32Operation.bltu, .regs = packRegs(0, rs1, rs2), .imm = getImmB(instruction) };
                    },
                    else => return DecodeError.UnknownFunct3,
                }
            },
            0b1101111 => { // jal
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) return DecodeError.WritesToX0;

                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                const rs2: u5 = @truncate((instruction >> 20) & mask_5bit);

                const mask_bit_11: i32 = 0x800;
                const mask_j_imm_19_12: i32 = 0xff000;
                const mask_j_imm_10_1: i32 = 0x7fe;
                const inv_mask_bits_20_0: i32 = ~0x1fffff;
                const signed_instruction: i32 = @bitCast(instruction);

                const j_20 = signed_instruction >> 11;
                const j_19_12 = signed_instruction & mask_j_imm_19_12;
                const j_11 = (signed_instruction >> 9) & mask_bit_11;
                const j_10_1 = (signed_instruction >> 20) & mask_j_imm_10_1;

                const imm = (j_20 & inv_mask_bits_20_0) | j_19_12 | j_11 | j_10_1;

                return Single{ .addr = addr, .op = isa.RV32Operation.jal, .regs = packRegs(rd, rs1, rs2), .imm = imm };
            },
            0b1100111 => { // jalr
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) return DecodeError.WritesToX0;

                const rs1: u5 = @truncate((instruction >> 15) & mask_5bit);
                const rs2: u5 = 0; // rs2 isn't used in this instruction

                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                if (funct3 != 0x0) return DecodeError.UnknownFunct3;

                return Single{ .addr = addr, .op = isa.RV32Operation.jalr, .regs = packRegs(rd, rs1, rs2), .imm = getImmB(instruction) };
            },
            0b10110111 => { // lui
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) return DecodeError.WritesToX0;
                return Single{ .addr = addr, .op = isa.RV32Operation.lui, .regs = packRegs(rd, 0, 0), .imm = getImmU(instruction) };
            },
            0b0010111 => { // auipc
                const rd: u5 = @truncate((instruction >> 7) & mask_5bit);
                if (rd == 0b00000) return DecodeError.WritesToX0;

                return Single{ .addr = addr, .op = isa.RV32Operation.auipc, .regs = packRegs(rd, 0, 0), .imm = getImmU(instruction) };
            },
            0b1110011 => {
                const funct3: u3 = @truncate((instruction >> @splat(12)) & mask_3bit);
                if (funct3 != 0x0) return isa.RV32Operation.UnknownFunct3;

                const imm = getImmI(instruction);

                switch (imm) {
                    0x0 => return Single{ .addr = addr, .op = isa.RV32Operation.ecall, .regs = 0, .imm = imm }, // Regs is set to zero because they aren't used
                    0x1 => return Single{ .addr = addr, .op = isa.RV32Operation.ebreak, .regs = 0, .imm = imm }, // Ditto
                }
            },
            else => return DecodeError.UnknownOpcode,
        }

        // The above switch statement should have returned something, so this section of the code is unreachable
        unreachable;
    }

    /// Extract the immediate value from a raw 32 bit I-type instruction. 
    /// This function does not perform any validation.
    inline fn getImmI(instruction: u32) i32 {
        const signed_instruction: i32 = @bitCast(instruction);
        return signed_instruction >> 20;
    }

    /// Extract the immediate value from a raw 32 bit S-type instruction. 
    /// This function does not perform any validation.
    inline fn getImmS(instruction: u32) i32 {
        const signed_instruction: i32 = @bitCast(instruction);
        const mask_bits_4_0: i32 = 0x1f; // mask_5bit but i32
        const inv_mask_bits_4_0: i32 = ~0x1f; // inverted
        const s_upper: i32 = signed_instruction >> 20; // Sign extends from bit 31
        const s_lower: i32 = signed_instruction >> 7 & mask_bits_4_0;

        return (s_upper & inv_mask_bits_4_0) | s_lower;
    }

    /// Extract the immediate value from a raw 32 bit B-type instruction. 
    /// This function does not perform any validation.
    inline fn getImmB(instruction: u32) i32 {
        const signed_instruction: i32 = @bitCast(instruction);

        const inv_mask_bits_11_0: i32 = ~0x1fffff;
        const b_12 = signed_instruction >> 19; // sign-extend from bit 12
        const b_11 = (signed_instruction >> 7) & 0x1;
        const b_10_5 = (signed_instruction >> 8) & 0x3f;
        const b_4_1 = (signed_instruction >> 8) & 0xf;

        return (b_12 & inv_mask_bits_11_0) | (b_11 << 11) | (b_10_5 << 5) | (b_4_1 << 1);
    }

    inline fn getImmU(instruction: u32) i32 {
        const mask_u_imm_31_12: u32 = 0xFFFFF000;
        return @bitCast(instruction & mask_u_imm_31_12);
    }
};

/// Helper function to pack the rd, rs1, and rs2 values into a single u16
pub inline fn packRegs(rd: u5, rs1: u5, rs2: u5) u16 {
    return (@as(u16, rd) << 10) | (@as(u16, rs1) << 5) | @as(u16, rs2);
}

/// Helper function to extract rd from a packed 16 bit integer
pub inline fn getRd(regs: u16) u5 {
    return @truncate((regs >> 10) & 0x1f);
}

/// Helper function to extract rs1 from a packed 16 bit integer
pub inline fn getRs1(regs: u16) u5 {
    return @truncate((regs >> 5) & 0x1f);
}

/// Helper function to extract rs1 from a packed 16 bit integer
pub inline fn getRs2(regs: u16) u5 {
    return @truncate(regs & 0x1f);
}
