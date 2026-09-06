#!/bin/bash

#===================================================================#
# Allrun: buildMesh + Run + Allpostprocess.
#===================================================================#

set -euo pipefail

casePath="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

"$casePath/buildMesh.sh"
"$casePath/Run.sh"
"$casePath/Allpostprocess.sh"
