/// A singular decoded instruction. Use the Instructions (plural) for a vectorized structure of arrays, which is more efficent.
pub const Instruction32 = struct {
    opcode: u7, // TODO: refactor to use an enum later down the line
    rd: u5,
    funct3: u2,
    rs1: u5,
    rs2: u5,
    funct7: u7,

    pub inline fn decode(instruction: u32) Instruction32 {
        return Instruction32{
            .opcode = @truncate(instruction & 0x7f),
            .rd = @truncate((instruction >> 7) & 0x1f),
            .funct3 = @truncate((instruction >> 12) & 0x07),
            .rs1 = @truncate((instruction >> 15) & 0x1f),
            .rs2 = @truncate((instruction >> 20) & 0x1f),
            .funct7 = @truncate((instruction >> 25) & 0x07),
        };
    }
};

/// Plural version of the Instruction32 struct, using @Vector for optimization.
pub fn Instructions32(comptime len: comptime_int) type {
    var initialized = struct {
        len: usize,
        opcode: @Vector(len, u7),
        rd: @Vector(len, u5),
        funct3: @Vector(len, u2),
        rs1: @Vector(len, u5),
        rs2: @Vector(len, u5),
        funct7: @Vector(len, u7),

        pub inline fn decode(instructions: @Vector(len, u32)) @This() {
            const instruction_struct = Instructions32(instructions.len);

            const u7_mask = @as(@Vector(u32, instructions.len), @splat(0x7f));
            const u5_mask = @as(@Vector(u32, instructions.len), @splat(0x1f));
            const u3_mask = @as(@Vector(u32, instructions.len), @splat(0x07));
            const shift_7: @Vector(len, u5) = @splat(7);
            const shift_12: @Vector(len, u5) = @splat(12);
            const shift_15: @Vector(len, u5) = @splat(15);
            const shift_20: @Vector(len, u5) = @splat(20);
            const shift_25: @Vector(len, u5) = @splat(25);

            return instruction_struct{
                .opcode = @truncate(instructions & u7_mask),
                .rd = @truncate((instructions >> shift_7) & u5_mask),
                .funct3 = @truncate((instructions >> shift_12) & u3_mask),
                .rs1 = @truncate((instructions >> shift_15) & u5_mask),
                .rs2 = @truncate((instructions >> shift_20) & u5_mask),
                .funct7 = @truncate((instructions >> shift_25) & u7_mask),
            };
        }
    };

    initialized.len = @as(usize, @intCast(len));

    return initialized;
}
