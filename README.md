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

| strategy | milliseconds per iteration|
| -------- | ------------------------- |
| numpy | `16.3` |
| torch | `1.5` |
| zig mul (naive) | `937` |
| zig mul (loop_reorder) | `455` |
| zig mul (simd) | `911` |
| zig mul (simd_reorder) | `163` |
| zig mul (naive_multithreaded) | `135` |
| zig mul (multithreaded_loop_reorder) | `54` |
| zig mul (multithreaded_simd) | `127` |
| zig mul (multithreaded_simd_reorder) | `23` |
