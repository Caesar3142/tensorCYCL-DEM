#!/bin/bash

# Reconstruct CFD fields, then convert ALL DEM dumps for ParaView.
# Re-run this after ./parCFDDEMcontinue.sh so ParaView sees new times.
#
# Speed knobs (env):
#   RECONSTRUCT_JOBS=8          parallel reconstructPar workers (default 8)
#   RECONSTRUCT_FIELDS='(U p …)'  only these fields (default: ParaView essentials)
#   RECONSTRUCT_FIELDS=all      every field (slower)
#   RECONSTRUCT_TIME='5:'       OpenFOAM -time range (default: all result times)
#   SKIP_CFD_RECONSTRUCT=1      DEM dumps only

set -euo pipefail

casePath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfdPath="$casePath/CFD"
demPath="$casePath/DEM"

if ! command -v reconstructPar >/dev/null 2>&1; then
    echo "ERROR: reconstructPar not found. Run this inside the cfdem:local container."
    exit 1
fi

if ! compgen -G "$cfdPath/processor*" >/dev/null; then
    echo "ERROR: no CFD/processor* directories found. Run the coupled case first."
    exit 1
fi

if ! compgen -G "$demPath/post/dump*.liggghts_run" >/dev/null; then
    echo "ERROR: no DEM/post/dump*.liggghts_run files found."
    exit 1
fi

latestProc="$(ls -1 "$cfdPath/processor0" | awk '/^[0-9]/ && $0 != "0" {print}' | sort -n | tail -1)"
latestDumpStep="$(ls -1 "$demPath/post"/dump*.liggghts_run | sed 's|.*/dump||;s|\.liggghts_run||' | sort -n | tail -1)"
latestDumpTime="$(python3 - <<PY
print(round(int("$latestDumpStep") * 5e-7, 6))
PY
)"

echo "Latest CFD processor time: ${latestProc:-none}"
echo "Latest DEM dump: step $latestDumpStep -> t=${latestDumpTime} s"

if python3 - <<PY
import sys
cfd = float("${latestProc:-0}")
dem = float("${latestDumpTime:-0}")
sys.exit(0 if abs(cfd - dem) <= 0.005 + 1e-12 else 1)
PY
then
    :
else
    echo "WARNING: CFD time (${latestProc}) and DEM dump time (${latestDumpTime}) differ."
    echo "         particles.pvd follows DEM dumps. A previous continue likely"
    echo "         resumed CFD ahead of DEM. Fix by continuing from the synced time:"
    echo "           ./parCFDDEMcontinue.sh"
fi

if [ "${SKIP_CFD_RECONSTRUCT:-0}" != "1" ]; then
    echo "Reconstructing CFD fields..."
    (
        cd "$cfdPath"
        # CFDEM particleCloud data is incompatible with plain reconstructPar.
        # OpenFOAM-5 reconstructPar is serial; speed it up by splitting times
        # across several independent reconstructPar processes, and by skipping
        # non-essential fields (full list: RECONSTRUCT_FIELDS=all).
        nJobs="${RECONSTRUCT_JOBS:-${NR_PROCS:-8}}"
        fieldsOpt=()
        fieldsSpec="${RECONSTRUCT_FIELDS:-(U p voidfraction Us Ksl rho nut k epsilon)}"
        if [ "$fieldsSpec" != "all" ]; then
            fieldsOpt=(-fields "$fieldsSpec")
            echo "  fields: $fieldsSpec"
        else
            echo "  fields: all"
        fi

        mapfile -t times < <(
            ls -1 processor0 |
            awk '/^[0-9]+([.][0-9]+)?$/ && $0 != "0" {print}' |
            sort -n
        )
        if [ -n "${RECONSTRUCT_TIME:-}" ]; then
            # Filter to times that fall in the OpenFOAM -time selection.
            # Supports "a:b", "a:", ":b", or a single value.
            mapfile -t times < <(
                printf '%s\n' "${times[@]}" | RECONSTRUCT_TIME="$RECONSTRUCT_TIME" python3 -c '
import os, sys
sel = os.environ["RECONSTRUCT_TIME"].strip()
times = [ln.strip() for ln in sys.stdin if ln.strip()]
lo = hi = None
if ":" in sel:
    a, b = sel.split(":", 1)
    lo = float(a) if a else None
    hi = float(b) if b else None
else:
    lo = hi = float(sel)
for t in times:
    v = float(t)
    if lo is not None and v < lo - 1e-12:
        continue
    if hi is not None and v > hi + 1e-12:
        continue
    print(t)
'
            )
            echo "  time filter RECONSTRUCT_TIME=${RECONSTRUCT_TIME} -> ${#times[@]} times"
        fi

        nTimes="${#times[@]}"
        if [ "$nTimes" -eq 0 ]; then
            echo "ERROR: no result times found under processor0/ (after filters)."
            exit 1
        fi
        if [ "$nJobs" -gt "$nTimes" ]; then
            nJobs="$nTimes"
        fi
        echo "  $nTimes times -> $nJobs parallel reconstructPar jobs (-noLagrangian -newTimes)"

        pids=()
        fails=0
        for ((i = 0; i < nJobs; i++)); do
            start=$((i * nTimes / nJobs))
            end=$(((i + 1) * nTimes / nJobs))
            if [ "$start" -ge "$end" ]; then
                continue
            fi
            t0="${times[$start]}"
            t1="${times[$((end - 1))]}"
            log="../log_reconstructPar_${i}"
            (
                echo "  job $i: times ${t0}:${t1} (${start}..$((end - 1)))"
                reconstructPar -noLagrangian -newTimes "${fieldsOpt[@]}" \
                    -time "${t0}:${t1}" >"$log" 2>&1
            ) &
            pids+=("$!")
        done

        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                fails=$((fails + 1))
            fi
        done
        if [ "$fails" -ne 0 ]; then
            echo "ERROR: $fails reconstructPar job(s) failed; see log_reconstructPar_*"
            exit 1
        fi
        touch cycloneSeparator.foam
    )
else
    echo "Skipping CFD reconstruct (SKIP_CFD_RECONSTRUCT=1)."
fi

echo "Converting DEM dumps for ParaView (rewrites particles.pvd)..."
# step0=0 so physical time = DEM_step * dt matches CFD absolute time
# after cold start and after ./parCFDDEMcontinue.sh.
"$demPath/dumpsToParaView" --step0 0 --dt 5e-7 "$@"

echo "Post-processing complete:"
echo "  CFD: $cfdPath/cycloneSeparator.foam"
echo "  DEM: $demPath/post/particles.pvd"
echo ""
echo "In ParaView: File -> Reload Files (or close/reopen both sources)"
echo "so the time slider picks up times after a continue."
