/// Struct that holds a batch of instructions in vector form for the first stage of decoding.
/// The decode function is ran at comptime as the vectors' length needs to be known then, and unless the instructions are comptime known, the instructions will be decoded at runtime by calling the decode function.
pub fn Decoder(comptime len: usize) type {
    return struct {
        /// Common fields, present in most instruction formats:
        common: struct {
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
            funct7: @Vector(len, u7),
        },

        /// Immediate values, sign extended:
        immediate: struct {
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
        },

        /// Decode a batch of instructions, extracting every field for every instruction, using SIMD for parallelization. While the every field decoding is redundant, it reduces control flow which is more ideal for stage 2.
        pub inline fn decode(self: *@This(), instructions: @Vector(len, u32)) void {
            // Masks needed for common field bit extraction, splatted into a vector. 2^[# of bits] - 1
            const mask_7bit: @Vector(len, u32) = @splat(0x7f);
            const mask_5bit: @Vector(len, u32) = @splat(0x1f);
            const mask_3bit: @Vector(len, u32) = @splat(0x07);

            // Extract common fields using shift + mask pattern: (instruction >> bit_offset) & mask
            self.common.opcode = @truncate(instructions & mask_7bit);
            self.common.rd = @truncate((instructions >> @splat(7)) & mask_5bit);
            self.common.funct3 = @truncate((instructions >> @splat(12)) & mask_3bit);
            self.common.rs1 = @truncate((instructions >> @splat(15)) & mask_5bit);
            self.common.rs2 = @truncate((instructions >> @splat(20)) & mask_5bit);
            self.common.funct7 = @truncate(instructions >> @splat(25) & mask_7bit);

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

            self.immediate.imm_i = signed_instructions >> @splat(20); // I-type: imm[11:0] at bits [31:20]

            // S-type: imm[11:5] at [31:25] | imm[4:0] at [11:7]
            // Reassemble split immediate with sign extension from bit 31
            const s_upper: @Vector(len, i32) = signed_instructions >> @splat(20); // Sign-extends from bit 31
            const s_lower: @Vector(len, i32) = signed_instructions >> @splat(7) & mask_bits_4_0;
            self.immediate.imm_s = (s_upper & inv_mask_bits_4_0) | s_lower;

            // B-type: imm[12] at [31] | imm[10:5] at [30:25] | imm[4:1] at [11:8] | imm[11] at [7]
            // Note: bit 0 is implicitly 0 (instructions are 2-byte aligned)
            const b_12: @Vector(len, i32) = signed_instructions >> @splat(19); // Sign-extend from bit 12
            const b_11: @Vector(len, i32) = (signed_instructions >> @splat(7)) & mask_bit_0;
            const b_10_5: @Vector(len, i32) = (signed_instructions >> @splat(25)) & mask_bits_5_0;
            const b_4_1: @Vector(len, i32) = (signed_instructions >> @splat(8)) & mask_bits_3_0;
            self.immediate.imm_b = (b_12 & inv_mask_bits_11_0) | (b_11 << @splat(11)) | (b_10_5 << @splat(5)) | (b_4_1 << @splat(1));

            // U-type: imm[31:12] at [31:12], lower 12 bits are zero
            // Used by LUI (load upper immediate) and AUIPC (add upper immediate to PC)
            self.immediate.imm_u = @bitCast(instructions & mask_u_imm_31_12);

            // J-type: imm[20] at [31] | imm[10:1] at [30:21] | imm[11] at [20] | imm[19:12] at [19:12]
            // Note: bit 0 is implicitly 0 (instructions are 2-byte aligned)
            const j_20: @Vector(len, i32) = signed_instructions >> @splat(11);
            const j_19_12: @Vector(len, i32) = signed_instructions & mask_j_imm_19_12;
            const j_11: @Vector(len, i32) = (signed_instructions >> @splat(9)) & mask_bit_11;
            const j_10_1: @Vector(len, i32) = (signed_instructions >> @splat(20)) & mask_j_imm_10_1;
            self.immediate.imm_j = (j_20 & inv_mask_bits_20_0) | j_19_12 | j_11 | j_10_1;
        }
    };
}
