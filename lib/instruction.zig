const std = @import("std");
const isa = @import("isa");

/// Errors returned by an invalid usage of the decoding stages
pub const DecodeError = error{
    /// The decoder was set to an invalid alignment
    MisalignedMemoryBase
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

        /// Extract rd from packed register field
        pub inline fn getRd(regs: u16) u5 {
            return @truncate((regs >> 10) & 0x1f);
        }

        /// Extract rs1 from packed register field
        pub inline fn getRs1(regs: u16) u5 {
            return @truncate((regs >> 5) & 0x1f);
        }

        /// Extract rs2 from packed register field
        pub inline fn getRs2(regs: u16) u5 {
            return @truncate(regs & 0x1f);
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
                            std.log.warn("R-type instruction 0x{X} of opcode 0b0110011 has rd set to x0, skipping. (i = {d})\n", .{ instruction[i], i });
                            continue;
                        }
                        
                        switch (funct3[i]) {
                            0x0 => {
                                switch (funct7[i]) {
                                    0x00 => try self.appendInstruction(allocator, i, isa.RV32Operation.add, packRegs(rd[i], rs1[i], rs2[i]), 0), // R type instructions do not have an imm, appending zero
                                    0x20 => try self.appendInstruction(allocator, i, isa.RV32Operation.sub, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    else => std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x0, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] }),
                                }
                            },
                            0x1 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.sll, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x1, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x2 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.slt, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x2, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x3 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.sltu, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x3, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x4 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.xor, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x4, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x5 => {
                                switch (funct7[i]) {
                                    0x00 => try self.appendInstruction(allocator, i, isa.RV32Operation.srl, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    0x20 => try self.appendInstruction(allocator, i, isa.RV32Operation.sra, packRegs(rd[i], rs1[i], rs2[i]), 0),
                                    else => {
                                        std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x5, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                        continue;
                                    }
                                }
                            },
                            0x6 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.OR, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x6, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            0x7 => {
                                if (funct7[i] == 0x00) try self.appendInstruction(allocator, i, isa.RV32Operation.AND, packRegs(rd[i], rs1[i], rs2[i]), 0) else {
                                    std.log.debug("Skipping instruction 0x{} (i = {}) due to having valid R-type opcode of 0b0110011, funct3 of 0x7, but an unknown funct7 of {}\n", .{ instruction[i], i, funct7[i] });
                                    continue;
                                }
                            },
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode of 0b0110011 but unknown funct3 of 0x{X}\n", .{ instruction[i], i, funct3[i] }),
                        }
                    },
                    0b0010011 => { // I type instruction
                        if (rd[i] == 0b00000) {
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
                                else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid ecall/ebreak opcode of 0b1110011 but invalid imm of 0x{X}\n", .{ instruction[i], i, imm_i[i] }),
                            }
                        }
                    },
                    else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having an unknown opcode of 0x{X}\n", .{ instruction[i], i, opcode[i] }),
                }
            }
        }

        /// Pack the rd, rs1, and rs2 values into a single u16 to append to .regs
        pub inline fn packRegs(rd: u5, rs1: u5, rs2: u5) u16 {
            return (@as(u16, rd) << 10) | (@as(u16, rs1) << 5) | @as(u16, rs2);
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