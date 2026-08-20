import subprocess
import sys
from pathlib import Path

from . import replace_in_file

# Relative to $PDK_ROOT
SRAM_LIB_SUBPATH = Path("libs.ref/sg13g2_sram")


def make_blackbox_stub(macro_name: str, src_v: Path, out_v: Path) -> bool:
    """Run the real macro model through yosys 'blackbox' to strip its body
    (including internal instantiations of shared behavioral cores like
    RM_IHPSG13_1P_core_behavioral_bm_bist that have no matching lef/gds and
    aren't meant to be treated as standalone macros) down to a pure
    port-list header. Returns True on success."""
    script = (
        f"read_verilog {src_v}; "
        f"blackbox {macro_name}; "
        f"write_verilog -noattr -blackboxes {out_v}"
    )
    result = subprocess.run(
        ["yosys", "-D", "FUNCTIONAL", "-p", script],
        capture_output=True,
        text=True,
    )
    replace_in_file.replace_regex(
        out_v,
        {
            r"(module [A-za-z0-9_]+\()(([^;]*\n)*.*;)": r"\g<1>\n`ifdef USE_POWER_PINS\nVDD, VSS, VDDARRAY,\n`endif\n\g<2>\n`ifdef USE_POWER_PINS\ninout VDD;\nwire VDD;\ninout VSS;\nwire VSS;\ninout VDDARRAY;\nwire VDDARRAY;\n`endif"
        }
    )
    if result.returncode != 0 or not out_v.is_file():
        print(
            f"WARNING: failed to generate blackbox stub for {macro_name}:\n"
            f"{result.stderr}",
            file=sys.stderr,
        )
        return False
    return True


def get_macro_v_path(macro_name, pdk_root: Path) -> Path:
    base = pdk_root / SRAM_LIB_SUBPATH
    return base / "verilog" / f"{macro_name}.v"

def build_macro_entry(macro_name: str, pdk_root: Path) -> dict:
    """Build a base macro entry for `macro_name`. Should be extended
    by a `vh` field pointing to a blackbox / declaration header"""
    base = pdk_root / SRAM_LIB_SUBPATH

    lef_file = base / "lef" / f"{macro_name}.lef"
    gds_file = base / "gds" / f"{macro_name}.gds"

    missing = [str(p) for p in (lef_file, gds_file) if not p.is_file()]
    if missing:
        print(
            f"WARNING: {macro_name} is instantiated but missing required "
            f"view(s): {', '.join(missing)} -- skipping this macro.",
            file=sys.stderr,
        )
        return None

    entry = {
        "instances": {},
        "gds": [str(gds_file)],
        "lef": [str(lef_file)],
    }

    lib_dir = base / "lib"
    lib_matches = sorted(lib_dir.glob(f"{macro_name}*.lib")) if lib_dir.is_dir() else []
    if lib_matches:
        lib_dict = {}
        for lf in lib_matches:
            corner_tag = lf.stem[len(macro_name):].strip("_")
            key = f"*{corner_tag}*" if corner_tag else "*"
            lib_dict.setdefault(key, []).append(str(lf))
        entry["lib"] = lib_dict
    else:
        print(
            f"NOTE: no .lib files found for {macro_name} in {lib_dir} -- "
            f"STA for this macro will need a fallback (nl.v/spef or "
            f"black-boxed).",
            file=sys.stderr,
        )
        entry["lib"] = {}

    entry["spice"] = []
    entry["sdf"] = {}

    return entry


def discover_macros(pdk_root: Path) -> dict:
    """Map macro name -> entry, derived from the PDK's sram LEF dir
    (every physically real macro has a LEF; behavioral-only helper
    models like RM_IHPSG13_1P_core_behavioral_bm_bist do not)."""
    macros = {}
    lef_dir = pdk_root / SRAM_LIB_SUBPATH / "lef"
    if not lef_dir.is_dir():
        print(f"WARNING: {lef_dir} does not exist; check $PDK_ROOT", file=sys.stderr)
        return macros
    for lef_file in lef_dir.glob("*.lef"):
        entry = build_macro_entry(lef_file.stem, pdk_root)
        if entry:
            macros[lef_file.stem] = entry
    return macros
