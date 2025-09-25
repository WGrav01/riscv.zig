const std = @import("std");

pub const DRAMError = error{
    /// The address specified was invalid in an R/W operation
    OutOfBounds,
};

/// Emulated dynamic random access memory
pub const DRAM = struct {
    /// The size of the dram
    size: usize,

    /// The base memory address of the DRAM
    base: usize = 0x80000000,

    /// The actual memory itself
    mem: []u8,

    /// Memory allocator, stored for init/deinit functions
    alloc: *std.mem.Allocator,

    /// Create an allocate a DRAM struct
    pub inline fn init(size: usize, allocator: *std.mem.Allocator) !DRAM {
        return DRAM{
            .size = size,
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
        return @as(*const u8, @ptrCast(&self.mem[idx])).*; // single byte, should be safe
    }

    /// Loads an 16 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load16(self: *const DRAM, addr: usize) DRAMError!u16 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 2 > self.size) return DRAMError.OutOfBounds;
        return std.mem.readInt(u16, &self.mem[idx .. idx + 2]);
    }

    /// Loads an 32 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load32(self: *const DRAM, addr: usize) DRAMError!u32 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 4 > self.size) return DRAMError.OutOfBounds;
        return std.mem.readInt(u32, &self.mem[idx .. idx + 4]);
    }

    /// Loads an 64 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load64(self: *const DRAM, addr: usize) DRAMError!u64 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 8 > self.size) return DRAMError.OutOfBounds;
        return std.mem.readInt(u64, &self.mem[idx .. idx + 8]);
    }

    /// Loads an 128 bit uint from the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn load128(self: *const DRAM, addr: usize) DRAMError!u128 {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 16 > self.size) return DRAMError.OutOfBounds;
        return std.mem.readInt(u128, &self.mem[idx .. idx + 16]);
    }

    /// Writes an 8 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store8(self: *DRAM, addr: usize, value: u64) DRAMError!void {
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
        std.mem.writeInt(u16, &self.mem[idx .. idx + 4], value, .little);
    }

    /// Writes an 32 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store32(self: *DRAM, addr: usize, value: u32) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 4 > self.size) return DRAMError.OutOfBounds;
        std.mem.writeInt(u32, &self.mem[idx .. idx + 8], value, .little);
    }

    /// Writes an 64 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store64(self: *DRAM, addr: usize, value: u64) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 8 > self.size) return DRAMError.OutOfBounds;
        std.mem.writeInt(u64, &self.mem[idx .. idx + 12], value, .little);
    }

    /// Writes an 128 bit unit into the emulated DRAM, returning DRAMError.OutOfBounds if the address is invalid
    pub inline fn store128(self: *DRAM, addr: usize, value: u128) DRAMError!void {
        if (addr < self.base) return DRAMError.OutOfBounds;
        const idx = addr - self.base;
        if (idx + 16 > self.size) return DRAMError.OutOfBounds;
        std.mem.writeInt(u128, &self.mem[idx .. idx + 16], value, .little);
    }
};
