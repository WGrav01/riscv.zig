/// Struct that defines what modules are in use
const ISAconfig = struct {
    // Core ISA:

    /// Base Integer Instruction Set - 32-bit
    rv32i: bool,

    /// Base Integer Instruction Set (embedded) - 32-bit, 16 registers
    rv32e: bool,

    /// Base Integer Instruction Set - 64-bit
    rv64i: bool,

    /// Base Integer Instruction Set - 128-bit
    rv128i: bool,

    // Extentions:

    /// Standard Extension for Integer Multiplication and Division
    m: bool,

    /// Standard Extension for Atomic Instructions
    a: bool,

    /// Standard Extension for Single-Precision Floating-Point
    f: bool,

    /// Standard Extension for Double-Precision Floating-Point
    d: bool,

    /// Shorthand for the base and above extensions
    g: bool,

    /// Standard Extension for Quad-Precision Floating-Point
    q: bool,

    /// Standard Extension for Decimal Floating-Point
    l: bool,

    /// Standard Extension for Compressed Instructions
    c: bool,

    /// Standard Extension for Bit Manipulation
    b: bool,

    /// Standard Extension for Dynamically Translated Languages
    j: bool,

    /// Standard Extension for Transactional Memory
    t: bool,

    /// Standard Extension for Packed-SIMD Instructions
    p: bool,

    /// Standard Extension for Vector Operations
    v: bool,

    /// Standard Extension for User-Level Interrupts
    n: bool,

    /// Standard Extension for Hypervisor
    h: bool,

    /// Standard Extension for Supervisor-level Instructions
    s: bool,
};
