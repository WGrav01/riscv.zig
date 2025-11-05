const std = @import("std");
const riscv = @import("riscv");
const testing = std.testing;

// Helper function to create a raw RISC-V instruction
fn makeRType(opcode: u7, rd: u5, funct3: u3, rs1: u5, rs2: u5, funct7: u7) u32 {
    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, rs2) << 20) |
        (@as(u32, funct7) << 25);
}

fn makeIType(opcode: u7, rd: u5, funct3: u3, rs1: u5, imm: i12) u32 {
    const imm_u: u12 = @bitCast(imm);
    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, imm_u) << 20);
}

fn makeSType(opcode: u7, funct3: u3, rs1: u5, rs2: u5, imm: i12) u32 {
    const imm_u: u12 = @bitCast(imm);
    const imm_low: u5 = @truncate(imm_u & 0x1F);
    const imm_high: u7 = @truncate(imm_u >> 5);
    return @as(u32, opcode) |
        (@as(u32, imm_low) << 7) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, rs2) << 20) |
        (@as(u32, imm_high) << 25);
}

fn makeBType(opcode: u7, funct3: u3, rs1: u5, rs2: u5, imm: i13) u32 {
    const imm_u: u13 = @bitCast(imm);
    const imm_11: u1 = @truncate((imm_u >> 11) & 1);
    const imm_4_1: u4 = @truncate((imm_u >> 1) & 0xF);
    const imm_10_5: u6 = @truncate((imm_u >> 5) & 0x3F);
    const imm_12: u1 = @truncate((imm_u >> 12) & 1);

    return @as(u32, opcode) |
        (@as(u32, imm_11) << 7) |
        (@as(u32, imm_4_1) << 8) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rs1) << 15) |
        (@as(u32, rs2) << 20) |
        (@as(u32, imm_10_5) << 25) |
        (@as(u32, imm_12) << 31);
}

fn makeUType(opcode: u7, rd: u5, imm: i32) u32 {
    const imm_u: u32 = @bitCast(imm);
    const imm_31_12: u20 = @truncate(imm_u >> 12);
    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, imm_31_12) << 12);
}

fn makeJType(opcode: u7, rd: u5, imm: i21) u32 {
    const imm_u: u21 = @bitCast(imm);
    const imm_20: u1 = @truncate((imm_u >> 20) & 1);
    const imm_10_1: u10 = @truncate((imm_u >> 1) & 0x3FF);
    const imm_11: u1 = @truncate((imm_u >> 11) & 1);
    const imm_19_12: u8 = @truncate((imm_u >> 12) & 0xFF);

    return @as(u32, opcode) |
        (@as(u32, rd) << 7) |
        (@as(u32, imm_19_12) << 12) |
        (@as(u32, imm_11) << 20) |
        (@as(u32, imm_10_1) << 21) |
        (@as(u32, imm_20) << 31);
}

// ============================================================================
// Stage 1: SIMD extraction
// ============================================================================

test "decoder: aligned base address accepted" {
    const base = 0x80000000;
    var decoder = try riscv.decoder.StageOne(4, base){};

    const instructions: @Vector(4, u32) = .{ 0x00000013, 0x00000013, 0x00000013, 0x00000013 };
    try decoder.decode(instructions);

    try testing.expectEqual(base, decoder.base);
}

test "decoder: misaligned base address rejected" {
    const bad_base = 0x80000002; // Not 4-byte aligned
    var decoder = try riscv.decoder.StageOne(4, bad_base){};

    const instructions: @Vector(4, u32) = .{ 0x00000013, 0x00000013, 0x00000013, 0x00000013 };
    try testing.expectError(riscv.decoder.DecodeError.MisalignedMemoryAccess, decoder.decode(instructions));
}

test "decoder: R-type field extraction" {
    // add x1, x2, x3  =>  0x003100B3
    const inst = makeRType(0b0110011, 1, 0, 2, 3, 0);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000);
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(u7, 0b0110011), decoder.opcode[0]);
    try testing.expectEqual(@as(u5, 1), decoder.rd[0]);
    try testing.expectEqual(@as(u3, 0), decoder.funct3[0]);
    try testing.expectEqual(@as(u5, 2), decoder.rs1[0]);
    try testing.expectEqual(@as(u5, 3), decoder.rs2[0]);
    try testing.expectEqual(@as(u7, 0), decoder.funct7[0]);
}

