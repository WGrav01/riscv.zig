const std = @import("std");
const dram = @import("dram.zig").DRAM;

/// Base CPU struct for the RV32 ISA
const Rv32 = struct {
    /// Registers x0-x31, all 32 bit
    registers: [32]u32,

    /// The program counter
    pc: u32,

    /// The connected DRAM
    dram: dram,

    pub fn init(d: dram) Rv32 {
        const cpu = Rv32{
            .registers = std.mem.zeroes([32]u32),
            .pc = d.base, // Set program counter to DRAM base
            .dram = d,
        };

        cpu.registers[0] = 0x00; // Register x0 is hardwired to zero
        cpu.registers[2] = d.base + d.size; // Set the stack pointer

        return cpu;
    }
};