import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from vcdvcd import VCDVCD


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
SIM_DATA_DIR = PROJECT_ROOT / "Docs" / "Sim_Data"
MAX_EVENTS = 500


def safe_stem(name):
    stem = Path(name).stem if name else "waveform"
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", stem)


def output_paths(top):
    stem = safe_stem(top)
    return {
        "md": SIM_DATA_DIR / f"ports_{stem}.md",
        "xml": SIM_DATA_DIR / f"parsed_waveform_{stem}.xml",
    }


def default_vcd_path(top):
    return PROJECT_ROOT / "Waveform" / f"dump_{safe_stem(top)}.vcd"


def resolve_path(path_arg, default_path):
    if not path_arg:
        return default_path

    path = Path(path_arg)
    if path.is_absolute():
        return path

    return PROJECT_ROOT / path


def read_signals(vcd):
    if hasattr(vcd, "get_signals"):
        signals = vcd.get_signals()
    else:
        signals = list(vcd.references.keys())

    return sorted(signals)


def generate_md_from_vcd(top, vcd_path):
    paths = output_paths(top)
    md_path = paths["md"]

    if not vcd_path.exists():
        print(f"ERROR: VCD file not found: {vcd_path}")
        return 1

    SIM_DATA_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Reading VCD: {vcd_path}")
    vcd = VCDVCD(str(vcd_path))
    all_vcd_paths = read_signals(vcd)

    with md_path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(f"# AI Debugging Signal Checklist: {safe_stem(top)}\n\n")
        f.write("## Time Scope (Optional)\n")
        f.write("> Enter simulation time values using the VCD timescale unit.\n")
        f.write("> Leave blank or write None to skip a bound.\n")
        f.write("- Start Time: \n")
        f.write("- End Time: \n\n")

        f.write("## Signals\n")
        f.write("> Change `[ ]` to `[x]` for signals you want to export.\n\n")
        for path in all_vcd_paths:
            f.write(f"- [ ] {path}\n")

    print(f"Generated signal checklist: {md_path}")
    print(f"Signals found: {len(all_vcd_paths)}")
    return 0


def read_selection(md_path):
    checked_paths = []
    start_time = None
    end_time = None

    with md_path.open("r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()

            if line.startswith("- Start Time:"):
                val = line.split(":", 1)[1].strip()
                if val and val.lower() != "none":
                    start_time = int(val)
            elif line.startswith("- End Time:"):
                val = line.split(":", 1)[1].strip()
                if val and val.lower() != "none":
                    end_time = int(val)
            elif line.startswith("- [x]") or line.startswith("- [X]"):
                parts = line.split("] ", 1)
                if len(parts) == 2:
                    checked_paths.append(parts[1].strip())

    return checked_paths, start_time, end_time


def parse_vcd(top, vcd_path):
    paths = output_paths(top)
    md_path = paths["md"]
    xml_path = paths["xml"]

    if not md_path.exists():
        print(f"ERROR: Signal checklist not found: {md_path}")
        print("Run --gen first, then select signals in the generated markdown file.")
        return 1

    if not vcd_path.exists():
        print(f"ERROR: VCD file not found: {vcd_path}")
        return 1

    checked_paths, start_time, end_time = read_selection(md_path)
    if not checked_paths:
        print(f"ERROR: No checked signals in: {md_path}")
        return 1

    print(f"Reading VCD: {vcd_path}")
    print(f"Reading signal checklist: {md_path}")
    print(f"Selected signals: {len(checked_paths)}")
    if start_time is not None or end_time is not None:
        print(f"Time filter: {start_time} ~ {end_time}")

    vcd = VCDVCD(str(vcd_path))
    root = ET.Element("SimulationData", top=safe_stem(top), vcd=str(vcd_path))

    for path in checked_paths:
        try:
            tv_list = vcd[path].tv
        except KeyError:
            print(f"WARNING: Signal not found in VCD: {path}")
            continue

        sig_name = path.split(".")[-1]
        sig_elem = ET.SubElement(root, "Signal", name=sig_name, path=path)

        filtered_tv = []
        for time, value in tv_list:
            if start_time is not None and time < start_time:
                continue
            if end_time is not None and time > end_time:
                break
            filtered_tv.append((time, value))

        if len(filtered_tv) > MAX_EVENTS:
            print(
                f"WARNING: {sig_name} has {len(filtered_tv)} events. "
                f"Exporting first {MAX_EVENTS} only."
            )
            filtered_tv = filtered_tv[:MAX_EVENTS]

        for time, value in filtered_tv:
            change_elem = ET.SubElement(sig_elem, "Change", time=str(time))
            change_elem.text = str(value)

        print(f"Exported: {path}")

    SIM_DATA_DIR.mkdir(parents=True, exist_ok=True)
    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    tree.write(xml_path, encoding="utf-8", xml_declaration=True)

    print(f"Generated XML: {xml_path}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="VCD parser for AI-assisted HDL debugging")
    parser.add_argument("--gen", action="store_true", help="generate a signal checklist markdown file")
    parser.add_argument("--parse", action="store_true", help="export checked signals to XML")
    parser.add_argument("--top", default="waveform", help="top/testbench name used for output filenames")
    parser.add_argument(
        "--vcd",
        default=None,
        help="VCD path. Relative paths are resolved from the project root. Default: Waveform/dump_<top>.vcd",
    )
    args = parser.parse_args()

    vcd_path = resolve_path(args.vcd, default_vcd_path(args.top))

    if args.gen == args.parse:
        parser.print_help()
        return 1

    if args.gen:
        return generate_md_from_vcd(args.top, vcd_path)

    return parse_vcd(args.top, vcd_path)


if __name__ == "__main__":
    sys.exit(main())
