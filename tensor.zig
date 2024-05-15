const std = @import("std");

const IndexError = error{ index_out_of_bounds, unsupported };

const MAX_DIM_LENGTH = 100;

pub fn Tensor(comptime T: type) type {
    return struct {
        data: []const T,
        len: usize,
        stride: []const usize,
        shape: []const usize,
        allocator: std.mem.Allocator,

        pub fn init(data: []const T, shape: []const usize, allocator: std.mem.Allocator) !Tensor(T) {
            var strides: []usize = try allocator.alloc(usize, shape.len);
            var shapes: []usize = try allocator.alloc(usize, shape.len);
            const copied_data: []T = try allocator.alloc(T, data.len);
            // copy data into the new tensor
            for (data, 0..) |item, i| {
                copied_data[i] = item;
            }

            var i: usize = data.len;
            for (shape, 0..) |dim, idx| {
                if (i % dim != 0) {
                    // TODO: return a more specific error
                    return error.unsupported;
                }
                strides[idx] = i / dim;
                shapes[idx] = dim;
                i /= dim;
            }

            if (i != 1) {
                // TODO: return a more specific error
                return error.unsupported;
            }

            return Tensor(T){
                .data = copied_data,
                .len = data.len,
                .stride = strides,
                .shape = shapes,
                .allocator = allocator,
            };
        }

        // init a tensor from heap allocated data
        pub fn init_zerocopy(ndim: usize, data: [*]T, shape: [*]usize, strides: [*]usize, len: usize, allocator: std.mem.Allocator) Tensor(T) {
            return Tensor(T){
                .data = data[0..len],
                .len = len,
                .stride = strides[0..ndim],
                .shape = shape[0..ndim],
                .allocator = allocator,
            };
        }

        pub fn getitem(self: Tensor(T), indices: []const usize) IndexError!T {
            if (indices.len != self.stride.len) {
                // TODO: return a more specific error
                return error.unsupported;
            }

            var i: usize = 0;
            for (indices, 0..self.stride.len) |index, idx| {
                i += index * self.stride[idx];
            }

            if (i >= self.len) {
                std.debug.print("error out of bounds - i: {}, len: {}\n", .{ i, self.len });
                return error.index_out_of_bounds;
            }
            return self.data[i];
        }

        pub fn deinit(self: Tensor(T), allocator: std.mem.Allocator) void {
            allocator.free(self.data);
            allocator.free(self.stride);
            allocator.free(self.shape);
        }

        pub fn reshape(self: Tensor(T), shape: []const usize) !Tensor(T) {
            return Tensor(T).init(self.data, shape, self.allocator);
        }

        pub fn sum(self: Tensor(T)) T {
            // https://developer.apple.com/documentation/accelerate/simd/double-precision_floating-point_vectors
            // it seems like on an M3 max, we can get 8 doubles in a SIMD register
            // so we can sum 8 doubles at a time
            const num_vecs: usize = self.len / 8;
            const remainder: usize = self.len % 8;

            // sum the SIMD vectors together
            var simd_sum: @Vector(8, T) = @splat(0.0);
            for (0..num_vecs) |i| {
                const vec: @Vector(8, T) = self.data[i * 8 ..][0..8].*;
                simd_sum += vec;
            }

            // sum the summed SIMD vector
            var ret: T = @reduce(.Add, simd_sum);

            // sum the floats which could not fit inside a 8 element SIMD vector to the final sum
            for (self.data[num_vecs * 8 .. num_vecs * 8 + remainder]) |item| {
                ret += item;
            }
            return ret;
        }

        pub fn equal(self: Tensor(T), other: Tensor(T)) bool {
            // nelements must be equal
            if (self.len != other.len) {
                return false;
            }

            // strides must be equal
            if (self.stride.len != other.stride.len) {
                return false;
            }
            for (self.stride, other.stride) |s1, s2| {
                if (s1 != s2) {
                    return false;
                }
            }

            // all the elements must be equal
            return std.mem.eql(T, self.data, other.data);
        }
    };
}

test "getitem indexing completely defined" {
    const T = f32;
    const allocator = std.testing.allocator;
    const tensor = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 27,
    }, &[_]usize{ 3, 3, 3 }, allocator);
    defer tensor.deinit(allocator);

    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 0, 0 }), 1);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 0, 1 }), 2);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 0, 2 }), 3);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 1, 0 }), 4);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 1, 1 }), 5);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 1, 2 }), 6);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 2, 0 }), 7);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 2, 1 }), 8);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 0, 2, 2 }), 9);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 0, 0 }), 10);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 0, 1 }), 11);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 0, 2 }), 12);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 1, 0 }), 13);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 1, 1 }), 14);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 1, 2 }), 15);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 2, 0 }), 16);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 2, 1 }), 17);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 1, 2, 2 }), 18);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 0, 0 }), 19);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 0, 1 }), 20);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 0, 2 }), 21);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 1, 0 }), 22);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 1, 1 }), 23);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 1, 2 }), 24);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 2, 0 }), 25);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 2, 1 }), 26);
    try std.testing.expectEqual(tensor.getitem(&[_]usize{ 2, 2, 2 }), 27);
}

test "reshape" {
    const T = f32;
    const allocator = std.testing.allocator;
    const tensor = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 27,
    }, &[_]usize{ 3, 3, 3 }, allocator);
    defer tensor.deinit(allocator);
    const reshaped = try tensor.reshape(&[_]usize{ 9, 3 });
    defer reshaped.deinit(allocator);
    try std.testing.expectEqualDeep(&[_]usize{ 3, 1 }, reshaped.stride);

    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 0, 0 }), 1);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 0, 1 }), 2);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 0, 2 }), 3);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 1, 0 }), 4);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 1, 1 }), 5);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 1, 2 }), 6);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 2, 0 }), 7);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 2, 1 }), 8);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 2, 2 }), 9);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 3, 0 }), 10);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 3, 1 }), 11);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 3, 2 }), 12);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 4, 0 }), 13);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 4, 1 }), 14);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 4, 2 }), 15);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 5, 0 }), 16);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 5, 1 }), 17);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 5, 2 }), 18);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 6, 0 }), 19);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 6, 1 }), 20);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 6, 2 }), 21);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 7, 0 }), 22);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 7, 1 }), 23);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 7, 2 }), 24);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 8, 0 }), 25);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 8, 1 }), 26);
    try std.testing.expectEqual(reshaped.getitem(&[_]usize{ 8, 2 }), 27);
}

test "equal" {
    const T = f32;
    const allocator = std.testing.allocator;

    // same struct
    const tensor = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 27,
    }, &[_]usize{ 3, 3, 3 }, allocator);
    defer tensor.deinit(allocator);
    try std.testing.expect(tensor.equal(tensor));

    // same data
    var other = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 27,
    }, &[_]usize{ 3, 3, 3 }, allocator);
    try std.testing.expect(tensor.equal(other));
    try std.testing.expect(other.equal(tensor));
    other.deinit(allocator);

    // different data
    other = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 28,
    }, &[_]usize{ 3, 3, 3 }, allocator);
    try std.testing.expect(!tensor.equal(other));
    other.deinit(allocator);

    // different shape
    other = try Tensor(T).init(&[_]T{
        1,  2,  3,
        4,  5,  6,
        7,  8,  9,
        10, 11, 12,
        13, 14, 15,
        16, 17, 18,
        19, 20, 21,
        22, 23, 24,
        25, 26, 27,
    }, &[_]usize{ 9, 3 }, allocator);
    try std.testing.expect(!tensor.equal(other));
    other.deinit(allocator);
}
