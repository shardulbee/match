const tensor = @import("tensor.zig");
const std = @import("std");

const Error = error{ dimension_mismatch, unimplemented };

// only supports integers > 0
fn arange(comptime dtype: type, start: usize, stop: usize, shape: []const usize, allocator: std.mem.Allocator) !tensor.Tensor(dtype) {
    const len: usize = stop - start;
    var data: []dtype = try allocator.alloc(dtype, len);
    switch (@typeInfo(dtype)) {
        .Int => {
            for (start..stop, 0..) |val, i| {
                data[i] = @intCast(val);
            }
        },
        .Float => {
            for (start..stop, 0..) |val, i| {
                data[i] = @floatFromInt(val);
            }
        },
        else => unreachable,
    }

    const tens = tensor.Tensor(dtype).init(data, shape, allocator) catch |err| {
        allocator.free(data);
        return err;
    };
    allocator.free(data);
    return tens;
}

test "arange" {
    const allocator = std.testing.allocator;
    const start: usize = 10;
    const stop: usize = 19;
    const tens = try arange(i64, start, stop, &[_]usize{ 3, 3 }, allocator);
    defer tens.deinit(allocator);

    try std.testing.expectEqual(10, tens.getitem(&[_]usize{ 0, 0 }));
    try std.testing.expectEqual(11, tens.getitem(&[_]usize{ 0, 1 }));
}

pub fn uniform(comptime dtype: type, shape: []const usize, allocator: std.mem.Allocator) !tensor.Tensor(dtype) {
    var size: usize = 1;
    for (shape) |s| {
        size *= s;
    }
    var data = try allocator.alloc(dtype, size);
    var rng = std.rand.DefaultPrng.init(0);
    var r = rng.random();
    for (0..data.len) |i| {
        data[i] = r.float(dtype);
    }
    const tens = tensor.Tensor(dtype).init(data, shape, allocator) catch |err| {
        allocator.free(data);
        return err;
    };
    allocator.free(data);
    return tens;
}

test "uniform" {
    const allocator = std.testing.allocator;
    const tens = try uniform(f32, &[_]usize{1_000_000}, allocator);
    defer tens.deinit(allocator);

    // want to check all elements are in the range [0, 1)
    for (0..tens.len) |i| {
        try std.testing.expect(try tens.getitem(&[_]usize{i}) >= 0);
        try std.testing.expect(try tens.getitem(&[_]usize{i}) < 1);
    }
}

fn mul(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) !tensor.Tensor(dtype) {
    // check last dimension of a matches first dimension of b
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unsupported;
    }

    const output_length = a.shape[0] * b.shape[1];
    var data = try allocator.alloc(dtype, output_length);

    // WE'RE DOING IT BABY
    for (0..a.shape[0]) |i| {
        for (0..b.shape[1]) |j| {
            var sum: dtype = 0;
            for (0..a.shape[1]) |k| {
                sum += try a.getitem(&[_]usize{ i, k }) * try b.getitem(&[_]usize{ k, j });
            }
            data[i * b.shape[1] + j] = sum;
        }
    }

    const tens = tensor.Tensor(dtype).init(data, &[_]usize{ a.shape[0], b.shape[1] }, allocator) catch |err| {
        allocator.free(data);
        return err;
    };
    allocator.free(data);
    return tens;
}

test "mul" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 3, 3 };

    const a = try arange(f32, 1, 10, shape, allocator);
    defer a.deinit(allocator);

    const b = try arange(f32, 1, 10, shape, allocator);
    defer b.deinit(allocator);

    const c = try mul(f32, a, b, allocator);
    defer c.deinit(allocator);

    // assert dim is correct
    try std.testing.expectEqualDeep(&[_]usize{ 3, 3 }, c.shape);

    // assert values are correct
    try std.testing.expectEqual(c.getitem(&[_]usize{ 0, 0 }), 30);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 0, 1 }), 36);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 0, 2 }), 42);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 1, 0 }), 66);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 1, 1 }), 81);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 1, 2 }), 96);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 2, 0 }), 102);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 2, 1 }), 126);
    try std.testing.expectEqual(c.getitem(&[_]usize{ 2, 2 }), 150);
}

test "bigmul" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1000, 1000 };

    const a = try uniform(f64, shape, allocator);
    defer a.deinit(allocator);

    const b = try uniform(f64, shape, allocator);
    defer b.deinit(allocator);

    const c = try mul(f64, a, b, allocator);
    defer c.deinit(allocator);

    // assert dim is correct
    try std.testing.expectEqualDeep(&[_]usize{ 1000, 1000 }, c.shape);
}