test "decoder: I-type immediate sign extension positive" {
    // addi x1, x2, 42  =>  imm = 0x02A
    const inst = makeIType(0b0010011, 1, 0, 2, 42);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, 42), decoder.imm_i[0]);
}

test "decoder: I-type immediate sign extension negative" {
    // addi x1, x2, -1  =>  imm = 0xFFF
    const inst = makeIType(0b0010011, 1, 0, 2, -1);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, -1), decoder.imm_i[0]);
}

test "decoder: S-type immediate extraction" {
    // sw x3, 8(x2)  =>  imm = 8
    const inst = makeSType(0b0100011, 2, 2, 3, 8);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, 8), decoder.imm_s[0]);
}

test "decoder: B-type immediate with alignment" {
    // beq x1, x2, 16  =>  imm must be multiple of 4
    const inst = makeBType(0b1100011, 0, 1, 2, 16);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, 16), decoder.imm_b[0]);
}

test "decoder: U-type immediate extraction" {
    // lui x1, 0x12345 => imm[31:12] = 0x12345
    const inst = makeUType(0b0110111, 1, 0x12345000);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, 0x12345000), decoder.imm_u[0]);
}

test "decoder: J-type immediate extraction" {
    // jal x1, 2048 => imm = 2048
    const inst = makeJType(0b1101111, 1, 2048);

    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    try testing.expectEqual(@as(i32, 2048), decoder.imm_j[0]);
}

test "decoder: batch processing multiple instructions" {
    const inst1 = makeRType(0b0110011, 1, 0, 2, 3, 0); // add
    const inst2 = makeIType(0b0010011, 4, 0, 5, 100); // addi
    const inst3 = makeBType(0b1100011, 0, 6, 7, 8); // beq
    const inst4 = makeUType(0b0110111, 8, 0x1000); // lui

    var decoder = try riscv.decoder.StageOne(4, 0x80000000){};
    const vec: @Vector(4, u32) = .{ inst1, inst2, inst3, inst4 };
    try decoder.decode(vec);

    try testing.expectEqual(@as(u7, 0b0110011), decoder.opcode[0]);
    try testing.expectEqual(@as(u7, 0b0010011), decoder.opcode[1]);
    try testing.expectEqual(@as(u7, 0b1100011), decoder.opcode[2]);
    try testing.expectEqual(@as(u7, 0b0110111), decoder.opcode[3]);
}

// ============================================================================
// Stage 2: Validation Tests
// ============================================================================

test "validation: simple R-type ADD" {
    const allocator = testing.allocator;

    const inst = makeRType(0b0110011, 1, 0, 2, 3, 0); // add x1, x2, x3
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(@as(usize, 1), instructions.op.items.len);
    try testing.expectEqual(riscv.isa.RV32Operation.add, instructions.op.items[0]);
    try testing.expectEqual(@as(u5, 1), riscv.decoder.StageTwo.getRd(instructions.regs.items[0]));
    try testing.expectEqual(@as(u5, 2), riscv.decoder.StageTwo.getRs1(instructions.regs.items[0]));
    try testing.expectEqual(@as(u5, 3), riscv.decoder.StageTwo.getRs2(instructions.regs.items[0]));
}

test "validation: R-type SUB" {
    const allocator = testing.allocator;

    const inst = makeRType(0b0110011, 5, 0, 6, 7, 0x20); // sub x5, x6, x7
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.sub, instructions.op.items[0]);
}

test "validation: R-type rejects write to x0" {
    const allocator = testing.allocator;

    const inst = makeRType(0b0110011, 0, 0, 2, 3, 0); // add x0, x2, x3 (invalid)
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    // Should be skipped
    try testing.expectEqual(@as(usize, 0), instructions.op.items.len);
}

