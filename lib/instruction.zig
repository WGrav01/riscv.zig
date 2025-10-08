/// A singular decoded instruction. Use the Instructions (plural) for a vectorized structure of arrays, which is more efficent.
pub const Instruction32 = struct {
    opcode: u7, // TODO: refactor to use an enum later down the line
    rd: u5,
    funct3: u2,
    rs1: u5,
    rs2: u5,
    funct7: u7,

    pub fn decode(instruction: u32) Instruction32 {
        return Instruction32{
            .opcode = @truncate(instruction & 0x7f),
            .rd = @truncate((instruction >> 7) & 0x1f),
            .funct3 = @truncate((instruction >> 12) & 0x7),
            .rs1 = @truncate((instruction >> 15) & 0x1f),
            .rs2 = @truncate((instruction >> 20) & 0x1f),
            .funct7 = @truncate((instruction >> 25) & 0x7f),
        };
    }
};
