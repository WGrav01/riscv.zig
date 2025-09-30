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
pub const Extensions = enum {
    /// Standard Extension for Integer Multiplication and Division
    m,

    /// Standard Extension for Atomic Instructions
    a,

    /// Standard Extension for Single-Precision Floating-Point
    f,

    /// Standard Extension for Double-Precision Floating-Point
    d,

    /// Shorthand for the base and above extensions
    g,

    /// Standard Extension for Quad-Precision Floating-Point
    q,

    /// Standard Extension for Decimal Floating-Point
    l,

    /// Standard Extension for Compressed Instructions
    c,

    /// Standard Extension for Bit Manipulation
    b,

    /// Standard Extension for Dynamically Translated Languages
    j,

    /// Standard Extension for Transactional Memory
    t,

    /// Standard Extension for Packed-SIMD Instructions
    p,

    /// Standard Extension for Vector Operations
    v,

    /// Standard Extension for User-Level Interrupts
    n,

    /// Standard Extension for Hypervisor
    h,

    /// Standard Extension for Supervisor-level Instructions
    s,
};
