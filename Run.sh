#!/bin/bash

#===================================================================#
# Run: cyclone-separator CFD-DEM (CFDEM + LIGGGHTS)
#
# Requires an existing mesh from ./buildMesh.sh.
# For mesh + run + post-process, use ./Allrun.sh.
#===================================================================#

set -euo pipefail

casePath="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: '$1' not found."
        echo "This case needs OpenFOAM + CFDEMcoupling."
        echo "Exit this container and start:"
        echo "  docker run -it --rm --platform linux/amd64 \\"
        echo "    -v ~/Documents_Local/GitHub/LIGGGHTS_projects:/simulation \\"
        echo "    cfdem:local"
        echo "Build once with: docker build --platform linux/amd64 -f Dockerfile.cfdem -t cfdem:local ."
        exit 1
    fi
}

require_cmd cfdemSolverPiso
require_cmd parCFDDEMrun

if [ -z "${CFDEM_LIGGGHTS_EXEC:-}" ] || [ ! -x "${CFDEM_LIGGGHTS_EXEC}" ]; then
    echo "ERROR: CFDEM_LIGGGHTS_EXEC is not set or not executable."
    echo "Use the cfdem:local image (Dockerfile.cfdem), not liggghts:local."
    exit 1
fi

boundaryFile="$casePath/CFD/constant/polyMesh/boundary"
if [ ! -f "$boundaryFile" ] ||
   ! grep -q "body" "$boundaryFile" ||
   ! grep -q "inlet" "$boundaryFile" ||
   ! grep -q "outlet" "$boundaryFile"; then
    echo "ERROR: cyclone mesh not found or incomplete."
    echo "Run ./buildMesh.sh first (or ./Allrun.sh)."
    exit 1
fi

if [ ! -f "$casePath/DEM/body.stl" ]; then
    echo "ERROR: DEM/body.stl missing. Run ./buildMesh.sh first."
    exit 1
fi

mkdir -p "$casePath/DEM/post/restart" "$casePath/CFD/couplingFiles"
# parCFDDEMrun does: rm couplingFiles/*
touch "$casePath/CFD/couplingFiles/.keep"

# The cyclone starts empty. LIGGGHTS creates particles periodically at the
# inlet during the coupled run, so no packed-bed restart is required.
"$casePath/parCFDDEMrun.sh"
