import match
import random
import timeit
import numpy as np
import torch as t
import argparse


def test_sum():
    shape = (100, 100)
    python_floats = [random.uniform(0, 1) for _ in range(shape[0] * shape[1])]
    match_tensor = match.uniform_f64(shape)
    numpy_ndarray = np.random.uniform(0, 1, shape)
    torch_tensor = t.randn(shape)

    # benchmark 10000 runs of python-native sum
    native_time = timeit.timeit(
        lambda: sum(python_floats), number=100_000
    )  # run one million times
    print(f"python sum: {native_time}")

    match_time = timeit.timeit(lambda: match_tensor.sum(), number=100_000)
    print(f"zig simd sum: {match_time}")

    # benchmark 10000 runs of numpy.sum
    numpy_time = timeit.timeit(lambda: numpy_ndarray.sum(), number=100_000)
    print(f"numpy sum: {numpy_time}")

    # benchmark 10000 runs of torch.sum
    torch_time = timeit.timeit(lambda: torch_tensor.sum(), number=100_000)
    print(f"torch sum: {torch_time}")


def test_mul():
    shape = (1024, 1024)

    match_lhs = match.uniform_f64(shape)
    match_rhs = match.uniform_f64(shape)

    numpy_lhs = np.random.uniform(0, 1, shape)
    numpy_rhs = np.random.uniform(0, 1, shape)

    torch_lhs = t.randn(shape).to(t.device("cpu"))
    torch_rhs = t.randn(shape).to(t.device("cpu"))

    n_iters = 10

    # benchmarks
    numpy_time = timeit.timeit(lambda: np.matmul(numpy_lhs, numpy_rhs), number=n_iters)
    print(f"numpy mul: {numpy_time/n_iters} seconds per iteration")

    torch_time = timeit.timeit(lambda: torch_lhs @ torch_rhs, number=n_iters)
    print(f"torch mul: {torch_time/10} seconds per iteration")

    match_time = timeit.timeit(
        lambda: match.mul_f64(match_lhs, match_rhs, "naive"), number=n_iters
    )
    print(f"zig mul: {match_time/n_iters} seconds per iteration")

    match_time = timeit.timeit(
        lambda: match.mul_f64(match_lhs, match_rhs, "loop_reorder"), number=n_iters
    )
    print(f"zig mul (loop_reorder): {match_time/n_iters} seconds per iteration")

    match_time = timeit.timeit(
        lambda: match.mul_f64(match_lhs, match_rhs, "simd"), number=n_iters
    )
    print(f"zig mul (simd): {match_time/n_iters} seconds per iteration")
    match_time = timeit.timeit(
        lambda: match.mul_f64(match_lhs, match_rhs, "simd_reorder"), number=n_iters
    )
    print(f"zig mul (simd_reorder): {match_time/n_iters} seconds per iteration")


if __name__ == "__main__":
    # parse args for whether we are testing sum or mul
    parser = argparse.ArgumentParser()
    parser.add_argument("--sum", action="store_true")
    parser.add_argument("--mul", action="store_true")
    args = parser.parse_args()

    if args.sum:
        print("testing sum")
        test_sum()
        exit(0)
    elif args.mul:
        print("testing mul")
        test_mul()
        exit(0)
    else:
        print("must specify either --sum or --mul")
        exit(1)
