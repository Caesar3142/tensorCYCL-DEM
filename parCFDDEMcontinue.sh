#!/bin/bash

#===================================================================#
# Continue the cyclone CFD-DEM run from the last *synced* write time
# (parallel, without re-decomposing processor* directories).
#
# CFD and DEM must resume from the SAME physical time. If CFD has
# advanced further than DEM dumps/restarts (e.g. after a bad continue),
# this script resumes from the latest time where BOTH exist.
#
# Usage (inside cfdem:local):
#   cd /simulation/cyclone-separator
#   ./parCFDDEMcontinue.sh              # resume to controlDict endTime
#   END_TIME=2.0 ./parCFDDEMcontinue.sh # optional new end time
#===================================================================#

set -euo pipefail

if ! command -v cfdemSolverPiso >/dev/null 2>&1; then
    echo "ERROR: cfdemSolverPiso not found. Use image cfdem:local (see Dockerfile.cfdem)."
    exit 1
fi

casePath="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cfdPath="$casePath/CFD"
demPath="$casePath/DEM"
restartDir="$demPath/post/restart"
nrProcs="${NR_PROCS:-8}"
demDt=0.0000005
writeInterval=0.005
feedTotal=10000

controlDict="$cfdPath/system/controlDict"
couplingProps="$cfdPath/constant/couplingProperties"
continueInput="$demPath/in.liggghts_continue"
continueInputRun="$demPath/in.liggghts_continue.active"
continueRestart="$restartDir/liggghts.continue"

mkdir -p "$restartDir" "$cfdPath/couplingFiles"
touch "$cfdPath/couplingFiles/.keep"

if ! compgen -G "$cfdPath/processor*" >/dev/null; then
    echo "ERROR: no CFD/processor* directories found. Start with ./Run.sh first."
    exit 1
fi

# Resolve a common resume time where CFD + DEM both have data.
syncInfo="$(
python3 - <<'PY' "$cfdPath" "$demPath" "$restartDir" "$nrProcs" "$demDt" "$writeInterval"
import os, sys, re
cfd, dem, rdir, nprocs, dt, wint = sys.argv[1:7]
nprocs = int(nprocs); dt = float(dt); wint = float(wint)

pat = re.compile(r"^[0-9]+(\.[0-9]+)?$")
counts = {}
for p in range(nprocs):
    d = os.path.join(cfd, f"processor{p}")
    if not os.path.isdir(d):
        sys.exit(f"missing {d}")
    for name in os.listdir(d):
        if pat.match(name):
            t = float(name)
            counts[t] = counts.get(t, 0) + 1
cfd_times = sorted(t for t, c in counts.items() if c == nprocs and t > 0)
if not cfd_times:
    sys.exit("no common CFD written times on all processors")

dump_steps = []
post = os.path.join(dem, "post")
for name in os.listdir(post):
    m = re.match(r"dump(\d+)\.liggghts_run$", name)
    if m:
        dump_steps.append(int(m.group(1)))
dump_steps.sort()

restart_steps = []
if os.path.isdir(rdir):
    for name in os.listdir(rdir):
        m = re.match(r"liggghts\.restart\.(\d+)$", name)
        if m:
            restart_steps.append(int(m.group(1)))
restart_steps.sort()

def near_write(t):
    # Snap to write interval grid used by this case.
    return round(round(t / wint) * wint, 9)

# Candidate sync times: CFD times that also have a DEM dump or restart.
tol = 0.5 * wint
sync_candidates = []
for t in cfd_times:
    step = int(round(t / dt))
    has_dump = step in dump_steps
    has_restart = step in restart_steps
    # Also accept nearest dump within half write interval.
    if not has_dump and dump_steps:
        nearest = min(dump_steps, key=lambda s: abs(s - step))
        if abs(nearest * dt - t) <= tol:
            step = nearest
            has_dump = True
    if not has_restart and restart_steps:
        nearest = min(restart_steps, key=lambda s: abs(s - step))
        if abs(nearest * dt - t) <= tol:
            step = nearest
            has_restart = True
    if has_dump or has_restart:
        sync_candidates.append((t, step, has_dump, has_restart))

if not sync_candidates:
    sys.exit(
        "no overlapping CFD/DEM write times.\n"
        f"  CFD max={cfd_times[-1]}\n"
        f"  DEM dump max={dump_steps[-1]*dt if dump_steps else None}\n"
        f"  DEM restart max={restart_steps[-1]*dt if restart_steps else None}"
    )

