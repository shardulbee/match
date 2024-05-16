import match

# import random
import timeit
import numpy as np
import torch as t
# import argparse


def test_mul():
    shape = (1024, 1024)

    match_lhs = match.uniform_f64(shape)
    match_rhs = match.uniform_f64(shape)

    numpy_lhs = np.random.uniform(0, 1, shape)
    numpy_rhs = np.random.uniform(0, 1, shape)

    torch_lhs = t.randn(shape).to(t.device("cpu"))
    torch_rhs = t.randn(shape).to(t.device("cpu"))

    # torch_lhs_gpu = t.randn(shape).to(t.device("mps"))
    # torch_rhs_gpu = t.randn(shape).to(t.device("mps"))

    n_iters = 10

    # benchmarks
    numpy_time = timeit.timeit(lambda: np.matmul(
        numpy_lhs, numpy_rhs), number=n_iters)
    print(f"numpy mul: {numpy_time/n_iters} seconds per iteration")

    torch_time = timeit.timeit(lambda: t.matmul(
        torch_lhs, torch_rhs), number=n_iters)
    print(f"torch mul: {torch_time/n_iters} seconds per iteration")

    # torch_time = timeit.timeit(
    #     lambda: torch_lhs_gpu @ torch_rhs_gpu, number=n_iters)
    # print(f"torch mul (gpu): {torch_time/n_iters} seconds per iteration")

    for strategy in [
        "naive",
        "loop_reorder",
        "simd",
        "simd_reorder",
        "multithreaded_naive",
        "multithreaded_loop_reorder",
        "multithreaded_simd",
        "multithreaded_simd_reorder",
    ]:
        if strategy == "multithreaded_naive":
            strategy = "naive_multithreaded"
        match_time = timeit.timeit(
            lambda: match.mul_f64(match_lhs, match_rhs, strategy), number=n_iters
        )
        print(
            f"zig mul ({strategy}): {match_time/n_iters} seconds per iteration")


if __name__ == "__main__":
    print("testing mul")
    test_mul()
    exit(0)