test "validation: all R-type ALU operations" {
    const allocator = testing.allocator;

    const operations = [_]struct { funct3: u3, funct7: u7, op: riscv.isa.RV32Operation }{
        .{ .funct3 = 0, .funct7 = 0x00, .op = .add },
        .{ .funct3 = 0, .funct7 = 0x20, .op = .sub },
        .{ .funct3 = 1, .funct7 = 0x00, .op = .sll },
        .{ .funct3 = 2, .funct7 = 0x00, .op = .slt },
        .{ .funct3 = 3, .funct7 = 0x00, .op = .sltu },
        .{ .funct3 = 4, .funct7 = 0x00, .op = .xor },
        .{ .funct3 = 5, .funct7 = 0x00, .op = .srl },
        .{ .funct3 = 5, .funct7 = 0x20, .op = .sra },
        .{ .funct3 = 6, .funct7 = 0x00, .op = .OR },
        .{ .funct3 = 7, .funct7 = 0x00, .op = .AND },
    };

    for (operations) |op_spec| {
        const inst = makeRType(0b0110011, 1, op_spec.funct3, 2, 3, op_spec.funct7);
        var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
        const vec: @Vector(1, u32) = .{inst};
        try decoder.decode(vec);

        var instructions = riscv.decoder.StageTwo.init(allocator);
        defer instructions.deinit();

        try instructions.validateAndPack(allocator, 1, decoder);

        try testing.expectEqual(@as(usize, 1), instructions.op.items.len);
        try testing.expectEqual(op_spec.op, instructions.op.items[0]);
    }
}

test "validation: I-type ADDI" {
    const allocator = testing.allocator;

    const inst = makeIType(0b0010011, 1, 0, 2, 42); // addi x1, x2, 42
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[0]);
    try testing.expectEqual(@as(i32, 42), instructions.imm.items[0]);
}

test "validation: I-type shift with valid shamt" {
    const allocator = testing.allocator;

    const inst = makeIType(0b0010011, 1, 1, 2, 5); // slli x1, x2, 5
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.slli, instructions.op.items[0]);
}

test "validation: I-type shift rejects invalid shamt" {
    const allocator = testing.allocator;

    // slli with shamt_high != 0 (invalid)
    const inst = makeIType(0b0010011, 1, 1, 2, 0x425); // Invalid: upper bits set
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    // Should be skipped
    try testing.expectEqual(@as(usize, 0), instructions.op.items.len);
}

test "validation: load instructions" {
    const allocator = testing.allocator;

    const loads = [_]struct { funct3: u3, op: riscv.isa.RV32Operation }{
        .{ .funct3 = 0, .op = .lb },
        .{ .funct3 = 1, .op = .lh },
        .{ .funct3 = 2, .op = .lw },
        .{ .funct3 = 4, .op = .lbu },
        .{ .funct3 = 5, .op = .lhu },
    };

    for (loads) |load_spec| {
        const inst = makeIType(0b0000011, 1, load_spec.funct3, 2, 8);
        var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
        const vec: @Vector(1, u32) = .{inst};
        try decoder.decode(vec);

        var instructions = riscv.decoder.StageTwo.init(allocator);
        defer instructions.deinit();

        try instructions.validateAndPack(allocator, 1, decoder);

        try testing.expectEqual(load_spec.op, instructions.op.items[0]);
    }
}

test "validation: store instructions" {
    const allocator = testing.allocator;

    const stores = [_]struct { funct3: u3, op: riscv.isa.RV32Operation }{
        .{ .funct3 = 0, .op = .sb },
        .{ .funct3 = 1, .op = .sh },
        .{ .funct3 = 2, .op = .sw },
    };

    for (stores) |store_spec| {
        const inst = makeSType(0b0100011, store_spec.funct3, 2, 3, 8);
        var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
        const vec: @Vector(1, u32) = .{inst};
        try decoder.decode(vec);

        var instructions = riscv.decoder.StageTwo.init(allocator);
        defer instructions.deinit();

        try instructions.validateAndPack(allocator, 1, decoder);

        try testing.expectEqual(store_spec.op, instructions.op.items[0]);
    }
}

