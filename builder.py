import os
from setuptools.command.build_ext import build_ext


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        assert len(ext.sources) == 1

        if not os.path.exists(self.build_lib):
            os.makedirs(self.build_lib)

        self.spawn(
            [
                "zig",
                "build-lib",
                "-target",
                "aarch64-macos",  # build for macos
                "-O",
                "ReleaseFast",  # set optimization level
                "-lc",  # link with C standard library
                # where to output machine code
                f"-femit-bin={self.get_ext_fullpath(ext.name)}",
                "-fallow-shlib-undefined",  # allow undefined symbols in shared libs
                "-dynamic",  # force output to be dynamically linked TODO: what does this mean
                *[f"-I{d}" for d in self.include_dirs],  # directories to build
                ext.sources[0],  # the Zig source file
            ]
        )
