const std = @import("std");
pub const riscv = @import("riscv");
pub const instruction = @import("instruction.zig");
pub const dram = @import("dram.zig");

test {
    std.testing.refAllDecls(@This());
}
