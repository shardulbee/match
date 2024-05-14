const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

const std = @import("std");
const match_impl = @import("match_impl.zig");

const PyObject = py.PyObject;
const PyModuleDef = py.PyModuleDef;
const PyModuleCreate = py.PyModule_Create;
const PyMethodDef = py.PyMethodDef;
const METH_VARARGS = py.METH_VARARGS;
const METH_KEYWORDS = py.METH_KEYWORDS;
const PyModuleDef_Base = py.PyModuleDef_Base;

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
var allocator = &arena.allocator();

fn tensor(self: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    _ = self;
    var pylist: [*c]py.PyObject = undefined;

    if (py.PyArg_ParseTuple(args, "O", &pylist) != 1) {
        py.PyErr_SetString(py.PyExc_ValueError, "unable to parse list");
        return null;
    }

    if (py.PyList_Check(pylist) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "argument must be a list");
        return null;
    }

    const size = py.PyList_Size(pylist);
    if (size < 0) {
        py.PyErr_SetString(py.PyExc_ValueError, "len(list) must be >= 0.");
        return null;
    }

    var ret = allocator.alloc(f64, @intCast(size)) catch return null;

    var item: [*c]py.PyObject = undefined;
    for (0..@intCast(size)) |idx| {
        item = py.PyList_GetItem(pylist, @intCast(idx));

        if (py.PyFloat_Check(item) != 1) {
            py.PyErr_SetString(py.PyExc_TypeError, "list items must be floats.");
            return null;
        }
        ret[idx] = py.PyFloat_AsDouble(item);
    }
    return PyTensor_FromTensor(ret);
}

fn uniform_f64(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
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

    var tensor_shape: []usize = allocator.alloc(usize, @intCast(size)) catch return null;
    for (0..@intCast(size)) |idx| {
        tensor_shape[idx] = py.PyLong_AsUnsignedLong(py.PyTuple_GetItem(shape, @intCast(idx)));
    }

    const ret = match_impl.uniform(f64, tensor_shape, allocator.*) catch {
        allocator.free(tensor_shape);
        return null;
    };

    return PyTensor_FromTensor(f64, ret); // fix this to the new thing
}

