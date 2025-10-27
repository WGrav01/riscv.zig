/// Errors returned by an invalid usage of the decoding stages
pub const DecodeError = error{
    /// The decoder was set to an invalid alignment
    MisalignedMemoryAccess
};

/// Struct that holds a batch of instructions in vector form for the first stage of decoding.
/// The decode function is ran at comptime as the vectors' length needs to be known then, and unless the instructions are comptime known, the instructions will be decoded at runtime by calling the decode function.
pub fn Decoder(comptime len: usize, base: usize) type {
    return struct {
        /// The start address of the instruction block
        base: usize = base,

        instruction: [len]u32,

        /// The specific type of instruction. This field is present in all instruction types.
        opcode: @Vector(len, u7),

        /// The destination register. This is present in all instruction types except for S and B, where it uses imm[4:0] and imm[4:1|11], likewise
        rd: @Vector(len, u5),

        /// The operation field, present in all instruction types except for U and J, where a single immediate value replaces every field except for the rd and opcode fields.
        funct3: @Vector(len, u3),

        /// The first source register for the instruction. Like funct3, it is present in all instruction types except for U and J.
        rs1: @Vector(len, u5),

        /// The second source register to be used in the instruction. Present in R, S, and B instruction types.
        rs2: @Vector(len, u5),

        /// A last 7 bits specifying additional execution details in an R type instruction.
        /// Also used as imm[5:11]
        funct7: @Vector(len, u7),

        /// I-type immediate value: imm[11:0], replacing the rd field.
        imm_i: @Vector(len, i32),

        /// S-type: imm[11:5|4:0]
        imm_s: @Vector(len, i32),

        /// B-type: imm[12|10:5|4:1|11]
        imm_b: @Vector(len, i32),

        /// U-type: imm[31:12]
        imm_u: @Vector(len, i32),

        /// J-type: imm[20|10:1|11|19:12]
        imm_j: @Vector(len, i32),

        /// Decode a batch of instructions, extracting every field for every instruction, using SIMD for parallelization.
        /// While the every field decoding is redundant, it reduces control flow which is more ideal for stage 2. (in theory)
        pub inline fn decode(self: *@This(), instructions: @Vector(len, u32)) !void {
            if (self.base % 4 != 0) return DecodeError.MisalignedMemoryAccess;

            self.instructions = instructions;

            // Masks needed for common field bit extraction, splatted into a vector. 2^[# of bits] - 1
            const mask_7bit: @Vector(len, u32) = @splat(0x7f);
            const mask_5bit: @Vector(len, u32) = @splat(0x1f);
            const mask_3bit: @Vector(len, u32) = @splat(0x07);

            // Extract common fields using shift + mask pattern: (instruction >> bit_offset) & mask
            self.opcode = @truncate(instructions & mask_7bit);
            self.rd = @truncate((instructions >> @splat(7)) & mask_5bit);
            self.funct3 = @truncate((instructions >> @splat(12)) & mask_3bit);
            self.rs1 = @truncate((instructions >> @splat(15)) & mask_5bit);
            self.rs2 = @truncate((instructions >> @splat(20)) & mask_5bit);
            self.funct7 = @truncate(instructions >> @splat(25) & mask_7bit);

            const signed_instructions: @Vector(len, i32) = @bitCast(instructions); // Cast to signed for use in the immediate fields

            // Bit field masks for immediate extraction
            const mask_bit_0: @Vector(len, i32) = @splat(0x1);
            const mask_bits_3_0: @Vector(len, i32) = @splat(0xf);
            const mask_bits_4_0: @Vector(len, i32) = @splat(0x1f);
            const mask_bits_5_0: @Vector(len, i32) = @splat(0x3f);
            const mask_j_imm_10_1: @Vector(len, i32) = @splat(0x7fe);
            const mask_bit_11: @Vector(len, i32) = @splat(0x800);
            const mask_j_imm_19_12: @Vector(len, i32) = @splat(0xff000);
            const mask_u_imm_31_12: @Vector(len, u32) = @splat(0xFFFFF000);

            // Inverse masks for preserving upper bits
            const inv_mask_bits_4_0: @Vector(len, i32) = @splat(~@as(i32, 0x1f));
            const inv_mask_bits_11_0: @Vector(len, i32) = @splat(~@as(i32, 0xfff));
            const inv_mask_bits_20_0: @Vector(len, i32) = @splat(~@as(i32, 0x1fffff));

            self.imm_i = signed_instructions >> @splat(20); // I-type: imm[11:0] at bits [31:20]

            // S-type: imm[11:5] at [31:25] | imm[4:0] at [11:7]
            // Reassemble split immediate with sign extension from bit 31
            const s_upper: @Vector(len, i32) = signed_instructions >> @splat(20); // Sign-extends from bit 31
            const s_lower: @Vector(len, i32) = signed_instructions >> @splat(7) & mask_bits_4_0;
            self.imm_s = (s_upper & inv_mask_bits_4_0) | s_lower;

            // B-type: imm[12] at [31] | imm[10:5] at [30:25] | imm[4:1] at [11:8] | imm[11] at [7]
            // Note: bit 0 is implicitly 0 (instructions are 2-byte aligned)
            const b_12: @Vector(len, i32) = signed_instructions >> @splat(19); // Sign-extend from bit 12
            const b_11: @Vector(len, i32) = (signed_instructions >> @splat(7)) & mask_bit_0;
            const b_10_5: @Vector(len, i32) = (signed_instructions >> @splat(25)) & mask_bits_5_0;
            const b_4_1: @Vector(len, i32) = (signed_instructions >> @splat(8)) & mask_bits_3_0;
            self.imm_b = (b_12 & inv_mask_bits_11_0) | (b_11 << @splat(11)) | (b_10_5 << @splat(5)) | (b_4_1 << @splat(1));

            // U-type: imm[31:12] at [31:12], lower 12 bits are zero
            // Used by LUI (load upper immediate) and AUIPC (add upper immediate to PC)
            self.imm_u = @bitCast(instructions & mask_u_imm_31_12);

            // J-type: imm[20] at [31] | imm[10:1] at [30:21] | imm[11] at [20] | imm[19:12] at [19:12]
            // Note: bit 0 is implicitly 0 (instructions are 2-byte aligned)
            const j_20: @Vector(len, i32) = signed_instructions >> @splat(11);
            const j_19_12: @Vector(len, i32) = signed_instructions & mask_j_imm_19_12;
            const j_11: @Vector(len, i32) = (signed_instructions >> @splat(9)) & mask_bit_11;
            const j_10_1: @Vector(len, i32) = (signed_instructions >> @splat(20)) & mask_j_imm_10_1;
            self.imm_j = (j_20 & inv_mask_bits_20_0) | j_19_12 | j_11 | j_10_1;
        }
    };
}

