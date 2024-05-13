from setuptools import setup, Extension

from builder import ZigBuilder

match = Extension("match", sources=["match.zig"])

setup(
    name="match",
    version="0.0.1",
    ext_modules=[match],
    description="A simple example of using Zig with Python",
    cmdclass={"build_ext": ZigBuilder},
    py_modules=["builder"],
)
