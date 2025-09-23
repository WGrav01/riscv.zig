//! Definitions for instruction sets and extensions

/// Enum for which base instruction set is in use
pub const Base = enum {
    /// 32 bit base integer instruction set
    rv32i,

    /// Embedded version of the 32 bit base integer instruction set, with 16 registers
    rv32e,

    /// 64 bit base integer instruction set
    rv64i,

    /// 128 bit base integer instruction set
    rv128i,
};

/// Struct that defines what extensions are in use
pub const Extentions = struct {
    /// Standard Extension for Integer Multiplication and Division
    m: bool = undefined,

    /// Standard Extension for Atomic Instructions
    a: bool = undefined,

    /// Standard Extension for Single-Precision Floating-Point
    f: bool = undefined,

    /// Standard Extension for Double-Precision Floating-Point
    d: bool = undefined,

    /// Shorthand for the base and above extensions
    g: bool = undefined,

    /// Standard Extension for Quad-Precision Floating-Point
    q: bool = undefined,

    /// Standard Extension for Decimal Floating-Point
    l: bool = undefined,

    /// Standard Extension for Compressed Instructions
    c: bool = undefined,

    /// Standard Extension for Bit Manipulation
    b: bool = undefined,

    /// Standard Extension for Dynamically Translated Languages
    j: bool = undefined,

    /// Standard Extension for Transactional Memory
    t: bool = undefined,

    /// Standard Extension for Packed-SIMD Instructions
    p: bool = undefined,

    /// Standard Extension for Vector Operations
    v: bool = undefined,

    /// Standard Extension for User-Level Interrupts
    n: bool = undefined,

    /// Standard Extension for Hypervisor
    h: bool = undefined,

    /// Standard Extension for Supervisor-level Instructions
    s: bool = undefined,
};
