// fn match_sum_impl_simd(tens: [*c]PyTensorObject) !f64 {
//     // https://developer.apple.com/documentation/accelerate/simd/double-precision_floating-point_vectors
//     // it seems like on an M3 max, we can get 8 doubles in a SIMD register
//     // so we can sum 8 doubles at a time
//
//     const floats = tens.*.data[0..tens.*.len];
//     const num_vecs: usize = tens.*.len / 8;
//     const remainder: usize = tens.*.len % 8;
//
//     // sum the SIMD vectors together
//     var simd_sum: @Vector(8, f64) = @Vector(8, f64){ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
//     for (0..num_vecs) |i| {
//         const vec: @Vector(8, f64) = floats[i * 8 ..][0..8].*;
//         simd_sum += vec;
//     }
//
//     // sum the summed SIMD vector
//     var sum: f64 = @reduce(.Add, simd_sum);
//
//     // sum the floats which could not fit inside a 8 element SIMD vector to the final sum
//     for (floats[num_vecs * 8 .. num_vecs * 8 + remainder]) |item| {
//         sum += item;
//     }
//     return sum;
// }
//
// fn match_sum(_: [*c]PyObject, args: [*c]PyObject) callconv(.C) [*c]PyObject {
//     var simd_bool: [*c]PyObject = undefined;
//     var input: [*c]PyObject = undefined;
//
//     if (py.PyArg_ParseTuple(args, "OO", &input, &simd_bool) != 1) {
//         py.PyErr_SetString(py.PyExc_ValueError, "unable to arguments");
//         return null;
//     }
//
//     if (py.PyBool_Check(simd_bool) != 1) {
//         py.PyErr_SetString(py.PyExc_TypeError, "second argument must be a boolean");
//         return null;
//     }
//
//     if (py.PyObject_TypeCheck(input, &PyTensorType) != 1) {
//         py.PyErr_SetString(py.PyExc_TypeError, "first argument must be a tensor");
//         return null;
//     }
//
//     const obj: [*c]PyTensorObject = @ptrCast(input);
//     if (obj == null) {
//         return null;
//     }
//
//     var sum: f64 = 0.0;
//     if (py.PyObject_IsTrue(simd_bool) == 1) {
//         sum = match_sum_impl_simd(obj) catch return null;
//     } else {
//         sum = match_sum_impl(obj);
//     }
//     return py.PyFloat_FromDouble(sum);
// }