const std = @import("std");
const ArrayList = @import("std").ArrayList;
const Allocator = @import("std").mem.Allocator;
const isa = @import("isa.zig");

/// Stage two of decoding: Validate the instructions, and store only the valid ones in an array.
/// This ensures that only valid decoded instructions are executed, and removes the need for validation during the execution stage.
/// Only values actually needed during execution (parameters) are kept, otherwise things like the opcode, funct3 are left out and replaced with an enum.
pub const Instructions = struct {
    /// The address (in DRAM) where instructions are stored
    loc: ArrayList(usize),

    /// The operation name (opcode)
    op: ArrayList(isa.RV32_Operation),

    /// The destination register.
    /// This is present in all instruction types except for S and B, where it uses imm[4:0] and imm[4:1|11], likewise
    rd: ArrayList(?u5),

    /// The first source register for the instruction. Like funct3, it is present in all instruction types except for U and J.
    rs1: ArrayList(?u5),

    /// The second source register to be used in the instruction. Present in R, S, and B instruction types.
    rs2: ArrayList(?u5),

    /// A last 7 bits specifying additional execution details in an R type instruction.
    funct7: ArrayList(?u7),

    /// I-type immediate value: imm[11:0], replacing the rd field.
    imm_i: ArrayList(?i32), // All immediate fields are signed

    /// S-type: imm[11:5|4:0]
    imm_s: ArrayList(?i32),

    /// B-type: imm[12|10:5|4:1|11]
    imm_b: ArrayList(?i32),

    /// U-type: imm[31:12]
    imm_u: ArrayList(?i32),

    /// J-type: imm[20|10:1|11|19:12]
    imm_j: ArrayList(?i32),

    /// Returns an empty instruction SoA with initialized (empty) ArrayList values
    pub fn init() Instructions {
        return Instructions{
            .loc = ArrayList(usize).empty,
            .op = ArrayList(isa.RV32Operation).empty,
            .rd = ArrayList(?u5).empty,
            .rs1 = ArrayList(?u5).empty,
            .rs2 = ArrayList(?u5).empty,
            .funct7 = ArrayList(?u5).empty,
            .imm_i = ArrayList(?i32).empty,
            .imm_s = ArrayList(?i32).empty,
            .imm_b = ArrayList(?i32).empty,
            .imm_u = ArrayList(?i32).empty,
            .imm_j = ArrayList(?i32).empty,
        };
    }

    /// Deallocate the ArrayLists in the struct
    pub fn deinit(self: *Instructions, allocator: Allocator) void {
        self.loc.deinit(allocator);
        self.op.deinit(allocator);
        self.rd.deinit(allocator);
        self.rs1.deinit(allocator);
        self.rs2.deinit(allocator);
        self.funct7.deinit(allocator);
        self.imm_i.deinit(allocator);
        self.imm_s.deinit(allocator);
        self.imm_b.deinit(allocator);
        self.imm_u.deinit(allocator);
        self.imm_j.deinit(allocator);
    }

    pub fn validateAndPack(self: *Instructions, allocator: Allocator, comptime len: usize, instructions: Decoder(len)) !void {
        for (0..len) |i| {
            switch (instructions.opcode[i]) {
                0b0110011 => { // R type instruction
                    switch (instructions.funct3[i]) {
                        0x0 => {
                            switch (instructions.funct7[i]) {
                                0x00 => try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.add),
                                0x20 => try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.sub),
                                else => std.log.debug("Skipping instruction {} (i = {}) due to having valid R-type opcode, funct3 of {}, but an invalid funct7 of {}.\n", .{ instructions.instruction[i], i, instructions.funct3[i], instructions.funct7[i] }),
                            }
                        },
                        0x1 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, instructions, isa.RV32Operation.sll) else {
                                std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode, funct3 of 0x{X}, but an invalid funct7 of 0x{X}.\n", .{ instructions.instruction[i], i, instructions.funct3[i], instructions.funct7[i] });
                            }
                        },
                        0x2 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.slt) else {
                                std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode, funct3 of 0x{X}, but an invalid funct7 of 0x{X}.\n", .{ instructions.instruction[i], i, instructions.funct3[i], instructions.funct7[i] });
                            }
                        },
                        0x3 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.sltu) else {
                                std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode, funct3 of 0x{X}, but an invalid funct7 of 0x{X}.\n", .{ instructions.instruction[i], i, instructions.funct3[i], instructions.funct7[i] });
                            }
                        },
                        0x4 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.xor) else {
                                std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode, funct3 of 0x{X}, but an invalid funct7 of 0x{X}.\n", .{ instructions.instruction[i], i, instructions.funct3[i], instructions.funct7[i] });
                            }
                        },
                        0x5 => {
                            switch (instructions.funct7[i]) {
                                0x00 => try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.srl),
                                0x20 => try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.sra),
                                else => continue,
                            }
                        },
                        0x6 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.OR);
                        },
                        0x7 => {
                            if (instructions.funct7[i] == 0x00) try self.appendInstructionR(allocator, len, i, instructions, isa.RV32Operation.AND);
                        },
                        else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] }),
                    }
                },
                0b0010011 => { // I type instruction
                    switch (instructions.funct3[i]) {
                        0x0 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.addi),
                        0x1 => {
                            const shamt_high: u7 = @truncate((instructions.imm_i[i] >> 5) & 0x7f);
                            if (shamt_high == 0x00) try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.slli) else {
                                std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode but invalid shamt_high of 0x{X}\n", .{ instructions.instruction[i], i, shamt_high });
                            }
                        },
                        0x2 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.slti),
                        0x3 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.sltiu),
                        0x4 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.xori),
                        0x5 => {
                            const shamt_high: u7 = @truncate((instructions.imm_i[i] >> 5) & 0x7f);
                            switch (shamt_high) {
                                0x00 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.srli),
                                0x20 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.srai),
                                else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid R-type opcode but invalid shamt_high of 0x{X}\n", .{ instructions.instruction[i], i, shamt_high }),
                            }
                        },
                        0x6 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.ori),
                        0x7 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.andi),
                        else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid I-type opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] }),
                    }
                },
                0b0000011 => { // I type instruction (load)
                    switch (instructions.funct3[i]) {
                        0x0 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.lb),
                        0x1 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.lh),
                        0x2 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.lw),
                        0x4 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.lbu),
                        0x5 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.lhu),
                        else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid load (I type) opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] }),
                    }
                },
                0b0100011 => { // S type instruction
                    switch (instructions.funct3[i]) {
                        0x0 => try self.appendInstructionS(allocator, len, i, instructions, isa.RV32Operation.sb),
                        0x1 => try self.appendInstructionS(allocator, len, i, instructions, isa.RV32Operation.sh),
                        0x2 => try self.appendInstructionS(allocator, len, i, instructions, isa.RV32Operation.sw),
                        else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid S type opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] }),
                    }
                },
                0b1100011 => { // B type instruction
                    switch (instructions.funct3[i]) {
                        0x0 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.beq),
                        0x1 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.bne),
                        0x4 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.blt),
                        0x5 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.bge),
                        0x6 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.bltu),
                        0x7 => try self.appendInstructionB(allocator, len, i, instructions, isa.RV32Operation.bgeu),
                        else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid B type opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] }),
                    }
                },
                0b1100111 => {
                    if (instructions.funct3[i] == 0x0) {
                        try self.appendInstructionJ(allocator, len, i, instructions, isa.RV32Operation.jal);
                    } else std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid jal opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] });
                },
                0b1101111 => {
                    if (instructions.funct3[i] == 0x0) {
                        try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.jal);
                    } else std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid jalr opcode but invalid funct3 of 0x{X}\n", .{ instructions.instruction[i], i, instructions.funct3[i] });
                },
                0b0110111 => try self.appendInstructionU(allocator, len, i, instructions, isa.RV32Operation.lui),
                0b0010111 => try self.appendInstructionU(allocator, len, i, instructions, isa.RV32Operation.auipc),
                0b1110011 => { // ecall and ebreak
                    if (instructions.funct3[i] == 0x0) {
                        switch (instructions.imm_i[i]) {
                            0x0 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.ecall),
                            0x1 => try self.appendInstructionI(allocator, len, i, instructions, isa.RV32Operation.ebreak),
                            else => std.log.debug("Skipping instruction 0x{X} (i = {d}) due to having valid ecall/ebreak opcode but invalid imm of 0x{X}\n", .{ instructions.instruction[i], i, instructions.imm_i[i] }),
                        }
                    }
                },
                else => continue,
            }
        }
    }

    /// Appends the relevant fields for a R type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionR(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        if (instructions.rd[i] == 0b00000) {
            std.log.warn("Skipping R-type instruction 0x{X} due to attempted write to x0. i = {d}\n", .{ instructions.instruction[i], i });
            return;
        }

        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, null);
        try self.imm_s.append(allocator, null);
        try self.imm_b.append(allocator, null);
        try self.imm_u.append(allocator, null);
        try self.imm_j.append(allocator, null);
    }

    /// Appends the relevant fields for an I type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionI(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        if (instructions.rd[i] == 0b00000) {
            std.log.warn("Skipping I-type instruction 0x{X} due to attempted write to x0. i = {d}\n", .{ instructions.instruction[i], i });
            return;
        }

        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, instructions.imm_i[i]);
        try self.imm_s.append(allocator, null);
        try self.imm_b.append(allocator, null);
        try self.imm_u.append(allocator, null);
        try self.imm_j.append(allocator, null);
    }

    /// Appends the relevant fields for a S type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionS(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, null);
        try self.imm_s.append(allocator, instructions.imm_s[i]);
        try self.imm_b.append(allocator, null);
        try self.imm_u.append(allocator, null);
        try self.imm_j.append(allocator, null);
    }

    /// Appends the relevant fields for a B type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionB(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, null);
        try self.imm_s.append(allocator, null);
        try self.imm_b.append(allocator, instructions.imm_b[i]);
        try self.imm_u.append(allocator, null);
        try self.imm_j.append(allocator, null);
    }

    /// Appends the relevant fields for an U type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionU(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        if (instructions.rd[i] == 0b00000) {
            std.log.warn("Skipping U-type instruction 0x{X} due to attempted write to x0. i = {d}\n", .{ instructions.instruction[i], i });
            return;
        }

        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, null);
        try self.imm_s.append(allocator, null);
        try self.imm_b.append(allocator, null);
        try self.imm_u.append(allocator, instructions.imm_u[i]);
        try self.imm_j.append(allocator, null);
    }

    /// Appends the relevant fields for a J type instruction to the validated instruction structure of arrays, appending null for the fields that aren't used
    inline fn appendInstructionJ(self: *Instructions, allocator: Allocator, comptime len: usize, i: usize, instructions: Decoder(len), opcode: isa.RV32Operation) !void {
        if (instructions.rd[i] == 0b00000) {
            std.log.warn("Skipping J-type instruction 0x{X} due to attempted write to x0. i = {d}\n", .{ instructions.instruction[i], i });
            return;
        }

        std.log.debug("Validated and appending instruction 0x{X} of opcode 0x{X} from address 0x{X}. i = {d}\n", .{ instructions.instruction[i], opcode, instructions.base + (i * 4), i });

        try self.loc.append(allocator, instructions.base + (i * 4));
        try self.op.append(allocator, opcode);
        try self.rd.append(allocator, instructions.rd[i]);

        try self.rd.append(allocator, instructions.rd[i]);
        try self.rs1.append(allocator, instructions.rs1[i]);
        try self.rs2.append(allocator, instructions.rs2[i]);

        try self.imm_i.append(allocator, null);
        try self.imm_s.append(allocator, null);
        try self.imm_b.append(allocator, null);
        try self.imm_u.append(allocator, null);
        try self.imm_j.append(allocator, instructions.imm_j[i]);
    }
};
