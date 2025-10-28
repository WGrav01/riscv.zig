const std = @import("std");
const riscv = @import("riscv");

test "decoder detects misaligned memory address during initialization" {
    const len = 64;
    const bad_base = 13;

    try std.testing.expectError(riscv.decode.DecodeError.MisalignedMemoryBase, riscv.decode.Decoder(len, bad_base));
}