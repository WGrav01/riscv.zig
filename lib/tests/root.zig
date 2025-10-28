const std = @import("std");
pub const riscv = @import("riscv");
pub const decode = @import("decode.zig");
pub const dram = @import("dram.zig");

test {
    std.testing.refAllDecls(@This());
}