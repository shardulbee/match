const tensor = @import("tensor.zig");
const std = @import("std");

const Error = error{ dimension_mismatch, unimplemented, allocator_error };

pub const MulStrategy = enum {
    naive,
    loop_reorder,
    simd,
    simd_reorder,
};

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

pub fn mul(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator, strategy: MulStrategy) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    switch (strategy) {
        .naive => return mul_naive(dtype, a, b, allocator),
        .loop_reorder => return mul_loop_reorder(dtype, a, b, allocator),
        .simd => return mul_simd(dtype, a, b, allocator),
        .simd_reorder => return mul_simd_reorder(dtype, a, b, allocator),
    }
}

pub fn mul_simd(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    @memset(data, 0);

    // TODO: implement as SIMD
    // for (0..a.shape[0]) |i| {
    //     for (0..a.shape[1]) |k| {
    //         for (0..b.shape[1]) |j| {
    //             const lhs = a.getitem(&[_]usize{ i, k }) catch return error.unimplemented;
    //             const rhs = b.getitem(&[_]usize{ k, j }) catch return error.unimplemented;
    //             data[i * b.shape[1] + j] += lhs * rhs;
    //         }
    //     }
    // }
    //

    const n_vec: usize = a.shape[0] / 8; // how many SIMD products we do per row of a / col of b
    const remainder: usize = a.shape[0] % 8; // how many elements are left over

    if (remainder != 0) {
        std.debug.print("we do not support matrix dimensions which are not divisible by 8\n", .{});
        return error.unimplemented;
    }

    for (0..a.shape[0]) |i| {
        for (0..b.shape[1]) |j| {
            var simd_sum: @Vector(8, dtype) = @splat(0.0);
            for (0..n_vec) |k| {
                // we want the kth group of 8 elements of the ith row of a
                // to get the start of the ith row of a, we do i * a.stride[0]
                // and then we add k * 8 to get the start of the kth group of 8 elements
                // of the ith row of a
                // so we do i * a.stride[0] + k * 8
                // and then we get the first 8 elements of the result
                const lhs: @Vector(8, dtype) = a.data[i * a.stride[0] + k * 8 ..][0..8].*;

                // to get the nth element of the jth column of b, we do n * b.stride[0] + j
                var rhs: @Vector(8, dtype) = @splat(0.0);
                for (0..8) |kk| {
                    rhs[kk] = b.data[(k * 8 + kk) * b.stride[0] + j];
                }

                simd_sum += lhs * rhs;
            }

            data[i * b.shape[1] + j] = @reduce(.Add, simd_sum);
        }
    }

    const tens = tensor.Tensor(dtype).init(data, &[_]usize{ a.shape[0], b.shape[1] }, allocator) catch {
        allocator.free(data);
        return error.unimplemented;
    };
    allocator.free(data);
    return tens;
}

pub fn mul_simd_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const output_length = a.shape[0] * b.shape[1];

    const n_vec: usize = b.shape[1] / 8; // how many SIMD products we do per row of a / col of b
    const remainder: usize = b.shape[1] % 8; // how many elements are left over

    if (remainder != 0) {
        std.debug.print("we do not support matrix dimensions which are not divisible by 8\n", .{});
        return error.unimplemented;
    }

    // allocate a 2d array of vectors
    var ret = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    var data: []@Vector(8, dtype) = allocator.alloc(@Vector(8, dtype), a.shape[0] * n_vec) catch return error.allocator_error;
    @memset(data, @splat(0));

    // iterate over rows of A
    for (0..a.shape[0]) |i| {
        // iterate over cols of A
        for (0..a.shape[1]) |k| {
            const lhs: @Vector(8, dtype) = @splat(a.data[i * a.stride[0] + k]);
            // iterate over the kth row of B, chunk, and scalar multiply, then add to the ith row of C
            for (0..n_vec) |j| {
                // we want the jth group of 8 elements of the kth row of B
                // kth row of B is k * b.stride[0]
                // jth group of 8 elements is j * 8
                const rhs: @Vector(8, dtype) = b.data[(k * b.stride[0] + j * 8)..][0..8].*;
                data[i * n_vec + j] += lhs * rhs;
            }
        }
    }

    for (0..a.shape[0]) |i| {
        for (0..n_vec) |j| {
            // number of vecs per row is b.shape[1] / 8
            const vec: @Vector(8, dtype) = data[i * b.shape[1] / 8 + j];
            for (0..8) |kk| {
                ret[(i * b.shape[1] + j * 8 + kk)] = vec[kk];
            }
        }
    }

    const tens = tensor.Tensor(dtype).init(ret, &[_]usize{ a.shape[0], b.shape[1] }, allocator) catch {
        allocator.free(data);
        return error.unimplemented;
    };
    allocator.free(ret);
    allocator.free(data);
    return tens;
}

