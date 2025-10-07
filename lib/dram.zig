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
