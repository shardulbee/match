# Notes

## TODO

- [ ] figure out why simd correctness is failing
- [ ] figure out if numpy/torch are using multithreaded loops
- [ ] start implementing multithreading
- [ ] fix up matmul to support non-multiple of 8 matrix dimensions
- [x] add a test for simd reorder correctness
- [x] add a test for simd correctness
- [x] add a test for reorder correctness
- [ ] add tests for matmul correctness within python (compare to numpy/torch)
-
-


## autograd

- build a computation graph
  - every time you do an op with a tensor (or multiple tensors), you add it to the graph
  - x + y + z = a, then you add (x + y) + z = a
