#!/bin/bash

#===================================================================#
# Optional DEM-only cyclone geometry check
#===================================================================#

set -euo pipefail

if [ -z "${CFDEM_LIGGGHTS_EXEC:-}" ]; then
    echo "ERROR: CFDEM environment not loaded. Use image cfdem:local (see Dockerfile.cfdem)."
    exit 1
fi

echo "starting DEM run in parallel..."

casePath="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
logpath="$casePath"
headerText="run_liggghts_init_DEM"
logfileName="log_$headerText"
solverName="in.liggghts_init"
# Must match DEM/in.liggghts_run "processors" product (default 2*2*2=8)
nrProcs="${NR_PROCS:-8}"
machineFileName="none"
debugMode="off"

mkdir -p "$casePath/DEM/post/restart"
restartFile="$casePath/DEM/post/restart/liggghts.restart"
rm -f "$restartFile"

parDEMrun "$logpath" "$logfileName" "$casePath" "$headerText" "$solverName" "$nrProcs" "$machineFileName" "$debugMode"

# The CFDEM helper can return success even if one MPI rank failed.
if [ ! -s "$restartFile" ]; then
    echo "ERROR: LIGGGHTS did not create $restartFile"
    exit 1
fi

echo "DEM geometry check passed."
