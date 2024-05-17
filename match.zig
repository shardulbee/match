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

fn uniform_f64(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    return PyTensor(f64).uniform(args);
}

fn uniform_f32(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    return PyTensor(f32).uniform(args);
}

pub fn mul_f64(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    return PyTensor(f64).mul(args);
}

pub fn mul_f32(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    return PyTensor(f32).mul(args);
}

fn parse_shape(args: [*c]py.PyObject) ?[]usize {
    var shape: [*c]py.PyObject = undefined;

    if (py.PyArg_ParseTuple(args, "O", &shape) != 1) {
        py.PyErr_SetString(py.PyExc_ValueError, "unable to parse shape argument");
        return null;
    }

    if (py.PyTuple_Check(shape) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "shape argument must be a list");
        return null;
    }

    const size: isize = py.PyTuple_Size(shape);
    if (size < 0) {
        py.PyErr_SetString(py.PyExc_ValueError, "len(shape) must be >= 0.");
        return null;
    }

    var tensor_shape: []usize = allocator.alloc(usize, @intCast(size)) catch {
        py.PyErr_SetString(py.PyExc_MemoryError, "unable to allocate memory for tensor shape");
        return null;
    };
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
    PyMethodDef{
        .ml_name = "mul_f64",
        .ml_meth = mul_f64,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Multiply two f64 tensors",
    },
    PyMethodDef{
        .ml_name = "mul_f32",
        .ml_meth = mul_f32,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Multiply two f32 tensors",
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

fn PyTensor(comptime dtype: type) type {
    switch (dtype) {
        f64 => {},
        f32 => {},
        else => {
            @compileError("unsupported dtype");
        },
    }
    return struct {
        var type_object: *const py.PyTypeObject = &py.PyTypeObject{
            .ob_base = py.PyVarObject{
                .ob_base = py.PyObject{
                    .ob_refcnt = std.math.maxInt(isize),
                    .ob_type = null,
                },
                .ob_size = 0,
            },
            .tp_name = "match.tensor",
            .tp_basicsize = @sizeOf(PyTensorObject()),
            .tp_doc = "A PyMatch tensor class",
            .tp_alloc = py.PyType_GenericAlloc,
            .tp_free = free,
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
        };

        fn PyTensorObject() type {
            return extern struct {
                ob_base: py.PyObject,

                data: [*]const dtype,
                len: usize,
                shape: [*]const usize,
                dtype: [*]const u8,
                ndim: usize,
            };
        }

        pub fn AsTensor(obj: [*c]PyObject) tensor_impl.Tensor(dtype) {
            const py_tensor_object: *const PyTensorObject() = @ptrCast(obj);

            // tensor initialization should only fail for dimension mistmatch
            // but this is converted from a python object which can only be created
            // by the zig code. so we can swallow the error.
            return tensor_impl.Tensor(dtype).init(
                py_tensor_object.data[0..py_tensor_object.len],
                py_tensor_object.shape[0..py_tensor_object.ndim],
            ) catch unreachable;
        }

        pub fn FromTensor(tensor_data: *const tensor_impl.Tensor(dtype)) [*c]py.PyObject {
            const alloc_fn = type_object.*.tp_alloc.?;

            const ptr: [*c]PyObject = alloc_fn(@constCast(type_object), 0);
            if (ptr == null) {
                return null;
            }

            const obj: *PyTensorObject() = @ptrCast(ptr);
            obj.*.data = tensor_data.data.ptr;
            obj.*.len = tensor_data.len;
            obj.*.shape = tensor_data.shape.ptr;
            obj.*.dtype = @ptrCast(@typeName(dtype));
            obj.*.ndim = tensor_data.shape.len;
            return @ptrCast(obj);
        }

        pub fn free(self: ?*anyopaque) callconv(.C) void {
            if (self == null) {
                return;
            }
            const py_tensor_object: [*c]PyObject = @ptrCast(@alignCast(self));

            @This().AsTensor(py_tensor_object).deinit(allocator.*);
        }

        pub fn tensor_repr(self: [*c]PyObject) callconv(.C) [*c]PyObject {
            const obj: *PyTensorObject() = @ptrCast(self);
            return py.PyUnicode_FromFormat("<match.tensor with %d elements with dtype=%s>", obj.len, @typeName(dtype));
        }

        pub fn sum(self: [*c]PyObject, _: [*c]PyObject) callconv(.C) [*c]PyObject {
            const as_tensor = @This().AsTensor(self);
            return py.PyFloat_FromDouble(as_tensor.sum());
        }

        pub fn uniform(args: [*c]PyObject) callconv(.C) [*c]PyObject {
            const parsed_shape: ?[]usize = parse_shape(args);
            if (parsed_shape == null) {
                return null;
            }
            const shape = parsed_shape.?;

            var data_len: usize = 1;
            for (shape) |s| {
                data_len *= s;
            }

            const buffer = allocator.alloc(dtype, data_len) catch {
                py.PyErr_SetString(py.PyExc_MemoryError, "unable to allocate memory for tensor");
                return null;
            };

            const uniform_tensor = match_impl.uniform(dtype, shape, buffer) catch {
                allocator.free(shape);
                allocator.free(buffer);
                return null; // TODO: set python exception
            };

            const tensor_python_object = @This().FromTensor(&uniform_tensor);
            return @ptrCast(tensor_python_object);
        }

        pub fn mul(args: [*c]PyObject) callconv(.C) [*c]PyObject {
            var first_arg: [*c]PyObject = undefined;
            var second_arg: [*c]PyObject = undefined;
            var strategy: [*c]PyObject = undefined;

            if (py.PyArg_ParseTuple(args, "OOO", &first_arg, &second_arg, &strategy) != 1) {
                py.PyErr_SetString(py.PyExc_ValueError, "unable to parse arguments");
                return null;
            }

            if (py.PyObject_TypeCheck(first_arg, @constCast(type_object)) != 1) {
                py.PyErr_SetString(py.PyExc_TypeError, "first argument must be a f64 tensor");
                return null;
            }

            if (py.PyObject_TypeCheck(second_arg, @constCast(type_object)) != 1) {
                py.PyErr_SetString(py.PyExc_TypeError, "second argument must be a f64 tensor");
                return null;
            }

            if (py.PyUnicode_Check(strategy) != 1) {
                py.PyErr_SetString(py.PyExc_TypeError, "strategy argument must be a string");
                return null;
            }

            const strategy_str = py.PyUnicode_AsUTF8(strategy);
            const length: usize = @intCast(py.PyUnicode_GetLength(strategy));

            var strategy_arg: match_impl.MulStrategy = undefined;
            if (std.mem.eql(u8, strategy_str[0..length], "naive")) {
                strategy_arg = match_impl.MulStrategy.naive;
            } else if (std.mem.eql(u8, strategy_str[0..length], "loop_reorder")) {
                strategy_arg = match_impl.MulStrategy.loop_reorder;
            } else if (std.mem.eql(u8, strategy_str[0..length], "simd")) {
                strategy_arg = match_impl.MulStrategy.simd;
            } else if (std.mem.eql(u8, strategy_str[0..length], "simd_reorder")) {
                strategy_arg = match_impl.MulStrategy.simd_reorder;
            } else if (std.mem.eql(u8, strategy_str[0..length], "naive_multithreaded")) {
                strategy_arg = match_impl.MulStrategy.naive_multithreaded;
            } else if (std.mem.eql(u8, strategy_str[0..length], "multithreaded_loop_reorder")) {
                strategy_arg = match_impl.MulStrategy.multithreaded_loop_reorder;
            } else if (std.mem.eql(u8, strategy_str[0..length], "multithreaded_simd")) {
                strategy_arg = match_impl.MulStrategy.multithreaded_simd;
            } else if (std.mem.eql(u8, strategy_str[0..length], "multithreaded_simd_reorder")) {
                strategy_arg = match_impl.MulStrategy.multithreaded_simd_reorder;
            } else if (std.mem.eql(u8, strategy_str[0..length], "multithreaded_tiled")) {
                strategy_arg = match_impl.MulStrategy.multithreaded_tiled;
            } else {
                py.PyErr_SetString(py.PyExc_ValueError, "strategy must be 'naive' or 'loop_reorder'");
                return null;
            }

            const first_tensor: tensor_impl.Tensor(dtype) = AsTensor(first_arg);
            const second_tensor: tensor_impl.Tensor(dtype) = AsTensor(second_arg);

            // mul will allocate memory for the result
            const result = match_impl.mul(dtype, first_tensor, second_tensor, allocator.*, strategy_arg) catch |err| {
                switch (err) {
                    error.dimension_mismatch => {
                        py.PyErr_SetString(py.PyExc_ValueError, "dimension mismatch");
                        return null;
                    },
                    error.unimplemented => {
                        py.PyErr_SetString(py.PyExc_ValueError, "unimplemented");
                        return null;
                    },
                    else => {
                        unreachable;
                    },
                }
            };

            return PyTensor(dtype).FromTensor(&result);
        }
    };
}

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
    if (py.PyType_Ready(@constCast(PyTensor(f64).type_object)) != 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "unable to initialize f64 tensor type");
    }
    if (py.PyType_Ready(@constCast(PyTensor(f32).type_object)) != 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "unable to initialize f32 tensor type");
    }
    return PyModuleCreate(&matchmodule);
}
