import match
import random
import timeit
import numpy as np
import torch as t


if __name__ == "__main__":
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

    # benchmark 10000 runs of match.sum
    match_time = timeit.timeit(lambda: match_tensor.sum_non_simd(), number=100_000)
    print(f"zig sum: {match_time}")

    match_time = timeit.timeit(lambda: match_tensor.sum(), number=100_000)
    print(f"zig simd sum: {match_time}")

    # benchmark 10000 runs of numpy.sum
    numpy_time = timeit.timeit(lambda: numpy_ndarray.sum(), number=100_000)
    print(f"numpy sum: {numpy_time}")

    # benchmark 10000 runs of torch.sum
    torch_time = timeit.timeit(lambda: torch_tensor.sum(), number=100_000)
    print(f"torch sum: {torch_time}")
