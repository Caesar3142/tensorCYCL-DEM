#!/usr/bin/env python3
"""Copy CFD/constant/triSurface/body.stl into DEM/ as ASCII STL.

LIGGGHTS mesh/surface only accepts ASCII STL. Binary STLs confuse vertex
merging and can create hard-angle / >5-neighbor failures. Bad triangles are
handled separately via mesh cleaning in buildMesh.sh.
"""
import struct
import sys
from pathlib import Path

case = Path(__file__).resolve().parent.parent
src = case / "CFD/constant/triSurface/body.stl"
dst = case / "DEM/body.stl"


def main():
    raw = src.read_bytes()
    if raw.lstrip()[:5].lower() == b"solid" and b"vertex" in raw[:5000].lower():
        dst.write_bytes(raw)
        print("copied ASCII {} -> {}".format(src, dst))
        return 0

    ntri = struct.unpack_from("<I", raw, 80)[0]
    lines = ["solid body"]
    off = 84
    for _ in range(ntri):
        vals = struct.unpack_from("<12fH", raw, off)
        nx, ny, nz = vals[0:3]
        lines.append(" facet normal {} {} {}".format(nx, ny, nz))
        lines.append("  outer loop")
        for k in range(3, 12, 3):
            lines.append("   vertex {} {} {}".format(*vals[k : k + 3]))
        lines.append("  endloop")
        lines.append(" endfacet")
        off += 50
    lines.append("endsolid body")
    dst.write_text("\n".join(lines) + "\n")
    print("converted binary->ASCII ({} tris): {} -> {}".format(ntri, src, dst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
