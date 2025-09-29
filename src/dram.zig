const std = @import("std");

pub const DRAMError = error{
    /// The address specified was invalid in an R/W operation
    OutOfBounds,
};

pub const default_base: usize = 0x80000000;

/// Emulated dynamic random access memory
pub const DRAM = struct {
    /// The size of the dram
    size: usize,

    /// The base memory address of the DRAM
    base: usize = default_base,

    /// The actual memory itself
    mem: []u8,

    /// Memory allocator, stored for init/deinit functions
    alloc: *std.mem.Allocator,

    /// Create an allocate a DRAM struct
    pub inline fn init(size: usize, allocator: *std.mem.Allocator, base: ?usize) !DRAM {
        return DRAM{
            .size = size,
            .base = base orelse default_base,
            .mem = try allocator.alloc(u8, size),
            .alloc = allocator,
        };
    }

    /// Deallocate the DRAM struct
    pub inline fn deinit(self: *DRAM) void {
        self.alloc.free(self.mem);
    }

    /// Loads an 8 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load8(self: *const DRAM, addr: usize) DRAMError!u8 {
        if (addr < self.base) return DRAMError.OutOfBounds; // Underflow check
        const idx = addr - self.base;
        if (idx + 1 > self.size) return DRAMError.OutOfBounds; // Overflow check
        return self.mem[idx]; // single byte, should be safe
    }

    /// Loads an 16 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load16(self: *const DRAM, addr: usize) DRAMError!u16 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 2 > self.size) return DRAMError.OutOfBounds;
        const src = @as(*[2]u8, @ptrCast(&self.mem[idx]));
        return std.mem.readInt(u16, src, .little);
    }

    /// Loads an 32 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load32(self: *const DRAM, addr: usize) DRAMError!u32 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 4 > self.size) return DRAMError.OutOfBounds;
        const src = @as(*[4]u8, @ptrCast(&self.mem[idx]));
        return std.mem.readInt(u32, src, .little);
    }

    /// Loads an 64 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load64(self: *const DRAM, addr: usize) DRAMError!u64 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 8 > self.size) return DRAMError.OutOfBounds;
        const src = @as(*[8]u8, @ptrCast(&self.mem[idx]));
        return std.mem.readInt(u64, src, .little);
    }

    /// Loads an 128 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load128(self: *const DRAM, addr: usize) DRAMError!u128 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 16 > self.size) return DRAMError.OutOfBounds;
        const src = @as(*[16]u8, @ptrCast(&self.mem[idx]));
        return std.mem.readInt(u128, src, .little);
    }

    /// Writes an 8 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store8(self: *DRAM, addr: usize, value: u8) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 1 > self.size) return DRAMError.OutOfBounds;
        self.mem[idx] = value; // Like load8, it's a single byte, so it SHOULD be safe
    }

    /// Writes an 16 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store16(self: *DRAM, addr: usize, value: u16) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 2 > self.size) return DRAMError.OutOfBounds;
        const dst = @as(*[2]u8, @ptrCast(&self.mem[idx]));
        std.mem.writeInt(u16, dst, value, .little);
    }

    /// Writes an 32 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store32(self: *DRAM, addr: usize, value: u32) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 4 > self.size) return DRAMError.OutOfBounds;
        const dst = @as(*[4]u8, @ptrCast(&self.mem[idx]));
        std.mem.writeInt(u32, dst, value, .little);
    }

    /// Writes an 64 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store64(self: *DRAM, addr: usize, value: u64) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 8 > self.size) return DRAMError.OutOfBounds;
        const dst = @as(*[8]u8, @ptrCast(&self.mem[idx]));
        std.mem.writeInt(u64, dst, value, .little);
    }

    /// Writes an 128 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store128(self: *DRAM, addr: usize, value: u128) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 16 > self.size) return DRAMError.OutOfBounds;
        const dst = @as(*[16]u8, @ptrCast(&self.mem[idx]));
        std.mem.writeInt(u128, dst, value, .little);
    }
};

// Tests begin here:

test "Check that DRAM inits and allocates correctly " {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try std.testing.expect(testing_dram.mem.len == 256);
}