test "validation: branch instructions" {
    const allocator = testing.allocator;

    const branches = [_]struct { funct3: u3, op: riscv.isa.RV32Operation }{
        .{ .funct3 = 0, .op = .beq },
        .{ .funct3 = 1, .op = .bne },
        .{ .funct3 = 4, .op = .blt },
        .{ .funct3 = 5, .op = .bge },
        .{ .funct3 = 6, .op = .bltu },
        .{ .funct3 = 7, .op = .bgeu },
    };

    for (branches) |branch_spec| {
        const inst = makeBType(0b1100011, branch_spec.funct3, 1, 2, 16); // offset = 16 (aligned)
        var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
        const vec: @Vector(1, u32) = .{inst};
        try decoder.decode(vec);

        var instructions = riscv.decoder.StageTwo.init(allocator);
        defer instructions.deinit();

        try instructions.validateAndPack(allocator, 1, decoder);

        try testing.expectEqual(branch_spec.op, instructions.op.items[0]);
    }
}

test "validation: JAL instruction" {
    const allocator = testing.allocator;

    const inst = makeJType(0b1101111, 1, 2048); // jal x1, 2048
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.jal, instructions.op.items[0]);
    try testing.expectEqual(@as(i32, 2048), instructions.imm.items[0]);
}

test "validation: JALR instruction" {
    const allocator = testing.allocator;

    const inst = makeIType(0b1100111, 1, 0, 2, 8); // jalr x1, 8(x2)
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.jalr, instructions.op.items[0]);
}

test "validation: LUI instruction" {
    const allocator = testing.allocator;

    const inst = makeUType(0b0110111, 1, 0x12345000); // lui x1, 0x12345
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.lui, instructions.op.items[0]);
}

test "validation: AUIPC instruction" {
    const allocator = testing.allocator;

    const inst = makeUType(0b0010111, 1, 0x1000); // auipc x1, 0x1
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.auipc, instructions.op.items[0]);
}

test "validation: ECALL instruction" {
    const allocator = testing.allocator;

    const inst = makeIType(0b1110011, 0, 0, 0, 0); // ecall
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.ecall, instructions.op.items[0]);
}

test "validation: EBREAK instruction" {
    const allocator = testing.allocator;

    const inst = makeIType(0b1110011, 0, 0, 0, 1); // ebreak
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.ebreak, instructions.op.items[0]);
}

test "validation: invalid opcode skipped" {
    const allocator = testing.allocator;

    const inst = makeRType(0b1111111, 1, 0, 2, 3, 0); // Invalid opcode
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    // Should be skipped
    try testing.expectEqual(@as(usize, 0), instructions.op.items.len);
}

test "validation: invalid funct3/funct7 combination skipped" {
    const allocator = testing.allocator;

    const inst = makeRType(0b0110011, 1, 0, 2, 3, 0x10); // Invalid funct7 for ADD
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    // Should be skipped
    try testing.expectEqual(@as(usize, 0), instructions.op.items.len);
}

test "validation: mixed valid and invalid instructions" {
    const allocator = testing.allocator;

    const inst1 = makeRType(0b0110011, 1, 0, 2, 3, 0); // Valid ADD
    const inst2 = makeRType(0b1111111, 1, 0, 2, 3, 0); // Invalid opcode
    const inst3 = makeIType(0b0010011, 4, 0, 5, 100); // Valid ADDI
    const inst4 = makeRType(0b0110011, 0, 0, 2, 3, 0); // Invalid (rd=x0)

    var decoder = try riscv.decoder.StageOne(4, 0x80000000){};
    const vec: @Vector(4, u32) = .{ inst1, inst2, inst3, inst4 };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 4, decoder);

    // Only 2 valid instructions
    try testing.expectEqual(@as(usize, 2), instructions.op.items.len);
    try testing.expectEqual(riscv.isa.RV32Operation.add, instructions.op.items[0]);
    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[1]);
}

// ============================================================================
// Register Packing/Unpacking Tests
// ============================================================================

