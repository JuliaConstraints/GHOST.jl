# GHOST.jl

JuMP/MathOptInterface frontend to the **C++ GHOST development branch**, through
the C ABI. This is the regenerated native wrapper with UUID
`11b06263-fdad-4e56-a327-8fd38a91e0b8`, not the old pure-Julia port with the same
repository name. Version 0.2.0 is new source; it does not pretend to recover the
missing bytes of the previous wrapper commit.

Native baseline: upstream `richoux/GHOST` **develop**, commit
`37bbfdf612af229cf9fbb9688995cae268c53a64`. The ABI from
`Azzaare/GHOST:forge/jump-wrapper-2026` is preserved and extended for Julia
callbacks. `GHOST_jll` supplies the library or reuses `GHOST_LIBRARY` when set to
an existing compatible library. A cached Artifact is reused without rebuilding
or reinstalling it. Tested native Artifacts are available for Linux
x86_64/aarch64, macOS Intel/Apple Silicon and Windows x86_64, with corresponding
GPL source included. Julia frontend qualification is a separate test gate.

```julia
using JuMP, GHOST
import MathOptInterface as MOI
model = Model(GHOST.Optimizer)
set_time_limit_sec(model, 0.1)
@variable(model, 1 <= x[1:3] <= 3, Int)
@constraint(model, x in MOI.AllDifferent(3))
@constraint(model, x in GHOST.Constraint(:sum; val=6))
optimize!(model)
value.(x)
```

Supported model classes: bounded integer and binary variables, affine
equalities/inequalities/intervals, `MOI.AllDifferent`, scoped Julia error
constraints, affine minimization/maximization and scoped callback objectives
via `GHOST.set_callback_objective(model, MOI.MIN_SENSE, variables, callable)`.
Continuous, unbounded,
quadratic and generic nonlinear models are unsupported. Domains are explicit
and limited to fewer than ten million integers per variable. An empty integer
domain is rejected. Models require at least one variable.

`GHOST.Error(f)` requires a finite, nonnegative `f(values)`, whose zero set is
exactly the constraint's feasible set. The input is a borrowed reusable vector;
do not retain it. The callable is copied for each native session. Callbacks
catch Julia exceptions inside the C boundary; the original exception is thrown
in Julia after the native solve returns. GC remains enabled.

## Learned ICNs

The normal frontend declares library constraints. Their saved ICN weights are
shipped with the package, restored with the generic CompositionalNetworks
constructor, and checked against the recorded operation-schema hash. Users do
not implement error functions or pass networks. `MOI.AllDifferent`,
`CPE.AllEqual`, `CPE.Increasing` and `CPE.Decreasing` map automatically to the
catalogue. `GHOST.Constraint(:name; parameters...)` additionally exposes the
11 saved variants reported by `GHOST.catalogue()`: allDifferent (standard and
exceptions), allEqual, nondecreasing order, sum (weighted and unweighted),
minimum, maximum, instantiation, count and nValues. Unsupported variants fail
explicitly. Original Boolean concepts independently validate exported solutions.

The recovered bank contains manually selected ICN witnesses encoded in a
learnable grammar, previously checked on the recorded finite assignments. It
does not establish that these weights came from a training run, nor universal
qualification of every variant. The port's tests independently check those
zero sets on small exhaustive assignments. That
provenance is available in the catalogue and each session's evaluator metadata.
There is no implicit substitution of a Boolean penalty for a missing ICN.

Explicit CompositionalNetworks input remains available for custom networks:

```julia
using CompositionalNetworks
# `learned_network` is your already trained and qualified ICN.
@constraint(model, x in GHOST.ICNError(learned_network; dom_size=3, numvars=3))
```

An ICN or `Composition` retains its selected operations and parameters. Each
solve binds a compiled function and a private `composition_workspace`. The
first evaluation prepares the generated function before the timed search.
Direct ICNs use compiled functions and private matrix buffers. Compound ICNs
use the pinned library's decoded callable with private network state; this
version does not expose a compiled workspace interface for those compositions.
No learning or operation replacement occurs implicitly. A learned error's zero
set must still be qualified against the original problem's validator; the
optimizer checks its declared MOI constraints, not an unstated original intent.
Tests include exhaustive zero-set checks on a small selected AllDifferent ICN.

## Threads, statuses and timing

Affine constraints can use native workers via `MOI.NumberOfThreads()`.
`error_backend="native"` opts into the native AllDifferent implementation;
the default `"icn"` binds standard global constraints to the saved catalogue.
Julia/ICN error callbacks require **one native worker per optimizer**: native
C++ threads must not enter Julia's runtime. For parallel callback solving, use
independent JuMP models on Julia-managed threads, with separate sessions,
callables and workspaces. Asking a callback model for multiple native threads
raises an error; it does not silently reduce the requested width.

GHOST performs heuristic search. Satisfaction produces `LOCALLY_SOLVED` with a
feasible point; optimization produces `TIME_LIMIT` with an incumbent. An
unsuccessful search produces `TIME_LIMIT` without a result. Neither optimality
nor infeasibility is claimed. Exported incumbents are rechecked in the declared
original MOI model. Results are invalidated after model edits.

The native search time excludes model construction and the first Julia/ICN
evaluation. `TimeLimitSec() = nothing` uses a finite 60-second default. Set a
positive explicit budget in comparisons and report both native search and
end-to-end elapsed time. Upstream random seeding is not exposed by this ABI;
this wrapper does not invent reproducibility from an ignored seed parameter.

## Development and qualification

Keep this checkout and GHOST_jll under `~/.julia/dev`. Develop both packages
into an isolated environment, then run `Pkg.test("GHOST")` with two Julia
threads and single BLAS/GC threads. A native library with callback ABI 1.0 is
required. `test/interface.jl` exercises MOI model construction/copying, and
`test/native.jl`, `test/icn.jl` and `test/catalogue.jl` qualify results, original
concept/ICN zero-set agreement, exception boundaries and
independent worker state. These are bounded functional tests, not a solver
comparison campaign. On 7 October 2026, all 1,665 frontend assertions passed
locally with two Julia threads; the native C ABI tests also passed on all five
distribution platforms. No performance claim is based on this preparation.

The interface follows the official
[MOI solver implementation guide](https://jump.dev/MathOptInterface.jl/stable/tutorials/implementing/)
and [JuMP extension API](https://jump.dev/JuMP.jl/stable/developers/extensions/).
Native code and this wrapper are distributed under GPL-3.0-or-later; retain the
license and corresponding native source when distributing binaries.
