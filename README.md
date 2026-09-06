# Cyclone separator CFD–DEM

CFDEM case for dilute dust/fine-sand separation in a cyclone. Air enters
tangentially through `inlet.stl` in the **-x direction** and leaves through
`outlet.stl` in the **+z direction**. Polydisperse quartz particles are
injected periodically at the air-inlet velocity.

## Model

| Item | Setting |
|---|---|
| Coupling | `cfdemSolverPiso` + LIGGGHTS, two-way MPI |
| Cyclone geometry | `body.stl`, x/y ±0.160 m, z -0.600 to 0.172 m |
| Inlet | 5.0 m/s in -x |
| Outlet | Pressure outlet in +z |
| Fluid | Air: ρ = 1.2 kg/m³, ν = 1.5e-5 m²/s |
| Turbulence | RAS k-epsilon, 5% inlet intensity |
| Particles | Quartz/sand, ρ = 2650 kg/m³ |
| Diameters | 0.30, 0.60, 1.20 mm (dust / fine / sand; mass fractions 0.05 / 0.25 / 0.70) |
| Diameter mass fractions | 0.05 / 0.25 / 0.70 |
| Wall/particle friction | 0.02 |
| Feed | 500 particles/s for 20 s (batches every 0.05 s), maximum 10000 |
| DEM injection velocity | (-5.0, 0, 0) m/s |
| CFD time step | 0.0025 s (= half of save interval) |
| DEM time step | 5e-7 s |
| Coupling period | 0.01 s (= 4 CFD steps) |
| Save / dump interval | 0.005 s (10000 DEM steps) |
| Simulated time | 20 s |
| MPI | 8 ranks (2 × 2 × 2) |

The softened particle Young's modulus (5e7 Pa) is a computational setting,
not the physical modulus of quartz. Higher values reduce wall overlap but
need a smaller DEM timestep. The feed is intentionally small enough
for a demonstration case; calibrate the particle rate and distribution from
the measured dust loading before using collection-efficiency results.

## Geometry and mesh

The CFD mesh is generated in two steps:

1. `blockMesh` creates a ~11 mm background mesh.
2. `snappyHexMesh -overwrite` retains the internal cyclone-fluid region and
   refines `body`, `inlet`, and `outlet` surfaces to about 6–7 mm
   (~1/4 of the previous cell count).

`inlet.stl` and `outlet.stl` are CFD boundary caps. LIGGGHTS uses only
`DEM/body.stl` as a particle wall, allowing particles to enter and leave
through the open ducts.

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

### Continue from the last written time

If the run stops (walltime, crash, or interrupt), resume in parallel without
re-meshing or re-decomposing:

```bash
cd /simulation/cyclone-separator
./parCFDDEMcontinue.sh
# optional: END_TIME=2.0 ./parCFDDEMcontinue.sh
```

This continues **both CFD and DEM/DPM** (particles are restored from a DEM
restart or matching dump, then keep moving/injecting). After a continue,
refresh ParaView data:

```bash
./Allpostprocess.sh
```

Then in ParaView use **File → Reload Files** (or reopen
`cycloneSeparator.foam` and `particles.pvd`). Old post-processed files stay
stale until you re-run `Allpostprocess.sh`.

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
parallel (time ranges split across `RECONSTRUCT_JOBS`, default 8). By default
it only rebuilds ParaView-useful fields (`U p voidfraction Us Ksl …`); use
`RECONSTRUCT_FIELDS=all` for a full reconstruct. `-newTimes` skips times that
are already reconstructed. It then converts DEM dumps.

Open:

- `CFD/cycloneSeparator.foam`
- `DEM/post/particles.pvd`

Useful CFD fields are `U`, `p`, and `voidfraction`. The particle data include
diameter, velocity, and CFD drag. Particle dumps and CFD writes both use a
0.005 s interval.

## Main controls

- Air speed and direction: `CFD/0/U`
- Particle speed, sizes, fractions, and rate: `DEM/in.liggghts_run`
- Fluid properties: `CFD/0/rho`,
  `CFD/constant/transportProperties`
- Mesh resolution: `CFD/system/blockMeshDict`,
  `CFD/system/snappyHexMeshDict`
- Simulation duration: `CFD/system/controlDict`
- Coupling: `CFD/constant/couplingProperties` and
  `DEM/in.liggghts_run`

`couplingInterval` and `couple_every` are both expressed in DEM steps and
must stay equal:

```text
CFDEM: DEM timestep × couplingInterval = 5e-7 × 20000 = 0.01 s
DEM:   timestep × couple_every         = 5e-7 × 20000 = 0.01 s
This equals 4 CFD steps at deltaT = 0.0025 s (2× writeInterval 0.005 s).
Write/dump interval remains 0.005 s (10000 DEM steps).
```

## Physical limitations

- This is an unresolved, spherical-particle CFD–DEM demonstration.
- Sub-100 µm cohesive dust requires adhesion/cohesion and often parcel or
  coarse-graining treatment; those effects are not enabled here.
- Validate mesh independence, pressure drop, residence time, and grade
  efficiency against experiment before treating the output as predictive.
