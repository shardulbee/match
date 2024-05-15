const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

const std = @import("std");
const match_impl = @import("match_impl.zig");
const tensor_impl = @import("tensor.zig");

const PyObject = py.PyObject;
const PyModuleDef = py.PyModuleDef;
const PyModuleCreate = py.PyModule_Create;
const PyMethodDef = py.PyMethodDef;
const METH_VARARGS = py.METH_VARARGS;
const METH_KEYWORDS = py.METH_KEYWORDS;
const PyModuleDef_Base = py.PyModuleDef_Base;

const allocator = &std.heap.page_allocator;

// create parse error
const ParseError = error{ ParseError, AllocError };

fn uniform_f64(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    const shape: []usize = parse_shape(args) catch return null;

    const ret = match_impl.uniform(f64, shape, allocator.*) catch {
        allocator.free(shape);
        return null;
    };

    const tens = PyTensor_FromTensor(f64, &ret);
    return @ptrCast(tens);
}

fn uniform_f32(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    const shape: []usize = parse_shape(args) catch return null;

    const ret = match_impl.uniform(f32, shape, allocator.*) catch {
        allocator.free(shape);
        return null;
    };

    const tens = PyTensor_FromTensor(f32, &ret);
    return @ptrCast(tens);
}

fn parse_shape(args: [*c]py.PyObject) error{ ParseError, AllocError }![]usize {
    var shape: [*c]py.PyObject = undefined;

    if (py.PyArg_ParseTuple(args, "O", &shape) != 1) {
        py.PyErr_SetString(py.PyExc_ValueError, "unable to parse shape argument");
        return ParseError.ParseError;
    }

    if (py.PyTuple_Check(shape) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "shape argument must be a list");
        return ParseError.ParseError;
    }

    const size: isize = py.PyTuple_Size(shape);
    if (size < 0) {
        py.PyErr_SetString(py.PyExc_ValueError, "len(shape) must be >= 0.");
        return ParseError.ParseError;
    }

    var tensor_shape: []usize = allocator.alloc(usize, @intCast(size)) catch return error.AllocError;
    for (0..@intCast(size)) |idx| {
        tensor_shape[idx] = py.PyLong_AsUnsignedLong(py.PyTuple_GetItem(shape, @intCast(idx)));
    }
    return tensor_shape;
}

// array of methods in the module
var MatchMethods = [_]PyMethodDef{
    PyMethodDef{
        .ml_name = "uniform_f64",
        .ml_meth = uniform_f64,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Create a tensor of f64 which is uniformly distributed in [0, 1)",
    },
    PyMethodDef{
        .ml_name = "uniform_f32",
        .ml_meth = uniform_f32,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Create a tensor of f32 which is uniformly distributed in [0, 1)",
    },

    // need to end the array with a null PyMethodDef
    // this is how the CPython API knows when to stop looking for methods
    PyMethodDef{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    },
};

fn PyTensorObject(comptime dtype: type) type {
    return extern struct {
        ob_base: py.PyObject,

        data: [*]const dtype,
        len: usize,
        stride: [*]const usize,
        shape: [*]const usize,
        dtype: [*]const u8,
        ndim: usize,
    };
}

pub fn PyTensor_AsTensor(comptime dtype: type, obj: [*c]PyObject) tensor_impl.Tensor(dtype) {
    const py_tensor_object: *const PyTensorObject(dtype) = @ptrCast(obj);
    const as_tensor = tensor_impl.Tensor(dtype).init_zerocopy(py_tensor_object.ndim, @constCast(py_tensor_object.data[0..py_tensor_object.len].ptr), @constCast(py_tensor_object.shape[0..py_tensor_object.ndim].ptr), @constCast(py_tensor_object.stride[0..py_tensor_object.ndim].ptr), py_tensor_object.len, allocator.*);
    return as_tensor;
}

