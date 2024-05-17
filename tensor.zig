const std = @import("std");

const Error = error{dimension_mismatch};

fn Tensor(comptime T: type) type {
    return struct {
        data: []T, // pointer (usize) and a length (usize) = 16 bytes
        shape: []const usize, // pointer (usize) and a length (usize) = 16
        len: usize, // usize = 8 bytes

        pub fn init(data: []const T, shape: []const usize) error{dimension_mismatch}!Tensor(T) {
            var prod: usize = 1;
            for (shape) |s| {
                prod *= s;
            }
            if (prod != data.len) {
                return error.dimension_mismatch;
            }

            return Tensor(T){
                .data = @constCast(data),
                .len = data.len,
                .shape = shape,
            };
        }

        pub fn stride(self: Tensor(T), idx: usize) usize {
            return self.data.len / self.shape[idx];
        }

        pub fn deinit(self: Tensor(T), allocator: std.mem.Allocator) void {
            allocator.free(self.data);
            allocator.free(self.shape);
        }

        /// Caller owns all memory and must take care of freeing it
        pub fn reshape(self: Tensor(T), shape: []const usize) error{dimension_mismatch}!Tensor(T) {
            return try Tensor(T).init(self.data, shape);
        }

        // TODO: decide if this should this overwrite the data or return a new one
        pub fn apply(self: Tensor(T), F: fn (comptime type, T) T) Tensor(T) {
            for (0..self.len) |i| {
                self.data[i] = F(T, self.data[i]);
            }
            return self;
        }

        // TODO: add some tests for data.len < 8
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
            if (self.len != other.len) {
                return false;
            }

            if (self.shape.len != other.shape.len) {
                return false;
            }
            if (!std.mem.eql(T, self.shape, other.shape)) {
                return false;
            }

            return std.mem.eql(T, self.data, other.data);
        }
    };
}
