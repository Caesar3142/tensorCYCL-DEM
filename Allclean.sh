#!/bin/bash

#===================================================================#
# Allclean: remove CFD + DEM runtime results for the cyclone separator.
# Keeps inputs: CFD/0, CFD/system, CFD/constant (except polyMesh),
#               DEM/*.liggghts, DEM/dumpsToParaView
#===================================================================#

set -euo pipefail

casePath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$casePath"

echo "Cleaning CFD..."
rm -rf \
    CFD/constant/polyMesh \
    CFD/processor* \
    CFD/postProcessing \
    CFD/couplingFiles \
    CFD/probes \
    CFD/VTK \
    CFD/dynamicCode

# Time directories (keep CFD/0 initial fields)
rm -rf CFD/0.* CFD/[1-9]*

# Foam stubs / logs under CFD (keep CFD/system/controlDict.foam)
rm -f CFD/cycloneSeparator.foam CFD/fluidizedBed.foam CFD/file.foam CFD/log.* CFD/log.liggghts

echo "Cleaning DEM..."
rm -rf DEM/post/dump* \
    DEM/post/restart/liggghts.restart* \
    DEM/post/particles_* \
    DEM/post/particles.pvd \
    DEM/post/particles.series \
    DEM/post/frame_* \
    DEM/post/init_frame_* \
    DEM/post/forces.txt \
    DEM/post/*.vtk \
    DEM/post/*.vtu \
    DEM/post/*.vtp \
    DEM/post/*.pvd \
    DEM/post/*.csv

rm -f DEM/log.liggghts DEM/screen.log DEM/log.*

echo "Cleaning case logs..."
rm -f log_* log.liggghts screen.log *.log

# Empty dirs / stubs Run/Allrun + ParaView expect
mkdir -p DEM/post/restart CFD/couplingFiles
touch DEM/post/.gitkeep DEM/post/restart/.gitkeep CFD/couplingFiles/.keep
touch CFD/cycloneSeparator.foam

echo "Clean done. Next: ./buildMesh.sh then ./Run.sh (or ./Allrun.sh)."
