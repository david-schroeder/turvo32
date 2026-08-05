# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 RVLab Contributors

from pydesignflow import Flow

from .fpga_top import FpgaTop
from .system_tb import SystemTb
from .sw import Program, Libsys
from .simlibs_questa import SimlibsQuesta
from .module_tb import ModuleTb
from .sources import Sources

flow = Flow()

# Software
# --------

sw_dirs = [
    "minimal",
    "coremark"
]

flow['libsys'] = Libsys()
for sw_dir in sw_dirs:
    flow[f'sw_{sw_dir}'] = Program(sw_dir, dependency_map={
        'libsys':'libsys'
    })

# Hardware
# --------

flow['simlibs_questa'] = SimlibsQuesta()
flow['srcs'] = Sources(dependency_map={
    'swinit': 'sw_coremark',
})

flow['fpga_top'] = FpgaTop(dependency_map={'srcs':'srcs'})


# Testbenches
# -----------

module_tbs = [
    "turvo32_core_tb"
]

for name in module_tbs:
    flow[name] = ModuleTb(name, dependency_map={
        'srcs':'srcs',
        'simlibs_questa':'simlibs_questa',
    })

flow[f'system_tb'] = SystemTb(dependency_map={
    'srcs':'srcs',
    'simlibs_questa':'simlibs_questa',
    'fpga_top':'fpga_top',
})