// array of methods in the module
var MatchMethods = [_]PyMethodDef{
    PyMethodDef{
        .ml_name = "tensor",
        .ml_meth = tensor,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Creates a tensor object",
    },

    PyMethodDef{
        .ml_name = "uniform_f64",
        .ml_meth = uniform_f64,
        .ml_flags = METH_VARARGS,
        .ml_doc = "Create a tensor of f64 which is uniformly distributed in [0, 1)",
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

const PyTensorObject = extern struct { ob_base: py.PyObject, data: [*]f64, len: usize };

pub fn PyTensor_FromTensor(tensor_data: []f64) [*c]PyObject {
    const ptr = PyTensorType.tp_alloc.?(&PyTensorType, 0);

    const obj: [*c]PyTensorObject = @ptrCast(ptr);
    if (obj == null) {
        return null;
    }

    obj.*.data = tensor_data.ptr;
    obj.*.len = tensor_data.len;
    return @ptrCast(obj);
}

fn tensor_repr(self: [*c]PyObject) callconv(.C) [*c]PyObject {
    const obj: [*c]PyTensorObject = @ptrCast(self);
    if (obj == null) {
        return null;
    }

    const tens = obj.*.data[0..obj.*.len];
    return py.PyUnicode_FromFormat("<match.tensor with %d elements>", tens.len);
}

fn match_sum_impl(tens: [*c]PyTensorObject) f64 {
    const floats = tens.*.data[0..tens.*.len];
    var sum: f64 = 0.0;
    for (floats) |item| {
        sum += item;
    }
    return sum;
}

fn match_sum_impl_simd(tens: [*c]PyTensorObject) !f64 {
    // https://developer.apple.com/documentation/accelerate/simd/double-precision_floating-point_vectors
    // it seems like on an M3 max, we can get 8 doubles in a SIMD register
    // so we can sum 8 doubles at a time

    const floats = tens.*.data[0..tens.*.len];
    const num_vecs: usize = tens.*.len / 8;
    const remainder: usize = tens.*.len % 8;

    // sum the SIMD vectors together
    var simd_sum: @Vector(8, f64) = @Vector(8, f64){ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    for (0..num_vecs) |i| {
        const vec: @Vector(8, f64) = floats[i * 8 ..][0..8].*;
        simd_sum += vec;
    }

    // sum the summed SIMD vector
    var sum: f64 = @reduce(.Add, simd_sum);

    // sum the floats which could not fit inside a 8 element SIMD vector to the final sum
    for (floats[num_vecs * 8 .. num_vecs * 8 + remainder]) |item| {
        sum += item;
    }
    return sum;
}

fn match_sum(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
    var simd_bool: [*c]PyObject = undefined;
    var input: [*c]PyObject = undefined;

    if (py.PyArg_ParseTuple(args, "OO", &input, &simd_bool) != 1) {
        py.PyErr_SetString(py.PyExc_ValueError, "unable to arguments");
        return null;
    }

    if (py.PyBool_Check(simd_bool) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "second argument must be a boolean");
        return null;
    }

    if (py.PyObject_TypeCheck(input, &PyTensorType) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "first argument must be a tensor");
        return null;
    }

    const obj: [*c]PyTensorObject = @ptrCast(input);
    if (obj == null) {
        return null;
    }

    var sum: f64 = 0.0;
    if (py.PyObject_IsTrue(simd_bool) == 1) {
        sum = match_sum_impl_simd(obj) catch return null;
    } else {
        sum = match_sum_impl(obj);
    }
    return py.PyFloat_FromDouble(sum);
}

fn tensor_sum(self: [*c]PyObject, args: [*c]PyObject, kwords: [*c]PyObject) callconv(.C) [*c]PyObject {
    var simd: [*c]PyObject = undefined;

    var keywords = [2][]const u8{ "simd", undefined };
    const keyword_list: [*c][*c]u8 = @ptrCast(keywords[0..].ptr);

    if (py.PyArg_ParseTupleAndKeywords(args, kwords, "O", keyword_list, &simd) != 1) {
        py.PyErr_SetString(py.PyExc_ValueError, "unable to parse boolean argument");
        return null;
    }

    if (py.PyBool_Check(simd) != 1) {
        py.PyErr_SetString(py.PyExc_TypeError, "argument must be a boolean");
        return null;
    }

    const obj: [*c]PyTensorObject = @ptrCast(self);
    if (obj == null) {
        return null;
    }

    var sum: f64 = 0.0;
    if (py.PyObject_IsTrue(simd) == 1) {
        sum = match_sum_impl_simd(obj) catch return null;
    } else {
        sum = match_sum_impl(obj);
    }
    return py.PyFloat_FromDouble(sum);
}

var TensorMethods = [_]PyMethodDef{
    // PyMethodDef{
    //     .ml_name = "sum",
    //     .ml_flags = METH_VARARGS | METH_KEYWORDS,
    //     .ml_meth = &tensor_sum,
    //     .ml_doc = "Sum a tensor",
    // },
    // need to end the array with a null PyMethodDef
    // this is how the CPython API knows when to stop looking for methods
    PyMethodDef{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    },
};

fn tensor_free(self: [*c]PyObject) callconv(.C) void {
    const obj: [*c]PyTensorObject = @ptrCast(self);
    if (obj == null) {
        return;
    }

    allocator.free(obj.*.data[0..obj.*.len]);
}

var PyTensorType = py.PyTypeObject{
    .ob_base = py.PyVarObject{ .ob_size = 0 },
    .tp_name = "match.tensor",
    .tp_basicsize = @bitSizeOf(PyTensorObject),
    .tp_doc = "A PyMatch tensor class",
    .tp_repr = tensor_repr,
    .tp_dealloc = tensor_free,
    .tp_methods = &TensorMethods,
};

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
    if (py.PyType_Ready(&PyTensorType) != 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "unable to tensor module");
    }

    return PyModuleCreate(&matchmodule);
}