# Resume from the latest overlapping time (keeps CFD and DEM clocks aligned).
t_sync, step_sync, has_dump, has_restart = sync_candidates[-1]
t_cfd = cfd_times[-1]
dem_times = []
if dump_steps:
    dem_times.append(dump_steps[-1] * dt)
if restart_steps:
    dem_times.append(restart_steps[-1] * dt)
t_dem = max(dem_times) if dem_times else 0.0

print(f"{t_cfd} {t_dem} {t_sync} {step_sync} {int(has_dump)} {int(has_restart)}")
PY
)"

read -r latestCfd latestDem syncTime demStep hasDump hasRestart <<< "$syncInfo"

echo "Latest CFD time:     $latestCfd"
echo "Latest DEM data:     $latestDem"
echo "Synced resume time:  $syncTime  (DEM step $demStep)"

if python3 - <<PY
import sys
cfd, dem, sync = float("$latestCfd"), float("$latestDem"), float("$syncTime")
sys.exit(0 if abs(cfd - sync) < 1e-12 else 1)
PY
then
    echo "CFD and DEM are aligned."
else
    echo "WARNING: CFD is ahead of DEM dumps/restarts."
    echo "         Resuming from t=$syncTime so particle and fluid clocks match."
    echo "         CFD folders after t=$syncTime will be overwritten as the run advances."
fi

dumpFile="$demPath/post/dump${demStep}.liggghts_run"
exactRestart="$restartDir/liggghts.restart.${demStep}"

build_restart_from_dump() {
    local dump="$1"
    local outRestart="$2"
    local tmpDir dataFile makeInput nAtoms remain

    if [ ! -f "$dump" ]; then
        echo "ERROR: no DEM dump at $dump and no binary restart for step $demStep."
        exit 1
    fi

    echo "Building DEM restart from $dump"
    tmpDir="$(mktemp -d "$demPath/post/tmp_continue.XXXXXX")"
    dataFile="$tmpDir/particles.data"
    makeInput="$tmpDir/make_restart.liggghts"

    nAtoms="$(python3 "$demPath/dump_to_data.py" "$dump" "$dataFile")"
    remain=$(( feedTotal - nAtoms ))
    if [ "$remain" -lt 0 ]; then remain=0; fi

    cat > "$makeInput" <<EOF
echo            both
log             $tmpDir/log.make_restart
atom_style      granular
atom_modify     map array
atom_modify     sort 0 0.0
communicate     single vel yes
boundary        f f f
newton          off
units           si
read_data       $dataFile
neighbor        0.003 bin
neigh_modify    delay 0
fix         m1 all property/global youngsModulus peratomtype 5.e7
fix         m2 all property/global poissonsRatio peratomtype 0.25
fix         m3 all property/global coefficientRestitution peratomtypepair 1 0.20
fix         m4 all property/global coefficientFriction peratomtypepair 1 0.02
pair_style  gran model hertz tangential no_history
pair_coeff  * *
timestep    $demDt
reset_timestep $demStep
write_restart   $outRestart
EOF

    if [ -z "${CFDEM_LIGGGHTS_EXEC:-}" ] || [ ! -x "${CFDEM_LIGGGHTS_EXEC}" ]; then
        echo "ERROR: CFDEM_LIGGGHTS_EXEC is not set/executable; cannot build restart from dump."
        exit 1
    fi

    "${CFDEM_LIGGGHTS_EXEC}" -in "$makeInput"
    rm -rf "$tmpDir"
    echo "Built DEM restart with $nAtoms atoms; remaining insert budget = $remain"
}

# After read_restart, insert/rate/region must have start >= current DEM step
# or LIGGGHTS aborts with: "'start' step can not be before current step".
patch_continue_inject() {
    local remain="$1"
    python3 - <<'PY' "$continueInputRun" "$remain" "$demStep"
import re, sys
path, remain, step = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()
text = re.sub(r"(nparticles\s+)\d+", r"\g<1>" + remain, text, count=1)

def patch_inject(m):
    line = m.group(0)
    line = re.sub(r"\s+start\s+\d+", "", line)
    # Place start just before "region feed" (required keyword order).
    if re.search(r"\sregion\s+feed\b", line):
        line = re.sub(r"(\sregion\s+feed\b)", f" start {step}\\1", line, count=1)
    else:
        line = line.rstrip() + f" start {step}"
    return line

text2, n = re.subn(
    r"(?m)^fix\s+inject\s+all\s+insert/rate/region\b.*$",
    patch_inject,
    text,
    count=1,
)
if n != 1:
    sys.exit("ERROR: could not patch fix inject in continue input")
open(path, "w", encoding="utf-8").write(text2)
print(f"inject: nparticles={remain}, start={step}")
PY
}