test "register packing: all combinations" {
    const test_cases = .{ .rd = [5]u5{ 0, 1, 31, 15, 5 }, .rs1 = [5]u5{ 0, 2, 30, 16, 0 }, .rs2 = [5]u5{ 0, 3, 29, 17, 31 } };

    for (0..5) |i| {
        const regs: u16 = riscv.decoder.StageTwo.packRegs(test_cases.rd[i], test_cases.rs1[i], test_cases.rs2[i]);

        try testing.expectEqual(test_cases.rd[i], riscv.decoder.StageTwo.getRd(regs));
        try testing.expectEqual(test_cases.rs1[i], riscv.decoder.StageTwo.getRs1(regs));
        try testing.expectEqual(test_cases.rs2[i], riscv.decoder.StageTwo.getRs2(regs));
    }
}

test "register packing: edge cases" {
    // Test maximum values
    const packed_max = riscv.decoder.StageTwo.packRegs(31, 31, 31);
    try testing.expectEqual(@as(u5, 31), riscv.decoder.StageTwo.getRd(packed_max));
    try testing.expectEqual(@as(u5, 31), riscv.decoder.StageTwo.getRs1(packed_max));
    try testing.expectEqual(@as(u5, 31), riscv.decoder.StageTwo.getRs2(packed_max));

    // Test minimum values
    const packed_min = riscv.decoder.StageTwo.packRegs(0, 0, 0);
    try testing.expectEqual(@as(u5, 0), riscv.decoder.StageTwo.getRd(packed_min));
    try testing.expectEqual(@as(u5, 0), riscv.decoder.StageTwo.getRs1(packed_min));
    try testing.expectEqual(@as(u5, 0), riscv.decoder.StageTwo.getRs2(packed_min));
}

// ============================================================================
// End-to-End Integration Tests
// ============================================================================

test "integration: simple program sequence" {
    const allocator = testing.allocator;

    // Simple program:
    // addi x1, x0, 5    # x1 = 5
    // addi x2, x0, 10   # x2 = 10
    // add x3, x1, x2    # x3 = x1 + x2 = 15
    // sw x3, 0(x0)      # store x3 to memory[0]

    const inst1 = makeIType(0b0010011, 1, 0, 0, 5);
    const inst2 = makeIType(0b0010011, 2, 0, 0, 10);
    const inst3 = makeRType(0b0110011, 3, 0, 1, 2, 0);
    const inst4 = makeSType(0b0100011, 2, 0, 3, 0);

    var decoder = try riscv.decoder.StageOne(4, 0x80000000){};
    const vec: @Vector(4, u32) = .{ inst1, inst2, inst3, inst4 };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 4, decoder);

    // Verify all 4 instructions were decoded
    try testing.expectEqual(@as(usize, 4), instructions.op.items.len);

    // Verify operations
    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[0]);
    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[1]);
    try testing.expectEqual(riscv.isa.RV32Operation.add, instructions.op.items[2]);
    try testing.expectEqual(riscv.isa.RV32Operation.sw, instructions.op.items[3]);

    // Verify immediates
    try testing.expectEqual(@as(i32, 5), instructions.imm.items[0]);
    try testing.expectEqual(@as(i32, 10), instructions.imm.items[1]);
    try testing.expectEqual(@as(i32, 0), instructions.imm.items[2]);
    try testing.expectEqual(@as(i32, 0), instructions.imm.items[3]);

    // Verify PC locations
    try testing.expectEqual(@as(usize, 0x80000000), instructions.loc.items[0]);
    try testing.expectEqual(@as(usize, 0x80000004), instructions.loc.items[1]);
    try testing.expectEqual(@as(usize, 0x80000008), instructions.loc.items[2]);
    try testing.expectEqual(@as(usize, 0x8000000C), instructions.loc.items[3]);
}

