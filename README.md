# `match`

`match` is a re-implementation of a subset of the PyTorch API in Zig. The goal was to learn more about a variety of topics with a small project. This includes:

- writing a native Python extension
- Learning Zig
- Manual memory management
- SIMD
- Performance optimization
- Matrix multiplication algorithms

## Benchmarks

### Matrix multiplication

I ran 10 iterations of matrix multiplication with matrices of size 1024x1024. The following benchmarks were run on a MacBook Pro M3 Max.

```
numpy mul: 0.016309575000195763 seconds per iteration
torch mul: 0.001465362499584444 seconds per iteration
zig mul (naive): 0.9365535666991491 seconds per iteration
zig mul (loop_reorder): 0.45489666670036966 seconds per iteration
zig mul (simd): 0.9111807208013488 seconds per iteration
zig mul (simd_reorder): 0.16331577909877523 seconds per iteration
zig mul (naive_multithreaded): 0.1352780791989062 seconds per iteration
zig mul (multithreaded_loop_reorder): 0.05411136249895208 seconds per iteration
zig mul (multithreaded_simd): 0.12674717499758117 seconds per iteration
zig mul (multithreaded_simd_reorder): 0.023085283298860303 seconds per iteration
```
