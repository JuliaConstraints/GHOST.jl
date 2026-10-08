# Exact Li-Lim adapter qualification, 2026-10-08

The existing Li-Lim `GHOSTNative.jl` adapter passes 855 assertions against the
frozen V3 environment, loading `Pilot`, `MetaRepair`, `ICNScoring` and
`GHOSTNative` directly. The installed wrapper is GHOST
`3b9e3e26e218f1e29e0a6fa7cc9cd52a1c969fef`; its cached native library SHA-256 is
`50bbe8af9cd061c6dfeb2eb9b80b2c3f0c74110c3e91429543b3173f5165545d`.
The optional runner qualification gate is unchanged. No installation, package
resolution, licence probe, source modification or comparative campaign occurs.

Julia 1.13.1 runs on CPUs 0 and 2 with two Julia threads, one GC thread and one
BLAS/OpenMP thread. Each GHOST model uses one native worker. Two-lane checks use
independent models and private callback/ICN storage.

The tiny original input is created in an automatically removed temporary
directory; its SHA-256 is
`0aa9c1cf876260da221aa8d6c9c2224045b0162145102d1c82b79e9faede8a4a`:

```text
3 1 1
0 0 0 0 0 20 0 0 0
1 1 1 1 0 20 0 0 2
2 2 1 -1 0 20 0 1 0
3 -1 1 1 0 20 0 0 4
4 -2 1 -1 0 20 0 3 0
```

All 720 permutations of nodes 2:7 agree with the original PDPTW validator's
feasibility. All 24 feasible permutations also agree on vehicle count and
continuous distance (absolute tolerance 1e-10): 770 assertions pass.

The adapter's actual `warmup` runs before each lane width. Four bounded
`run_case` calls pass 44 assertions, including original solution/trajectory
validation, objective agreement, source identity, positive callback counts,
lane width and within-budget trajectory timestamps.

| Julia lanes | Budget seconds | Seed label | Outer wall seconds | Objective evaluations |
|---:|---:|---:|---:|---:|
| 1 | 3 | 41 | 3.053950332 | 403,251 |
| 1 | 1 | 42 | 1.050750143 | 134,792 |
| 2 | 3 | 41 | 3.085047678 | 794,830 |
| 2 | 1 | 42 | 1.066977619 | 267,118 |

Every result retains the valid common insertion start: one vehicle, distance
8.650281539872886. Each trajectory contains that one entry; no improved native
incumbent was observed. The native ABI does not apply the seed label to search.
Outer elapsed time includes final validation and exceeds the requested search
budget slightly. These observations establish functional behavior, not search
quality, deterministic replay, throughput or scaling.

Forty ownership checks pass. Two actual C callback entry points succeed
concurrently, retaining their own copied input after the borrowed C arrays are
mutated. Score cells, successor arrays, distance matrices, backend counters and
every route workspace buffer are private. Two additional actual native lanes,
each capped at .02 seconds, invoke 268/273 objective callbacks and retain valid,
independent routes and trajectories. Observed affinity is exactly `[0,2]`.

The environment files and all listed adapter inputs remain byte-identical
after execution (one final integrity assertion). Raw outputs and helper source
are not saved. Source checkout started at
`932d498e573532940b0eb1614d6e28ce84fb60cb`; unrelated performance-driver changes
were already present.

| Input | SHA-256 |
|---|---|
| V3 Project.toml | `7347b66bc4e6eaaf3393198faebfac15611bc1bb150dcd5c87e845c73fd6b21d` |
| V3 Manifest.toml | `0ca5338888e453a9eee7e77170f0e37c94566ecaf9b42420d22143428bc1f19a` |
| LiLim/src/Pilot.jl | `5a08683820a39270c168b4436c6a8aa5e1b759b9e949074c776218e2212bd9da` |
| LiLim/src/MetaRepair.jl | `d170b3eb82ab6dc3559b55cbdb6206457d48f816e21a1f513bd1cb319d1f2868` |
| LiLim/src/ROFragments.jl | `20723afe6e56c67b8b530d3bef04608767418cfd42758a632445943b75a8e209` |
| LiLim/src/ICNScoring.jl | `5fb75fc59065359161fad934019b06940c5ec68b8b033eb320227d541a0a5212` |
| LiLim/src/GHOSTNative.jl | `933cfee9cc63056e0d8ac66fe14d550017b8ffe91bc3982674e7989a2c6990f3` |
| LiLim/src/PlatformResources.jl | `4937175e5c71001debc4f7a9d0a5b332639bf5755309092754c73228ceb169b1` |
| LiLim/resources/icn-pdptw-witnesses.toml | `4df0b409d303d1b666a2d0aba3367c1dc08a2b380da109e50dee83b042b8ea90` |
| LiLim/test/ghost_native.jl | `3a1f1d755d16ae4b768f25f917b5d1c27a12f0b86d6cbd77a6f19f0368bdb8e1` |
