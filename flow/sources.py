# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors
# Modified by David Schröder 2026

from pydesignflow import Block, task, Result
from .tools import vivado
import subprocess

class Sources(Block):
    """Hardware sources"""

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"

    @task(requires={
        'swinit': 'swinit.build',
        }, always_rebuild=True, hidden=True)
    def srcs_rtl(self, cwd, swinit):
        """Common RTL sources for all design runs"""
        r = Result()

        design_srcs_pkg = []
        for d in ["turvo32", "tilelink"]:
            design_srcs_pkg += [x for x in self.src_dir.glob(f"rtl/{d}/pkg/*.sv")]
        design_srcs = []
        design_srcs += [x for x in self.src_dir.glob("rtl/*/*.sv")]
        design_srcs += [x for x in self.src_dir.glob("rtl/*/*.v")]

        r.design_srcs_pkg = design_srcs_pkg
        r.design_srcs = design_srcs
        r.defines = { 'INIT_MEM_FILE': swinit.mem }
        r.include_dirs = []

        return r

    @task(requires={
        'srcs_rtl': '.srcs_rtl'
    }, always_rebuild=True, hidden=True)
    def srcs_fpga(self, cwd, srcs_rtl):
        """RTL + verification sources for FPGA synthesis"""
        r = Result()

        design_srcs_pkg = srcs_rtl.design_srcs_pkg
        design_srcs_pkg += [x for x in self.src_dir.glob("target/fpga/pkg/*.sv")]

        design_srcs = srcs_rtl.design_srcs
        design_srcs += [x for x in self.src_dir.glob("target/fpga/*.sv")]
        design_srcs += [x for x in self.src_dir.glob("target/fpga/*.v")]

        r.design_srcs = design_srcs_pkg + design_srcs

        r.defines = srcs_rtl.defines
        r.include_dirs = srcs_rtl.include_dirs
        r.tb_srcs = [x for x in self.src_dir.glob("tb/*.sv")]
        r.tb_srcs += [vivado.vivado_dir() / "data/verilog/src/glbl.v"]
        r.xcis = []

        return r

    @task(requires={
            'srcs_rtl': '.srcs_rtl'
        }, always_rebuild=True, hidden=True)
    def srcs_asic(self, cwd, srcs_rtl):
        """RTL + verification sources for ASIC synthesis"""
        r = Result()

        design_srcs_pkg = srcs_rtl.design_srcs_pkg
        design_srcs_pkg += [x for x in self.src_dir.glob("target/asic/pkg/*.sv")]

        design_srcs = srcs_rtl.design_srcs
        design_srcs += [x for x in self.src_dir.glob("target/asic/*.sv")]
        design_srcs += [x for x in self.src_dir.glob("target/asic/*.v")]

        r.design_srcs = design_srcs_pkg + design_srcs
        r.defines = srcs_rtl.defines
        return r

    @task(requires={"srcs":".srcs_fpga"})
    def lint(self, cwd, srcs):
        """Run static code quality assessment"""
        rules = [
            'always-comb',
            'always-comb-blocking',
            'always-ff-non-blocking',
            'case-missing-default',
            'explicit-function-lifetime',
            'explicit-function-task-parameter-type',
            'explicit-parameter-storage-type',
            'explicit-task-lifetime',
            'forbid-consecutive-null-statements',
            'forbid-defparam',
            'forbid-line-continuations',
            'generate-label',
            'module-begin-block',
            'module-filename',
            'module-parameter',
            'module-port',
            'one-module-per-file',
            'package-filename',
            'packed-dimensions-range-ordering',
            #'port-name-suffix',
            'undersized-binary-literal',
            'v2001-generate-begin',
            'void-cast',
        ]
        # Don't lint verilog files
        lint_srcs = [fn for fn in srcs.design_srcs if fn.suffix != '.v']
        try:
            subprocess.check_call(['verible-verilog-lint', '--ruleset', 'none', '--rules', ",".join(rules)]+lint_srcs, cwd=cwd)
        except subprocess.CalledProcessError as e:
            print(f"WARNING: verible-verilog-lint returned {e.returncode} errors.")
        else:
            print("Lint returned no errors.")
