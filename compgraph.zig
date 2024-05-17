const std = @import("std");

// match.mul(a, b) should return a new tensor whihc is the result, but also instantiates a new graph

// c should point to the mul op node
// mul op node should have two fields lhs and rhs which are pointers to other nodes

const OpKind = enum {
    mul,
    add,
    sub,
};

// a node is considered a leaf node if the op that produced it is null
//
pub fn Op(comptime dtype: type) type {
    return struct {
        kind: OpKind,
        lhs: *const Node(dtype),
        rhs: *const Node(dtype),
    };
}

pub fn Node(comptime dtype: type) type {
    return struct {
        val: dtype,
        op: ?Op(dtype),

        pub fn init_leaf(val: dtype) Node(dtype) {
            return Node(dtype){
                .val = val,
                .op = null,
            };
        }
    };
}

fn mul(comptime dtype: type, a: Node(dtype), b: Node(dtype)) Node(dtype) {
    return Node(dtype){
        .val = a.val * b.val,
        .op = Op(dtype){
            .kind = OpKind.mul,
            .lhs = &a,
            .rhs = &b,
        },
    };
}

test "Node" {
    const a = Node(f32).init_leaf(1);
    const b = Node(f32).init_leaf(2);
    const c = mul(f32, a, b);
    try std.testing.expectEqual(c.val, 2);
    try std.testing.expectEqual(c.op.?.kind, OpKind.mul);
    try std.testing.expectEqual(c.op.?.lhs, &a);
    try std.testing.expectEqual(c.op.?.rhs, &b);
}

// ok what i am realizing is that a tensor is a node
