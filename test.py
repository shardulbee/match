import match
import random
import timeit
import numpy as np
import torch as t


if __name__ == "__main__":
    python_floats = [random.uniform(0, 1) for _ in range(10000)]
    match_tensor = match.tensor(python_floats)
    numpy_ndarray = np.array(python_floats)
    torch_tensor = t.tensor(python_floats)

    # benchmark 10000 runs of python-native sum
    native_time = timeit.timeit(
        lambda: sum(python_floats), number=1_000_000
    )  # run one million times
    print(f"python sum: {native_time}")

    # benchmark 10000 runs of match.sum
    match_time = timeit.timeit(lambda: match_tensor.sum(False), number=1_000_000)
    print(f"zig sum: {match_time}")

    match_time = timeit.timeit(lambda: match_tensor.sum(True), number=1_000_000)
    print(f"zig simd sum: {match_time}")

    # benchmark 10000 runs of numpy.sum
    numpy_time = timeit.timeit(lambda: numpy_ndarray.sum(), number=1_000_000)
    print(f"numpy sum: {numpy_time}")

    # benchmark 10000 runs of torch.sum
    torch_time = timeit.timeit(lambda: torch_tensor.sum(), number=1_000_000)
    print(f"torch sum: {torch_time}")
