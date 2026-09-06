#!/bin/bash

#===================================================================#
# Coupled CFD-DEM run for the cyclone separator (cfdemSolverPiso)
#===================================================================#

set -euo pipefail

if ! command -v cfdemSolverPiso >/dev/null 2>&1; then
    echo "ERROR: cfdemSolverPiso not found. Use image cfdem:local (see Dockerfile.cfdem)."
    exit 1
fi

casePath="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
logpath=$casePath
headerText="run_parallel_cfdemSolverPiso_cycloneSeparator_CFDDEM"
logfileName="log_$headerText"
solverName="cfdemSolverPiso"
# Must match DEM/in.liggghts_run "processors" product (default 2*2*2=8)
nrProcs="${NR_PROCS:-8}"
machineFileName="none"
debugMode="off"
postproc="false"

mkdir -p "$casePath/CFD/couplingFiles"
touch "$casePath/CFD/couplingFiles/.keep"

# Parallel CFD-DEM (helper runs decomposePar + mpirun)
parCFDDEMrun "$logpath" "$logfileName" "$casePath" "$headerText" "$solverName" "$nrProcs" "$machineFileName" "$debugMode"

if [ -f "$casePath/$logfileName" ] &&
   grep -Eq "FOAM FATAL|ERROR on proc|MPI_ABORT" "$casePath/$logfileName"; then
    echo "ERROR: coupled solver failed; see $casePath/$logfileName"
    exit 1
fi

if [ "$postproc" == "true" ]; then
    cd "$casePath/DEM/post"
    python -i "$CFDEM_LPP_DIR/lpp.py" dump*.liggghts_run

    cd "$casePath/CFD"
    foamToVTK
fi