test "integration: branch and jump sequence" {
    const allocator = testing.allocator;

    // Program with control flow:
    // beq x1, x2, 8     # if x1 == x2, skip next instruction
    // addi x3, x3, 1    # x3++
    // jal x1, 16        # jump forward 16 bytes

    const inst1 = makeBType(0b1100011, 0, 1, 2, 8);
    const inst2 = makeIType(0b0010011, 3, 0, 3, 1);
    const inst3 = makeJType(0b1101111, 1, 16);

    var decoder = try riscv.decoder.StageOne(3, 0x80000000){};
    const vec: @Vector(3, u32) = .{ inst1, inst2, inst3 };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 3, decoder);

    try testing.expectEqual(@as(usize, 3), instructions.op.items.len);
    try testing.expectEqual(riscv.isa.RV32Operation.beq, instructions.op.items[0]);
    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[1]);
    try testing.expectEqual(riscv.isa.RV32Operation.jal, instructions.op.items[2]);
}

test "integration: load/store sequence" {
    const allocator = testing.allocator;

    // Load-store sequence:
    // lw x1, 0(x2)      # Load word from memory
    // addi x1, x1, 1    # Increment
    // sw x1, 0(x2)      # Store back

    const inst1 = makeIType(0b0000011, 1, 2, 2, 0);
    const inst2 = makeIType(0b0010011, 1, 0, 1, 1);
    const inst3 = makeSType(0b0100011, 2, 2, 1, 0);

    var decoder = try riscv.decoder.StageOne(3, 0x80000000){};
    const vec: @Vector(3, u32) = .{ inst1, inst2, inst3 };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 3, decoder);

    try testing.expectEqual(@as(usize, 3), instructions.op.items.len);
    try testing.expectEqual(riscv.isa.RV32Operation.lw, instructions.op.items[0]);
    try testing.expectEqual(riscv.isa.RV32Operation.addi, instructions.op.items[1]);
    try testing.expectEqual(riscv.isa.RV32Operation.sw, instructions.op.items[2]);
}

// ============================================================================
// Edge Case and Error Handling Tests
// ============================================================================

test "edge case: large positive immediate" {
    const allocator = testing.allocator;

    const inst = makeIType(0b0010011, 1, 0, 2, 2047); // Max positive 12-bit immediate
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(@as(i32, 2047), instructions.imm.items[0]);
}

test "edge case: large negative immediate" {
    const allocator = testing.allocator;

    const inst = makeIType(0b0010011, 1, 0, 2, -2048); // Max negative 12-bit immediate
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(@as(i32, -2048), instructions.imm.items[0]);
}

test "edge case: lui with large immediate" {
    const allocator = testing.allocator;

    const inst = makeUType(0b0110111, 1, 0xFFFFF000); // Max U-type immediate
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(@as(i32, @bitCast(@as(u32, 0xFFFFF000))), instructions.imm.items[0]);
}

test "edge case: maximum vector size" {
    const allocator = testing.allocator;

    // Create a large batch of instructions
    const batch_size = 64;
    var inst_array: [batch_size]u32 = undefined;
    for (0..batch_size) |i| {
        // Alternate between ADD and ADDI
        if (i % 2 == 0) {
            inst_array[i] = makeRType(0b0110011, 1, 0, 2, 3, 0);
        } else {
            inst_array[i] = makeIType(0b0010011, 1, 0, 2, @intCast(i));
        }
    }

    var decoder = try riscv.decoder.StageOne(batch_size, 0x80000000){};
    const vec: @Vector(batch_size, u32) = inst_array;
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, batch_size, decoder);

    try testing.expectEqual(@as(usize, batch_size), instructions.op.items.len);
}

test "edge case: all NOPs (addi x0, x0, 0)" {
    const allocator = testing.allocator;

    const nop = makeIType(0b0010011, 0, 0, 0, 0); // NOP = addi x0, x0, 0
    var decoder = try riscv.decoder.StageOne(4, 0x80000000){};
    const vec: @Vector(4, u32) = .{ nop, nop, nop, nop };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 4, decoder);

    // NOPs write to x0, should be filtered out
    try testing.expectEqual(@as(usize, 0), instructions.op.items.len);
}

