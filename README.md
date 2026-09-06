# Cyclone separator CFD–DEM

CFDEM case for dilute dust/fine-sand separation in a cyclone. Air enters
tangentially through `inlet.stl` in the **-x direction** and leaves through
`outlet.stl` in the **+z direction**. Polydisperse quartz particles are
injected periodically at the air-inlet velocity.

## Model

| Item | Setting |
|---|---|
| Coupling | `cfdemSolverPiso` + LIGGGHTS, two-way MPI |
| Cyclone geometry | `body.stl`, x/y ±0.160 m, z −0.600 to 0.172 m |
| Background / DEM box | x/y ±0.18 m, z −0.62 to 0.19 m |
| Inlet | 5.0 m/s in −x |
| Outlet | Pressure outlet in +z |
| Fluid | Air: ρ = 1.2 kg/m³, ν = 1.5e-5 m²/s |
| Turbulence | RAS k-epsilon, 5% inlet intensity |
| Particles | Quartz/sand, ρ = 2650 kg/m³ |
| Diameters | 0.30, 0.60, 1.20 mm (dust / fine / sand) |
| Mass fractions | 0.05 / 0.25 / 0.70 |
| Wall friction / restitution | 0.02 / 0.20 (`tangential no_history`) |
| Young’s modulus | 5e7 Pa (softened computational value) |
| Feed | 500 particles/s for 20 s (batches every 0.05 s), max 10000 |
| DEM injection velocity | (−5.0, 0, 0) m/s |
| CFD time step | 0.0025 s |
| DEM time step | 5e-7 s |
| Coupling period | 0.01 s (= 4 CFD steps; 20000 DEM steps) |
| Save / dump interval | 0.005 s (10000 DEM steps) |
| Simulated time | 20 s |
| MPI | 8 ranks (2 × 2 × 2) |

Young’s modulus is a computational setting, not physical quartz. Higher values
reduce wall overlap but need a smaller DEM timestep. Calibrate particle rate
and size distribution from measured dust loading before treating
collection-efficiency results as predictive.

## Geometry and mesh

1. `blockMesh` builds a ~11 mm background hex mesh `(34 34 74)`.
2. `snappyHexMesh -overwrite` keeps the internal fluid region and refines
   `body`, `inlet`, and `outlet` surfaces (~5–6 mm).
3. `buildMesh.sh` also syncs `CFD/constant/triSurface/body.stl` → ASCII
   `DEM/body.stl` and strips LIGGGHTS-illegal triangles.

`inlet.stl` and `outlet.stl` are CFD boundary caps only. LIGGGHTS uses
`DEM/body.stl` as the particle wall so grains can enter/leave the open ducts.

## Run

Use the `cfdem:local` image:

```bash
docker run -it --rm --platform linux/amd64 \
  -v ~/Documents_Local/GitHub/LIGGGHTS_projects:/simulation \
  cfdem:local
```

Inside the container:

```bash
cd /simulation/cyclone-separator
./Allclean.sh
./Allrun.sh              # buildMesh + Run + Allpostprocess
# or step-by-step:
# ./buildMesh.sh         # CFD mesh + DEM wall STL
# ./Run.sh               # coupled CFD-DEM only
# ./Allpostprocess.sh
```

`buildMesh.sh` builds the cyclone mesh and prepares `DEM/body.stl`.
`Run.sh` launches the coupled simulation (mesh must already exist).
`Allrun.sh` runs mesh, simulation, and post-process in sequence. The cyclone
starts empty; there is no packed-bed initialization.

After changing `body.stl`, remesh with `./Allclean.sh` then `./buildMesh.sh`
(or `./Allrun.sh`). Keep CFD inlet speed and DEM inject velocity equal.

### Continue from the last written time

If the run stops (walltime, crash, or interrupt), resume in parallel without
re-meshing or re-decomposing:

```bash
cd /simulation/cyclone-separator
./parCFDDEMcontinue.sh
# optional: END_TIME=20.0 ./parCFDDEMcontinue.sh
```

This continues **both CFD and DEM/DPM** (particles are restored from a DEM
restart or matching dump, then keep moving/injecting). If the last time
directory was truncated mid-write, resume from the previous good dump/restart.
After a continue, refresh ParaView data:

```bash
./Allpostprocess.sh
```

Then in ParaView use **File → Reload Files** (or reopen
`cycloneSeparator.foam` and `particles.pvd`).

For an optional DEM-only check that LIGGGHTS can read `body.stl`:

```bash
./parDEMrun.sh
```

## Post-process

```bash
./Allpostprocess.sh
# faster options:
# RECONSTRUCT_JOBS=12 ./Allpostprocess.sh
# RECONSTRUCT_TIME='5:' ./Allpostprocess.sh          # only t>=5 s
# SKIP_CFD_RECONSTRUCT=1 ./Allpostprocess.sh         # particles only
# RECONSTRUCT_FIELDS=all ./Allpostprocess.sh         # every CFD field
```

`Allpostprocess.sh` runs several `reconstructPar -noLagrangian` jobs in
parallel (`RECONSTRUCT_JOBS`, default 8). By default it only rebuilds
ParaView-useful fields (`U p voidfraction Us Ksl …`); use
`RECONSTRUCT_FIELDS=all` for a full reconstruct. `-newTimes` skips times that
are already reconstructed, then converts DEM dumps (`--dt 5e-7`).

Many write intervals use a lot of disk (processor data + reconstructed
fields + particle VTPs). Prefer `SKIP_CFD_RECONSTRUCT=1` when you only need
particles, or raise `writeInterval` for lighter future runs.

Open:

- `CFD/cycloneSeparator.foam`
- `DEM/post/particles.pvd`

Useful CFD fields are `U`, `p`, and `voidfraction`. Particle dumps include
diameter, velocity, and CFD drag.

## Main controls

- Air speed and direction: `CFD/0/U` (also rescale `0/k` and `0/epsilon`)
- Particle speed, sizes, fractions, and rate: `DEM/in.liggghts_run`
- Fluid properties: `CFD/0/rho`, `CFD/constant/transportProperties`
- Mesh resolution: `CFD/system/blockMeshDict`, `CFD/system/snappyHexMeshDict`
- Simulation duration: `CFD/system/controlDict`
- Coupling: `CFD/constant/couplingProperties` and `DEM/in.liggghts_run`

`couplingInterval` and `couple_every` are both DEM steps and must stay equal:

```text
CFDEM: DEM timestep × couplingInterval = 5e-7 × 20000 = 0.01 s
DEM:   timestep × couple_every         = 5e-7 × 20000 = 0.01 s
(= 4 CFD steps at deltaT = 0.0025 s; write/dump every 0.005 s = 10000 DEM steps)
```

## Physical limitations

- Unresolved, spherical-particle CFD–DEM demonstration.
- Sub-100 µm cohesive dust needs adhesion/cohesion and often parcel or
  coarse-graining treatment; those effects are not enabled here.
- On a shallow cone, strong swirl can park grains mid-wall; keep CFD and DEM
  inlet speeds consistent when tuning settling vs separation.
- Validate mesh independence, pressure drop, residence time, and grade
  efficiency against experiment before treating the output as predictive.