test "DRAM basic store/load, 8 bits" {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try testing_dram.store8(testing_dram.base + 0, 0xAB);
    try std.testing.expect(try testing_dram.load8(testing_dram.base + 0) == 0xAB);
}

test "DRAM basic store/load, 16 bits" {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try testing_dram.store16(testing_dram.base + 2, 0x1234);
    try std.testing.expect(try testing_dram.load16(testing_dram.base + 2) == 0x1234);
}

test "DRAM basic store/load, 32 bits" {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try testing_dram.store32(testing_dram.base + 4, 0xDEADBEEF); // magical
    try std.testing.expect(try testing_dram.load32(testing_dram.base + 4) == 0xDEADBEEF);
}

test "DRAM basic store/load, 64 bits" {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try testing_dram.store64(testing_dram.base + 8, 0x0123456789ABCDEF);
    try std.testing.expect(try testing_dram.load64(testing_dram.base + 8) == 0x0123456789ABCDEF);
}

test "DRAM basic store/load, 128 bits" {
    var test_allocator = std.testing.allocator;
    var testing_dram = try DRAM.init(256, &test_allocator, null);
    defer testing_dram.deinit();

    try testing_dram.store128(testing_dram.base + 16, 0x0123456789ABCDEF0123456789ABCDEF);
    try std.testing.expect(try testing_dram.load128(testing_dram.base + 16) == 0x0123456789ABCDEF0123456789ABCDEF);
}

test "Endian and byte layout" {
    var test_allocator = std.testing.allocator;
    var d = try DRAM.init(256, &test_allocator, null);
    defer d.deinit();

    const addr = d.base + 0;
    const value: u32 = 0x0A0B0C0D;
    try d.store32(addr, value);

    try std.testing.expect(d.mem[0] == 0x0D);
    try std.testing.expect(d.mem[1] == 0x0C);
    try std.testing.expect(d.mem[2] == 0x0B);
    try std.testing.expect(d.mem[3] == 0x0A);

    try std.testing.expect(try d.load8(addr + 0) == 0x0D);
    try std.testing.expect(try d.load8(addr + 1) == 0x0C);
    try std.testing.expect(try d.load8(addr + 2) == 0x0B);
    try std.testing.expect(try d.load8(addr + 3) == 0x0A);

    try std.testing.expect(try d.load32(addr) == value);
}

test "Bounds checking" {
    var test_allocator = std.testing.allocator;
    var d = try DRAM.init(256, &test_allocator, null);
    defer d.deinit();

    try std.testing.expectError(DRAMError.OutOfBounds, d.store8(d.base + 256, 0xAB));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load8(d.base + 256));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store16(d.base + 255, 0x1234));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load16(d.base + 255));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store32(d.base + 254, 0xDEADBEEF));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load32(d.base + 254));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store64(d.base + 253, 0x123456789ABCDEF));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load64(d.base + 254));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store64(d.base + 253, 0x123456789ABCDEF));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load64(d.base + 253));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store128(d.base + 252, 0x0123456789ABCDEF0123456789ABCDEF));
    try std.testing.expectError(DRAMError.OutOfBounds, d.load128(d.base + 252));
}

test "Extreme OOB value" {
    var test_allocator = std.testing.allocator;
    var d = try DRAM.init(256, &test_allocator, null);
    defer d.deinit();

    const max_usize = std.math.maxInt(usize);

    try std.testing.expectError(DRAMError.OutOfBounds, d.load64(max_usize));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store64(max_usize, 0));
}

test "OOB with custom base address" {
    var test_allocator = std.testing.allocator;
    const custom_base = 0x12340000;
    var d = try DRAM.init(256, &test_allocator, custom_base);
    defer d.deinit();

    try std.testing.expectError(DRAMError.OutOfBounds, d.load32(custom_base - 4));

    try std.testing.expectError(DRAMError.OutOfBounds, d.store64(custom_base + 256, 0xFFFFFFFFFFFFFFFF));

    try d.store32(custom_base + 100, 0xDEADBEEF);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), // Magical
        try d.load32(custom_base + 100));
}