test "mul_simd_reorder" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };

    const a = try uniform(f64, shape, allocator);
    defer a.deinit(allocator);

    const b = try uniform(f64, shape, allocator);
    defer b.deinit(allocator);

    const c = mul(f64, a, b, allocator, .simd_reorder) catch |err| {
        switch (err) {
            error.dimension_mismatch => {
                return;
            },
            error.unimplemented => {
                return;
            },
            else => {
                unreachable;
            },
        }
    };
    defer c.deinit(allocator);

    // assert dim is correct
    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c.shape);
}

test "simd_reorder correctness" {
    // assume that the naive implementation is correct
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };

    const a = try uniform(f64, shape, allocator);
    defer a.deinit(allocator);

    const b = try uniform(f64, shape, allocator);
    defer b.deinit(allocator);

    const c_simd = try mul(f64, a, b, allocator, .simd_reorder);
    defer c_simd.deinit(allocator);

    const c_naive = try mul(f64, a, b, allocator, .naive);
    defer c_naive.deinit(allocator);

    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_simd.shape);
    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_naive.shape);

    try std.testing.expectEqualDeep(c_simd, c_naive);
}

test "simd correctness" {
    // assume that the naive implementation is correct
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };

    const a = try uniform(f64, shape, allocator);
    defer a.deinit(allocator);

    const b = try uniform(f64, shape, allocator);
    defer b.deinit(allocator);

    const c_simd = try mul(f64, a, b, allocator, .simd);
    defer c_simd.deinit(allocator);

    const c_naive = try mul(f64, a, b, allocator, .naive);
    defer c_naive.deinit(allocator);

    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_simd.shape);
    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_naive.shape);

    try std.testing.expectEqualDeep(c_simd, c_naive);
}

test "reorder correctness" {
    // assume that the naive implementation is correct
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };

    const a = try uniform(f64, shape, allocator);
    defer a.deinit(allocator);

    const b = try uniform(f64, shape, allocator);
    defer b.deinit(allocator);

    const c_reorder = try mul(f64, a, b, allocator, .loop_reorder);
    defer c_reorder.deinit(allocator);

    const c_naive = try mul(f64, a, b, allocator, .naive);
    defer c_naive.deinit(allocator);

    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_reorder.shape);
    try std.testing.expectEqualDeep(&[_]usize{ 1024, 1024 }, c_naive.shape);

    try std.testing.expectEqualDeep(c_reorder, c_naive);
}

pub fn mul_loop_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    @memset(data, 0);

    for (0..a.shape[0]) |i| {
        for (0..a.shape[1]) |k| {
            for (0..b.shape[1]) |j| {
                // a.stride[0] is how many elements you need to skip to get to the next row
                // since we need the ith row of a, we need to skip i * a.stride[0] elements and then get the kth col
                const lhs = a.data[i * a.stride[0] + k];

                // b.stride[0] is how many elements you need to skip to get to the next row
                // we need all elements of the jth column of b
                // so we need to skip k * b.stride[0] elements every time
                // and then get the jth element
                const rhs = b.data[k * b.stride[0] + j];
                data[i * b.shape[1] + j] += lhs * rhs;
            }
        }
    }

    const tens = tensor.Tensor(dtype).init(data, &[_]usize{ a.shape[0], b.shape[1] }, allocator) catch {
        allocator.free(data);
        return error.unimplemented;
    };
    allocator.free(data);
    return tens;
}

pub fn mul_naive(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    // check last dimension of a matches first dimension of b
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    @memset(data, 0);

    // WE'RE DOING IT BABY
    for (0..a.shape[0]) |i| {
        for (0..b.shape[1]) |j| {
            for (0..a.shape[1]) |k| {
                // a.stride[0] is how many elements you need to skip to get to the next row
                // since we need the ith row of a, we need to skip i * a.stride[0] elements and then get the kth col
                const lhs = a.data[i * a.stride[0] + k];

                // b.stride[0] is how many elements you need to skip to get to the next row
                // we need all elements of the jth column of b
                // so we need to skip k * b.stride[0] elements every time
                // and then get the jth element
                const rhs = b.data[k * b.stride[0] + j];
                data[i * b.shape[1] + j] += lhs * rhs;
            }
        }
    }

    const tens = tensor.Tensor(dtype).init(data, &[_]usize{ a.shape[0], b.shape[1] }, allocator) catch {
        allocator.free(data);
        return error.unimplemented;
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

    const c = try mul(f32, a, b, allocator, .naive);
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
