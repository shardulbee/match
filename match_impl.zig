const tensor = @import("tensor.zig");
const std = @import("std");

const Error = error{ dimension_mismatch, unimplemented, allocator_error };

pub const MulStrategy = enum {
    naive,
    loop_reorder,
    simd,
    simd_reorder,
    naive_multithreaded,
    multithreaded_loop_reorder,
    multithreaded_simd,
    multithreaded_simd_reorder,
};

pub fn uniform(comptime dtype: type, shape: []const usize, buffer: []dtype) !tensor.Tensor(dtype) {
    var rng = std.rand.DefaultPrng.init(0);
    var r = rng.random();
    for (0..buffer.len) |i| {
        buffer[i] = r.float(dtype);
    }
    return tensor.Tensor(dtype).init(buffer, shape);
}

test "uniform" {
    const allocator = std.testing.allocator;

    const buffer = try allocator.alloc(f64, 1_024 * 1_024);
    defer allocator.free(buffer);

    const shape = try allocator.alloc(usize, 2);
    @memset(shape, 1024);
    defer allocator.free(shape);

    const tens = try uniform(f64, shape, buffer);

    for (0..tens.len) |i| {
        try std.testing.expect(tens.data[i] >= 0);
        try std.testing.expect(tens.data[i] < 1);
    }
}

pub fn identity(comptime dtype: type, shape: []const usize, buffer: []dtype) !tensor.Tensor(dtype) {
    @memset(buffer, 0);

    // error if not square
    if (shape[0] != shape[1]) {
        return error.dimension_mismatch;
    }

    for (0..shape[0]) |i| {
        buffer[i * shape[0] + i] = 1;
    }
    return tensor.Tensor(dtype).init(buffer, shape);
}

pub fn mul(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator, strategy: MulStrategy) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    switch (strategy) {
        .naive => return mul_naive(dtype, a, b, allocator),
        .loop_reorder => return mul_loop_reorder(dtype, a, b, allocator),
        .simd => return mul_simd(dtype, a, b, allocator),
        .simd_reorder => return mul_simd_reorder(dtype, a, b, allocator),
        .naive_multithreaded => return mul_naive_multithreaded(dtype, a, b, allocator),
        .multithreaded_loop_reorder => return mul_multithreaded_loop_reorder(dtype, a, b, allocator),
        .multithreaded_simd => return mul_multithreaded_simd(dtype, a, b, allocator),
        .multithreaded_simd_reorder => return mul_multithreaded_simd_reorder(dtype, a, b, allocator),
    }
}

pub fn mul_simd(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }
    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;

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
                // to get the start of the ith row of a, we do i * a.stride(0)
                // and then we add k * 8 to get the start of the kth group of 8 elements
                // of the ith row of a
                // so we do i * a.stride(0) + k * 8
                // and then we get the first 8 elements of the result
                const lhs: @Vector(8, dtype) = a.data[i * a.stride(0) + k * 8 ..][0..8].*;

                // to get the nth element of the jth column of b, we do n * b.stride(0) + j
                var rhs: @Vector(8, dtype) = @splat(0.0);
                for (0..8) |kk| {
                    rhs[kk] = b.data[(k * 8 + kk) * b.stride(0) + j];
                }

                simd_sum += lhs * rhs;
            }

            data[i * b.shape[1] + j] = @reduce(.Add, simd_sum);
        }
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

