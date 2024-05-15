import match as _match


def uniform(shape, dtype=None):
    if dtype is None:
        dtype = "f64"
    match dtype:
        case "f64":
            return _match.uniform_f64(shape)
        case "f32":
            return _match.uniform_f32(shape)
        case _:
            raise ValueError(f"dtype {dtype} not supported")
