# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: David Schröder 2026

from pydesignflow import Block, task, Result

from .tools import sv2v, gen_librelane_macros, replace_in_file

import os
import json
from pathlib import Path


class AsicTop(Block):
    """
    Top-level ASIC design
    """

    name = "asic_top"

    def setup(self):
        self.src_dir = self.flow.base_dir / "src"
        self.pdk_dir = Path(os.environ["PDK_ROOT"]).resolve()

    @task(requires={'srcs':'srcs.srcs_asic'}, hidden=True)
    def gen_verilog(self, cwd, srcs):
        """Convert design sources to single verilog file"""
        r = Result()

        sv2v.convert_sv2v(
            cwd,
            list(map(str, srcs.design_srcs)),
            str(cwd / "design.v"),
            srcs.defines
        )

        replace_in_file.replace_in_file(cwd / "design.v", {
            ".POWER_PIN_GUARD(),": "`ifdef USE_POWER_PINS\n.VDD(vdd), .VSS(vss), .VDDARRAY(vdd),\n`endif",
            "inout MODPORT_POWER_PINS;": "`ifdef USE_POWER_PINS\n\tinout vdd;\n\tinout vss;\n\t`endif",
            "MODPORT_POWER_PINS,": "`ifdef USE_POWER_PINS\n\tvdd,\n\tvss,\n\t`endif"
        })

        r.design = cwd / "design.v"
        return r

    @task(hidden=True)
    def gen_macros(self, cwd):
        r = Result()

        # Generate SRAM macros
        available = gen_librelane_macros.discover_macros(self.pdk_dir)
        if not available:
            raise FileNotFoundError("Could not find PDK SRAM macros!")

        macro_blackbox_cache: Path = cwd / "blackboxes"
        macro_blackbox_cache.mkdir()

        blackboxes = []

        for macro_name in available.keys():
            vfile = gen_librelane_macros.get_macro_v_path(
                macro_name, self.pdk_dir
            )
            blackbox = macro_blackbox_cache / f"{macro_name}.v"
            gen_librelane_macros.make_blackbox_stub(
                macro_name,
                vfile,
                blackbox
            )
            blackboxes.append(blackbox)
            available[macro_name]["vh"] = [str(blackbox)]

        with open(cwd / "macros.json", "w") as out:
            out.write(json.dumps({"MACROS": available}, indent=4))

        r.macros = cwd / "macros.json"
        r.blackboxes = blackboxes
        return r