test "mul simd" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_simd(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

pub fn mul_simd_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }
    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

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
    defer allocator.free(data);
    @memset(data, @splat(0));

    // iterate over rows of A
    for (0..a.shape[0]) |i| {
        // iterate over cols of A
        for (0..a.shape[1]) |k| {
            const lhs: @Vector(8, dtype) = @splat(a.data[i * a.stride(0) + k]);
            // iterate over the kth row of B, chunk, and scalar multiply, then add to the ith row of C
            for (0..n_vec) |j| {
                // we want the jth group of 8 elements of the kth row of B
                // kth row of B is k * b.stride(0)
                // jth group of 8 elements is j * 8
                const rhs: @Vector(8, dtype) = b.data[(k * b.stride(0) + j * 8)..][0..8].*;
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

    return tensor.Tensor(dtype).init(ret, new_shape);
}

test "mul simd_reorder" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_simd_reorder(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

pub fn mul_loop_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    @memset(data, 0);

    var tempdata = [_]dtype{0} ** 2048;

    for (0..a.shape[0]) |i| {
        for (0..a.shape[1]) |k| {
            // initialize a slice of length b.shape[1]
            // this is the result of multiplying the i,kth element of a by the kth row of b
            // this gets added to the ith row of the result

            for (0..b.shape[1]) |j| {
                // a.stride(0) is how many elements you need to skip to get to the next row
                // since we need the ith row of a, we need to skip i * a.stride(0) elements and then get the kth col
                // b.stride(0) is how many elements you need to skip to get to the next row
                // we need all elements of the jth column of b
                // so we need to skip k * b.stride(0) elements every time
                // and then get the jth element
                tempdata[j] = a.data[i * a.stride(0) + k] * b.data[k * b.stride(0) + j];
            }

            for (0..b.shape[1]) |j| {
                data[i * b.shape[1] + j] += tempdata[j];
            }
            // data[i * b.shape[1] + j] += a.data[i * a.stride(0) + k] * b.data[k * b.stride(0) + j];
        }
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

test "mul loop_reorder" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_loop_reorder(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

pub fn mul_naive(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    // check last dimension of a matches first dimension of b
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    var data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    // @memset(data, 0);

    // WE'RE DOING IT BABY
    for (0..a.shape[0]) |i| {
        for (0..b.shape[1]) |j| {
            var sum: dtype = 0;
            for (0..a.shape[1]) |k| {
                // a.stride(0) is how many elements you need to skip to get to the next row
                // since we need the ith row of a, we need to skip i * a.stride(0) elements and then get the kth col
                const lhs = a.data[i * a.stride(0) + k];

                // b.stride(0) is how many elements you need to skip to get to the next row
                // we need all elements of the jth column of b
                // so we need to skip k * b.stride(0) elements every time
                // and then get the jth element
                const rhs = b.data[k * b.stride(0) + j];
                sum += lhs * rhs;
            }
            data[i * b.shape[1] + j] = sum;
        }
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

test "mul naive" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_naive(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

fn mul_naive_multithreaded_worker(comptime dtype: type, a: *const tensor.Tensor(f64), b: *const tensor.Tensor(f64), data: []dtype, i: usize) void {
    for (0..b.shape[1]) |j| {
        var sum: dtype = 0;
        for (0..a.shape[1]) |k| {
            // a.stride(0) is how many elements you need to skip to get to the next row
            // since we need the ith row of a, we need to skip i * a.stride(0) elements and then get the kth col
            const lhs = a.data[i * a.stride(0) + k];

            // b.stride(0) is how many elements you need to skip to get to the next row
            // we need all elements of the jth column of b
            // so we need to skip k * b.stride(0) elements every time
            // and then get the jth element
            const rhs = b.data[k * b.stride(0) + j];
            sum += lhs * rhs;
        }
        data[i * b.shape[1] + j] = sum;
    }
}

pub fn mul_naive_multithreaded(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    // check last dimension of a matches first dimension of b
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    const data = allocator.alloc(dtype, output_length) catch return error.allocator_error;

    var pool: std.Thread.Pool = undefined;
    pool.init(.{ .allocator = allocator }) catch return error.allocator_error;
    defer pool.deinit();

    for (0..a.shape[0]) |i| {
        pool.spawn(mul_naive_multithreaded_worker, .{ dtype, &a, &b, data, i }) catch return error.allocator_error;
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

test "mul naive_multithreaded" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_naive_multithreaded(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

fn mul_multithreaded_loop_reorder_worker(comptime dtype: type, a: *const tensor.Tensor(f64), b: *const tensor.Tensor(f64), data: []dtype, i: usize) void {
    var tempdata = [_]dtype{0} ** std.math.maxInt(u16);
    for (0..a.shape[1]) |k| {
        // initialize a slice of length b.shape[1]
        // this is the result of multiplying the i,kth element of a by the kth row of b
        // this gets added to the ith row of the result

        for (0..b.shape[1]) |j| {
            // a.stride(0) is how many elements you need to skip to get to the next row
            // since we need the ith row of a, we need to skip i * a.stride(0) elements and then get the kth col
            // b.stride(0) is how many elements you need to skip to get to the next row
            // we need all elements of the jth column of b
            // so we need to skip k * b.stride(0) elements every time
            // and then get the jth element
            tempdata[j] = a.data[i * a.stride(0) + k] * b.data[k * b.stride(0) + j];
        }

        for (0..b.shape[1]) |j| {
            data[i * b.shape[1] + j] += tempdata[j];
        }
    }
}

pub fn mul_multithreaded_loop_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    const data = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    @memset(data, 0);

    var pool: std.Thread.Pool = undefined;
    pool.init(.{ .allocator = allocator }) catch return error.allocator_error;
    defer pool.deinit();

    for (0..a.shape[0]) |i| {
        pool.spawn(mul_multithreaded_loop_reorder_worker, .{ dtype, &a, &b, data, i }) catch return error.allocator_error;
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

test "mul multithreaded_loop_reorder" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_multithreaded_loop_reorder(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

pub fn mul_multithreaded_simd(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }

    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];
    const data = allocator.alloc(dtype, output_length) catch return error.allocator_error;

    // const n_vec: usize = a.shape[0] / 8; // how many SIMD products we do per row of a / col of b
    // const remainder: usize = a.shape[0] % 8; // how many elements are left over

    var pool: std.Thread.Pool = undefined;
    pool.init(.{ .allocator = allocator }) catch return error.allocator_error;
    defer pool.deinit();

    for (0..a.shape[0]) |i| {
        pool.spawn(mul_multithreaded_simd_worker, .{ dtype, &a, &b, data, i }) catch return error.allocator_error;
    }

    return tensor.Tensor(dtype).init(data, new_shape);
}

fn mul_multithreaded_simd_worker(comptime dtype: type, a: *const tensor.Tensor(f64), b: *const tensor.Tensor(f64), data: []dtype, i: usize) void {
    const n_vec: usize = a.shape[0] / 8; // how many SIMD products we do per row of a / col of b
    // const remainder: usize = a.shape[0] % 8; // how many elements are left over
    //
    // if (remainder != 0) {
    //     std.debug.print("we do not support matrix dimensions which are not divisible by 8\n", .{});
    //     return error.unimplemented;
    // }
    for (0..b.shape[1]) |j| {
        var simd_sum: @Vector(8, dtype) = @splat(0.0);
        for (0..n_vec) |k| {
            // we want the kth group of 8 elements of the ith row of a
            // to get the start of the ith row of a, we do i * a.stride(0)
            // and then we add k * 8 to get the start of the kth group of 8 elements
            // of the ith row of a
            // so we do i * a.stride(0) + k * 8
            // and then we get the first 8 elements of the result
            const lhs: @Vector(8, dtype) = a.data[i * a.stride(0) + k * 8 ..][0..8].*;

            // to get the nth element of the jth column of b, we do n * b.stride(0) + j
            var rhs: @Vector(8, dtype) = @splat(0.0);
            for (0..8) |kk| {
                rhs[kk] = b.data[(k * 8 + kk) * b.stride(0) + j];
            }

            simd_sum += lhs * rhs;
        }

        data[i * b.shape[1] + j] = @reduce(.Add, simd_sum);
    }
}

test "mul multithreaded_simd" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 1024, 1024 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_multithreaded_simd(f64, a, b, allocator);
    defer c.deinit(allocator);

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}

fn mul_multithreaded_simd_reorder(comptime dtype: type, a: tensor.Tensor(dtype), b: tensor.Tensor(dtype), allocator: std.mem.Allocator) error{ dimension_mismatch, unimplemented, allocator_error }!tensor.Tensor(dtype) {
    if (a.shape[a.shape.len - 1] != b.shape[0]) {
        return error.dimension_mismatch;
    }

    if (a.shape.len != 2 or b.shape.len != 2) {
        return error.unimplemented;
    }
    const new_shape = allocator.alloc(usize, 2) catch return error.allocator_error;
    new_shape[0] = a.shape[0];
    new_shape[1] = b.shape[1];

    const output_length = a.shape[0] * b.shape[1];

    const n_vec: usize = b.shape[1] / 8; // how many SIMD products we do per row of a / col of b
    const remainder: usize = b.shape[1] % 8; // how many elements are left over

    if (remainder != 0) {
        std.debug.print("we do not support matrix dimensions which are not divisible by 8\n", .{});
        return error.unimplemented;
    }

    // allocate a 2d array of vectors
    var ret = allocator.alloc(dtype, output_length) catch return error.allocator_error;
    const data: []@Vector(8, dtype) = allocator.alloc(@Vector(8, dtype), a.shape[0] * n_vec) catch return error.allocator_error;
    defer allocator.free(data);
    @memset(data, @splat(0));

    var pool: std.Thread.Pool = undefined;
    pool.init(.{ .allocator = allocator }) catch return error.allocator_error;

    // iterate over rows of A
    for (0..a.shape[0]) |i| {
        pool.spawn(mul_multithreaded_simd_reorder_worker, .{ @Vector(8, dtype), &a, &b, data, i }) catch return error.allocator_error;
    }

    pool.deinit();

    // for (pool.threads) |thread| {
    //     thread.join();
    // }

    for (0..a.shape[0]) |i| {
        for (0..n_vec) |j| {
            // number of vecs per row is b.shape[1] / 8
            const vec: @Vector(8, dtype) = data[i * b.shape[1] / 8 + j];
            for (0..8) |kk| {
                ret[(i * b.shape[1] + j * 8 + kk)] = vec[kk];
            }
        }
    }

    return tensor.Tensor(dtype).init(ret, new_shape);
}

fn mul_multithreaded_simd_reorder_worker(comptime dtype: type, a: *const tensor.Tensor(f64), b: *const tensor.Tensor(f64), data: []dtype, i: usize) void {
    const n_vec: usize = b.shape[1] / 8; // how many SIMD products we do per row of a / col of b
    for (0..a.shape[1]) |k| {
        const lhs: dtype = @splat(a.data[i * a.stride(0) + k]);
        // iterate over the kth row of B, chunk, and scalar multiply, then add to the ith row of C
        for (0..n_vec) |j| {
            // we want the jth group of 8 elements of the kth row of B
            // kth row of B is k * b.stride(0)
            // jth group of 8 elements is j * 8
            const rhs: dtype = b.data[(k * b.stride(0) + j * 8)..][0..8].*;

            // TODO need to lock this, but i dont know what to do yet
            data[i * n_vec + j] += lhs * rhs;
        }
    }
}

test "mul multithreaded_simd_reorder" {
    const allocator = std.testing.allocator;
    const shape = &[_]usize{ 4096, 4096 };
    const buffer = try allocator.alloc(f64, shape[0] * shape[1]);
    defer allocator.free(buffer);

    const a = try identity(f64, shape, buffer);
    const b = try identity(f64, shape, buffer);

    const c = try mul_multithreaded_simd_reorder(f64, a, b, allocator);
    defer c.deinit(allocator);

    // std.debug.print("{any}\n", .{c.data});

    try std.testing.expectEqualDeep(c.shape, shape);
    try std.testing.expectEqualDeep(a.data, c.data);
    // try std.testing.expect(std.mem.eql(f64, a.data, c.data));
    try std.testing.expect(std.mem.eql(f64, b.data, c.data));
}