test "stress test: alternating valid and invalid instructions" {
    const allocator = testing.allocator;

    const batch_size = 32;
    var inst_array: [batch_size]u32 = undefined;
    for (0..batch_size) |i| {
        if (i % 2 == 0) {
            // Valid instruction
            inst_array[i] = makeRType(0b0110011, @intCast(i % 32), 0, 1, 2, 0);
        } else {
            // Invalid instruction (bad opcode)
            inst_array[i] = makeRType(0b1111111, 1, 0, 2, 3, 0);
        }
    }

    var decoder = try riscv.decoder.StageOne(batch_size, 0x80000000){};
    const vec: @Vector(batch_size, u32) = inst_array;
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, batch_size, decoder);

    // Only half should be valid (minus x0 writes)
    try testing.expect(instructions.op.items.len > 0);
    try testing.expect(instructions.op.items.len < batch_size);
}

// ============================================================================
// Performance/Benchmark Tests (commented out, enable for benchmarking)
// ============================================================================

// Uncomment to run benchmark tests
// test "benchmark: decode 1000 instructions" {
//     const allocator = testing.allocator;
//     var timer = try std.time.Timer.start();
//
//     const iterations = 100;
//     var total_time: u64 = 0;
//
//     for (0..iterations) |_| {
//         const batch_size = 1000;
//         var inst_array: [batch_size]u32 = undefined;
//         for (0..batch_size) |i| {
//             inst_array[i] = makeRType(0b0110011, 1, 0, 2, 3, 0);
//         }
//
//         timer.reset();
//         var decoder = try riscv.decoder.StageOne(batch_size, 0x80000000){};
//         const vec: @Vector(batch_size, u32) = inst_array;
//         try decoder.decode(vec);
//
//         var instructions = riscv.decoder.StageTwo.init(allocator);
//         defer instructions.deinit();
//
//         try instructions.validateAndPack(allocator, batch_size, decoder);
//         total_time += timer.read();
//     }
//
//     const avg_time = total_time / iterations;
//     std.debug.print("Average time for 1000 instructions: {d}ns\n", .{avg_time});
// }

// ============================================================================
// Regression Tests (add here as bugs are found and fixed)
// ============================================================================

test "regression: ensure JAL uses J-type immediate" {
    const allocator = testing.allocator;

    // JAL should use imm_j, not imm_i
    const inst = makeJType(0b1101111, 1, 2048);
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.jal, instructions.op.items[0]);
    try testing.expectEqual(@as(i32, 2048), instructions.imm.items[0]);
}

test "regression: ensure JALR uses I-type immediate" {
    const allocator = testing.allocator;

    // JALR should use imm_i, not imm_j
    const inst = makeIType(0b1100111, 1, 0, 2, 8);
    var decoder = try riscv.decoder.StageOne(1, 0x80000000){};
    const vec: @Vector(1, u32) = .{inst};
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init(allocator);
    defer instructions.deinit();

    try instructions.validateAndPack(allocator, 1, decoder);

    try testing.expectEqual(riscv.isa.RV32Operation.jalr, instructions.op.items[0]);
    try testing.expectEqual(@as(i32, 8), instructions.imm.items[0]);
}

test "regression: ECALL/EBREAK should not require rd != 0" {
    const allocator = testing.allocator;

    // System calls don't write to rd, so rd=0 is valid
    const ecall = makeIType(0b1110011, 0, 0, 0, 0);
    const ebreak = makeIType(0b1110011, 0, 0, 0, 1);

    const decoder_type = try riscv.decoder.StageOne(2, 0x80000000);
    var decoder = decoder_type{};
    const vec: @Vector(2, u32) = .{ ecall, ebreak };
    try decoder.decode(vec);

    var instructions = riscv.decoder.StageTwo.init();
    defer instructions.deinit(allocator);

    try instructions.validateAndPack(allocator, 2, decoder);

    // Both should be accepted even with rd=0
    try testing.expectEqual(@as(usize, 2), instructions.op.items.len);
    try testing.expectEqual(riscv.isa.RV32Operation.ecall, instructions.op.items[0]);
    try testing.expectEqual(riscv.isa.RV32Operation.ebreak, instructions.op.items[1]);
}
