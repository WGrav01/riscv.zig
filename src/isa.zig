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
pub const Extensions = struct {
    /// Standard Extension for Integer Multiplication and Division
    m: bool = false,

    /// Standard Extension for Atomic Instructions
    a: bool = false,

    /// Standard Extension for Single-Precision Floating-Point
    f: bool = false,

    /// Standard Extension for Double-Precision Floating-Point
    d: bool = false,

    /// Shorthand for the base and above extensions
    g: bool = false,

    /// Standard Extension for Quad-Precision Floating-Point
    q: bool = false,

    /// Standard Extension for Decimal Floating-Point
    l: bool = false,

    /// Standard Extension for Compressed Instructions
    c: bool = false,

    /// Standard Extension for Bit Manipulation
    b: bool = false,

    /// Standard Extension for Dynamically Translated Languages
    j: bool = false,

    /// Standard Extension for Transactional Memory
    t: bool = false,

    /// Standard Extension for Packed-SIMD Instructions
    p: bool = false,

    /// Standard Extension for Vector Operations
    v: bool = false,

    /// Standard Extension for User-Level Interrupts
    n: bool = false,

    /// Standard Extension for Hypervisor
    h: bool = false,

    /// Standard Extension for Supervisor-level Instructions
    s: bool = false,
};
