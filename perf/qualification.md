# Julia callback barrier qualification — 8 October 2026

Frozen baseline: GHOST `75be7a567478ebbabece912677d1fa0b228ec26d`,
GHOST_jll `d32e43e0afda0da43d2779e209a0b011624e0f43`. The cached Linux library
was reused from artifact `74dbb8a57bef486956d7c309611a37e1fa3e54c5`; no native
solver or library was installed or rebuilt. Native access used the Julia wrapper.

The callback now invokes a concrete evaluator/validation barrier in the latest
Julia world. This keeps counters, score conversion and validation typed while
supporting ICNs compiled after the C trampoline was created. Input copying,
finite/nonnegative constraint scores, negative objective scores and the first
captured exception contract are preserved. Native failure still leaves the
result pointer untouched.

`callback_scenarios.jl` crosses the real Julia C trampoline for two inputs,
1,024 times (2,048 callbacks), using both an ordinary error and the existing
CompositionalNetworks all-different ICN wiring. Its independent zero-set oracle
checks original all-different truth. Each binding owns its values and ICN
workspace. Warm fixtures make two untimed callback calls during preparation;
the counter is then reset. Cold fixtures disable that warming explicitly.

Julia 1.13.1; CPUs 0,2; Julia threads 2, GC threads 1, BLAS/OpenMP threads 1,
precompile tasks 1. Native tests use one worker per solve and bounded .02–.05 s
budgets. Two private Julia tasks each use one native worker for ownership checks.
The native-only two-worker test variant was omitted; the rejected multiworker
callback request still exercises the wrapper's rejection contract.

| Warm operation on an already exercised binding, 2,048 callbacks | Before bytes / objects | After bytes / objects | Before seconds (3 samples) | After seconds (3 samples) |
|---|---:|---:|---|---|
| ordinary error | 163,904 / 10,243 | 32,832 / 2,051 | .000509809, .000496948, .000511038 | .000175030, .000140645, .000150814 |
| compiled ICN | 196,672 / 12,291 | 32,832 / 2,051 | .000626262, .000624432, .000612344 | .000193240, .000187180, .000179362 |

No warm compile or collection time was measured. Shared-machine timing is
operational evidence, not native solver throughput or scaling evidence. The
remaining trampoline allocation profile is a Float64 box at the latest-world
return boundary (approximately one 16-byte object per callback).

All 1,701 assertions in the one-native-worker qualification passed: existing
JuMP/MOI, native results, callbacks, ICN and saved-catalogue truth tests, plus
new late-world, private input, allocation-growth and exception-boundary checks.
All four PerfChecker collectors executed with passing callback/ICN oracles.

Fresh private ICN bindings create distinct compiled callable types. Collector
scopes therefore differ from the warm repeated-binding table. With the same
final harness and source dependencies, BenchmarkTools's fresh ICN case changed
from 681,696 bytes / 21,322 objects to 534,224 / 12,105; Chairmarks from 182,240 /
11,301 to 34,768 / 2,084. Each has two samples. First-operation compilation is
included in these observations; they are not a common steady-state estimate.
A direct probe of three fresh warmed bindings still found about .0033–.0034 s
compilation on the first harness operation, then zero compilation on the second.

JET and AllocCheck each reported zero findings for the concrete ordinary and
ICN evaluator barriers. JET reported 46 findings in the erased native trampoline,
including intentional latest-world dispatch and exception/runtime paths. Native
foreign-call boundaries are not a static proof of whole-operation allocation
freedom. SnoopCompile's cold private-ICN case measured 1.758 s inclusive inference.
Separate latency source/first/full-warm scopes were 1.531/4.493/.1464 s; the
fresh-binding lifecycle can generate code even after an earlier case ran.

GC/lock instrumentation of fresh private ICN fixtures measured about 1.596 MB
and .023–.025 s compile time, with no collections or lock conflicts. These
compiler allocations are kept separate from the repeated-binding table.
Reachable fixture size stayed 1,080 bytes (1,088 including the scalar result).
That fixture contains Julia callback data, not a native solver heap snapshot.

Aqua executed and identified two preexisting package-quality issues: an MOI
single-index deletion ambiguity and a missing Test-extra compatibility bound.
The callback increment does not claim a full Aqua pass. Bulk profiles, raw
snapshots and temporary diagnostic environments are not committed.
