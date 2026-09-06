#!/usr/bin/env python3
"""Drop ASCII STL facets whose starting 'facet' line numbers are listed
in a LIGGGHTS element_exclusion_list file (1-based line numbers)."""
import sys
from pathlib import Path


def load_facets(text_lines):
    """Return (header_line, list of facet blocks, footer_line)."""
    if not text_lines:
        raise SystemExit("empty STL")
    header = text_lines[0]
    footer = text_lines[-1] if text_lines[-1].strip().startswith("endsolid") else "endsolid body"
    facets = []
    i = 1
    while i < len(text_lines):
        line = text_lines[i]
        if line.strip().startswith("endsolid"):
            break
        if line.lstrip().startswith("facet"):
            start = i
            # 1-based line number of this facet line in the current file
            line_no = i + 1
            i += 1
            while i < len(text_lines) and not text_lines[i].lstrip().startswith("endfacet"):
                i += 1
            if i < len(text_lines):
                i += 1  # include endfacet
            facets.append((line_no, text_lines[start:i]))
            continue
        i += 1
    return header, facets, footer


def main():
    if len(sys.argv) != 3:
        print("usage: clean_body_mesh.py body.stl body.exclude", file=sys.stderr)
        return 2
    stl = Path(sys.argv[1])
    excl_path = Path(sys.argv[2])
    drop = {int(x) for x in excl_path.read_text().split() if x.strip()}
    if not drop:
        print("no exclusions; STL unchanged")
        return 0

    lines = stl.read_text().splitlines()
    header, facets, footer = load_facets(lines)
    kept = [block for line_no, block in facets if line_no not in drop]
    dropped = len(facets) - len(kept)
    missing = sorted(drop - {ln for ln, _ in facets})
    out = [header]
    for block in kept:
        out.extend(block)
    out.append(footer)
    stl.write_text("\n".join(out) + "\n")
    print(
        "removed {} facets (kept {}); missing line refs: {}".format(
            dropped, len(kept), missing
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
