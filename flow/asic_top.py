# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: David Schröder 2026

from pydesignflow import Block, task, Result

from .tools import sv2v

from pathlib import Path
import subprocess
import shlex

class AsicTop(Block):
    """
    Top-level ASIC design
    """

    name = "asic_top"

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"

    @task(requires={'srcs':'srcs.srcs_asic'}, hidden=True)
    def gen_verilog(self, cwd, srcs):
        """Convert design sources to single verilog file"""
        r = Result()

        design_srcs = list(map(str, srcs.design_srcs))

        cmdline = [
            "sv2v",
            *design_srcs,
            "-w", str(cwd / "design.v")
        ]
        for k, v in srcs.defines.items():
            cmdline.append(f"--define={k}={v}")

        print("Compiling design:\n\t", shlex.join(cmdline))
        subprocess.check_call(cmdline, cwd=cwd)

        r.design = cwd / "design.v"
        return r