cp -f "$continueInput" "$continueInputRun"
remain="$feedTotal"

if [ -f "$exactRestart" ]; then
    echo "Using DEM restart: $exactRestart"
    cp -f "$exactRestart" "$continueRestart"
    if [ -f "$dumpFile" ]; then
        nAtoms="$(awk '/ITEM: NUMBER OF ATOMS/{getline; print; exit}' "$dumpFile")"
        remain=$(( feedTotal - nAtoms ))
        if [ "$remain" -lt 0 ]; then remain=0; fi
        echo "Atoms in matching dump: $nAtoms; remaining insert budget = $remain"
    else
        echo "WARNING: no matching dump; keeping nparticles=$remain (may over-insert)."
    fi
elif [ -f "$dumpFile" ]; then
    build_restart_from_dump "$dumpFile" "$continueRestart"
    # remain was computed inside build_restart_from_dump; recompute for patch.
    nAtoms="$(awk '/ITEM: NUMBER OF ATOMS/{getline; print; exit}' "$dumpFile")"
    remain=$(( feedTotal - nAtoms ))
    if [ "$remain" -lt 0 ]; then remain=0; fi
else
    echo "ERROR: need DEM/post/restart/liggghts.restart.${demStep} or $dumpFile"
    exit 1
fi

patch_continue_inject "$remain"

# Backup and retarget OpenFOAM / CFDEM inputs for continue.
controlBak="$controlDict.continuebak"
couplingBak="$couplingProps.continuebak"
cp -f "$controlDict" "$controlBak"
cp -f "$couplingProps" "$couplingBak"

cleanup() {
    if [ -f "$controlBak" ]; then mv -f "$controlBak" "$controlDict"; fi
    if [ -f "$couplingBak" ]; then mv -f "$couplingBak" "$couplingProps"; fi
    rm -f "$continueInputRun"
}
trap cleanup EXIT

python3 - <<'PY' "$controlDict" "$syncTime" "${END_TIME:-}"
import re, sys
path, sync, end = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
# Use explicit startTime (not latestTime) so a desynced newer CFD folder
# cannot pull the fluid ahead of the DEM restart.
text = re.sub(r"(?m)^startFrom\s+\S+;", "startFrom       startTime;", text)
text = re.sub(r"(?m)^startTime\s+\S+;", f"startTime       {sync};", text)
if end:
    text = re.sub(r"(?m)^endTime\s+\S+;", f"endTime         {end};", text)
open(path, "w").write(text)
print(f"controlDict: startFrom startTime={sync}" + (f", endTime {end}" if end else ""))
PY

python3 - <<'PY' "$couplingProps"
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(
    r'liggghtsPath\s+"[^"]+";',
    'liggghtsPath "../DEM/in.liggghts_continue.active";',
    text,
)
open(path, "w").write(text)
print("couplingProperties: liggghtsPath -> in.liggghts_continue.active")
PY

logpath=$casePath
headerText="continue_parallel_cfdemSolverPiso_cycloneSeparator_CFDDEM"
logfileName="log_$headerText"
solverName="cfdemSolverPiso"
machineFileName="none"
debugMode="off"
reconstructCase="false"
decomposeCase="false"

echo "Continuing parallel CFD-DEM from t=$syncTime (NR_PROCS=$nrProcs)..."
parCFDDEMrun "$logpath" "$logfileName" "$casePath" "$headerText" "$solverName" \
    "$nrProcs" "$machineFileName" "$debugMode" "$reconstructCase" "$decomposeCase"

if [ -f "$casePath/$logfileName" ] &&
   grep -Eq "FOAM FATAL|ERROR on proc|MPI_ABORT" "$casePath/$logfileName"; then
    echo "ERROR: continued solver failed; see $casePath/$logfileName"
    exit 1
fi

echo "Continue finished. Log: $casePath/$logfileName"
echo "Re-run ./Allpostprocess.sh and Reload Files in ParaView."