pub fn PyTensor_FromTensor(comptime dtype: type, tensor_data: *const tensor_impl.Tensor(dtype)) [*c]py.PyObject {
    const type_object: *const py.PyTypeObject = switch (dtype) {
        f64 => PyTensorF64.type_object,
        f32 => PyTensorF32.type_object,
        else => unreachable,
    };
    const alloc_fn = type_object.*.tp_alloc.?;

    const ptr: [*c]PyObject = alloc_fn(@constCast(type_object), 0);
    if (ptr == null) {
        return null;
    }

    const obj: *PyTensorObject(dtype) = @ptrCast(ptr);
    obj.*.data = tensor_data.data.ptr;
    obj.*.len = tensor_data.len;
    obj.*.stride = tensor_data.stride.ptr;
    obj.*.shape = tensor_data.shape.ptr;
    obj.*.dtype = @ptrCast(@typeName(dtype));
    obj.*.ndim = tensor_data.shape.len;
    return @ptrCast(obj);
}

fn PyTensor(comptime dtype: type) type {
    return struct {
        type_object: *const py.PyTypeObject,

        pub fn init() PyTensor(dtype) {
            return PyTensor(dtype){
                .type_object = &py.PyTypeObject{
                    .ob_base = py.PyVarObject{
                        .ob_base = py.PyObject{
                            .ob_refcnt = std.math.maxInt(isize),
                            .ob_type = null,
                        },
                        .ob_size = 0,
                    },
                    .tp_name = "match.tensor",
                    .tp_basicsize = @sizeOf(PyTensorObject(dtype)),
                    .tp_doc = "A PyMatch tensor class",
                    .tp_alloc = py.PyType_GenericAlloc,
                    .tp_free = free,
                    // .tp_dealloc = tensor_free, // TODO: implement a generic free
                    .tp_repr = tensor_repr,
                    .tp_methods = @constCast(&[_]PyMethodDef{
                        PyMethodDef{
                            .ml_name = "sum",
                            .ml_meth = sum,
                            .ml_flags = METH_VARARGS,
                            .ml_doc = "Sum a tensor",
                        },
                        PyMethodDef{
                            .ml_name = null,
                            .ml_meth = null,
                            .ml_flags = 0,
                            .ml_doc = null,
                        },
                    }),
                },
            };
        }

        pub fn free(self: ?*anyopaque) callconv(.C) void {
            if (self == null) {
                return;
            }
            const obj: *PyTensorObject(dtype) = @ptrCast(@alignCast(self));
            allocator.free(obj.data[0..obj.len]);
            allocator.free(obj.stride[0..obj.ndim]);
            allocator.free(obj.shape[0..obj.ndim]);
        }

        pub fn tensor_repr(self: [*c]PyObject) callconv(.C) [*c]PyObject {
            const obj: *PyTensorObject(dtype) = @ptrCast(self);
            const as_tensor = PyTensor_AsTensor(dtype, self);
            std.debug.print("tensor as tensor len: {any}\n", .{as_tensor.len});
            std.debug.print("tensor as c obj len: {any}\n", .{obj.len});
            return py.PyUnicode_FromFormat("<match.tensor with %d elements with dtype=%s>", obj.len, @typeName(dtype));
        }

        pub fn sum(self: [*c]PyObject, _: [*c]PyObject) callconv(.C) [*c]PyObject {
            const as_tensor = PyTensor_AsTensor(dtype, self);
            return py.PyFloat_FromDouble(as_tensor.sum());
        }
    };
}

const PyTensorF64: PyTensor(f64) = PyTensor(f64).init();
const PyTensorF32: PyTensor(f32) = PyTensor(f32).init();

// module definition
var matchmodule = PyModuleDef{
    .m_base = PyModuleDef_Base{
        .ob_base = PyObject{
            .ob_refcnt = 1,
            .ob_type = null,
        },
        .m_init = null,
        .m_index = 0,
        .m_copy = null,
    },
    .m_name = "match",
    .m_methods = &MatchMethods,
    .m_doc = "A re-implementation of a subset of the PyTorch API in Zig.",
    .m_size = -1, // this means that the module state is global
    .m_slots = null, // not sure what this is
    .m_traverse = null, // dont specify a traversal function during GC of the module obj
    .m_clear = null, // dont specify a clear function during GC of the module obj
    .m_free = null, // dont specify a free function during GC of the module obj
};

pub export fn PyInit_match() [*]PyObject {
    if (py.PyType_Ready(@constCast(PyTensorF64.type_object)) != 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "unable to initialize f64 tensor type");
    }
    //
    if (py.PyType_Ready(@constCast(PyTensorF32.type_object)) != 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "unable to initialize f32 tensor type");
    }

    return PyModuleCreate(&matchmodule);
}
