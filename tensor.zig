const std = @import("std");

pub fn Tensor(comptime T: type) type {
    return struct {
        data: []const T, // pointer (usize) and a length (usize) = 16 bytes
        shape: []const usize, // pointer (usize) and a length (usize) = 16
        len: usize, // usize = 8 bytes

        pub fn init(data: []const T, shape: []const usize) Tensor(T) {
            // TODO: validate shape
            return Tensor(T){
                .data = data,
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

        // Caller owns all memory
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
            if (self.len != other.len) {
                return false;
            }

            if (self.shape.len != other.shape.len) {
                return false;
            }
            if (!std.mem.eql(T, self.shape, other.shape)) {
                return false;
            }

            // all the elements must be equal
            return std.mem.eql(T, self.data, other.data);
        }
    };
}
