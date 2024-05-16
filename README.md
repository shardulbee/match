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

| strategy | seconds per iteration|
|----------|----------------------|
| numpy | 0.016309575000195763 |
| torch | 0.001465362499584444 |
| zig mul (naive) | 0.9365535666991491 |
| zig mul (loop_reorder) | 0.45489666670036966 |
| zig mul (simd) | 0.9111807208013488 |
| zig mul (simd_reorder) | 0.16331577909877523 |
| zig mul (naive_multithreaded) | 0.1352780791989062 |
| zig mul (multithreaded_loop_reorder) | 0.05411136249895208 |
| zig mul (multithreaded_simd) | 0.12674717499758117 |
| zig mul (multithreaded_simd_reorder) | 0.023085283298860303 |

Now as miliseconds, rounded to the closest milisecond:

| strategy | milliseconds per iteration|
| -------- | ------------------------- |
| numpy | 16.3 |
| torch | 1.5 |
| zig mul (naive) | 937 |
| zig mul (loop_reorder) | 455 |
| zig mul (simd) | 911 |
| zig mul (simd_reorder) | 163 |
| zig mul (naive_multithreaded) | 135 |
| zig mul (multithreaded_loop_reorder) | 54 |
| zig mul (multithreaded_simd) | 127 |
| zig mul (multithreaded_simd_reorder) | 23 |
