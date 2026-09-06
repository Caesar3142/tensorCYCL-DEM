#!/usr/bin/env python3
import sys
dump, data = sys.argv[1], sys.argv[2]
lines = open(dump).read().splitlines()
i = 0
atoms = []
cols = None
while i < len(lines):
    line = lines[i].strip()
    if line.startswith("ITEM: ATOMS"):
        cols = line.split()[2:]
        i += 1
        while i < len(lines) and not lines[i].startswith("ITEM:"):
            parts = lines[i].split()
            if parts:
                atoms.append(dict(zip(cols, parts)))
            i += 1
        continue
    i += 1
density = 2650.0
with open(data, "w") as f:
    f.write("LIGGGHTS data file\n\n")
    f.write("%d atoms\n1 atom types\n\n" % len(atoms))
    f.write("-0.18 0.18 xlo xhi\n-0.18 0.18 ylo yhi\n-0.62 0.19 zlo zhi\n\n")
    f.write("Atoms\n\n")
    for a in atoms:
        f.write("%s %s %s %s %s %s %s\n" % (
            a["id"], a["type"],
            2.0 * float(a["radius"]), density,
            a["x"], a["y"], a["z"]))
    f.write("\nVelocities\n\n")
    for a in atoms:
        f.write("%s %s %s %s 0 0 0\n" % (a["id"], a["vx"], a["vy"], a["vz"]))
print(len(atoms))
