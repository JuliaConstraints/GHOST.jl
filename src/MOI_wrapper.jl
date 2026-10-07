const _Cache = MOI.Utilities.UniversalFallback{MOI.Utilities.Model{Float64}}
const _Bounds = Union{MOI.EqualTo{Float64},MOI.LessThan{Float64},MOI.GreaterThan{Float64},MOI.Interval{Float64}}
const _VariableSets = Union{_Bounds,MOI.Integer,MOI.ZeroOne}
const _OPTION_TYPES = Dict{String,DataType}(
    "error_backend" => String,
    "permutation_problem" => Bool,
    "optimization_guidance" => Bool,
    "tabu_time_local_min" => Int,
    "tabu_time_selected" => Int,
    "plateau_probability" => Int,
    "reset_threshold" => Int,
    "restart_threshold" => Int,
    "variables_to_reset" => Int,
    "start_samplings" => Int,
)

mutable struct Optimizer <: MOI.AbstractOptimizer
    cache::_Cache
    options::Dict{String,Any}
    time_limit::Union{Nothing,Float64}
    threads::Int
    silent::Bool
    session::Union{Nothing,CAPI.Session}
    bindings::Dict{MOI.ConstraintIndex,Any}
    primal::Dict{MOI.VariableIndex,Float64}
    termination::MOI.TerminationStatusCode
    raw_status::String
    solve_time::Float64
    solving::Bool
end

function Optimizer(; kwargs...)
    optimizer = Optimizer(MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
        Dict{String,Any}(), nothing, 1, true, nothing, Dict{MOI.ConstraintIndex,Any}(), Dict{MOI.VariableIndex,Float64}(),
        MOI.OPTIMIZE_NOT_CALLED, "OPTIMIZE_NOT_CALLED", 0.0, false)
    for (name, value) in kwargs
        MOI.set(optimizer, MOI.RawOptimizerAttribute(String(name)), value)
    end
    return optimizer
end

function _invalidate!(optimizer::Optimizer)
    optimizer.solving && error("A GHOST optimizer cannot be modified or solved recursively during optimize!")
    optimizer.session === nothing || close(optimizer.session)
    optimizer.session = nothing
    empty!(optimizer.bindings)
    empty!(optimizer.primal)
    optimizer.termination = MOI.OPTIMIZE_NOT_CALLED
    optimizer.raw_status = "OPTIMIZE_NOT_CALLED"
    optimizer.solve_time = 0.0
    return nothing
end

MOI.supports_incremental_interface(::Optimizer) = true
MOI.copy_to(dest::Optimizer, src::MOI.ModelLike) = MOI.Utilities.default_copy_to(dest, src)
MOI.is_empty(optimizer::Optimizer) = MOI.is_empty(optimizer.cache)
function MOI.empty!(optimizer::Optimizer)
    _invalidate!(optimizer)
    MOI.empty!(optimizer.cache)
    return nothing
end
MOI.is_valid(optimizer::Optimizer, index::Union{MOI.VariableIndex,MOI.ConstraintIndex}) = MOI.is_valid(optimizer.cache, index)
function MOI.add_variable(optimizer::Optimizer)
    _invalidate!(optimizer)
    return MOI.add_variable(optimizer.cache)
end
MOI.add_variables(optimizer::Optimizer, count::Int) = [MOI.add_variable(optimizer) for _ in 1:count]
function MOI.delete(optimizer::Optimizer, index::Union{MOI.VariableIndex,MOI.ConstraintIndex,Vector{MOI.VariableIndex},Vector{<:MOI.ConstraintIndex}})
    _invalidate!(optimizer)
    return MOI.delete(optimizer.cache, index)
end
MOI.supports_constraint(::Optimizer, ::Type{MOI.VariableIndex}, ::Type{S}) where {S<:_VariableSets} = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.ScalarAffineFunction{Float64}}, ::Type{S}) where {S<:_Bounds} = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{MOI.AllDifferent}) = true
MOI.supports_constraint(::Optimizer, ::Type{MOI.VectorOfVariables}, ::Type{<:MOIError}) = true
MOI.supports_constraint(::Optimizer, ::Type{<:MOI.AbstractFunction}, ::Type{<:MOI.AbstractSet}) = false

function MOI.add_constraint(optimizer::Optimizer, f::F, set::S) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    MOI.supports_constraint(optimizer, F, S) || throw(MOI.UnsupportedConstraint{F,S}())
    if f isa MOI.VectorOfVariables
        MOI.output_dimension(f) == MOI.dimension(set) || throw(DimensionMismatch("constraint scope and set"))
        isempty(f.variables) && throw(ArgumentError("GHOST vector constraints require a nonempty scope"))
    end
    _invalidate!(optimizer)
    return MOI.add_constraint(optimizer.cache, f, set)
end

MOI.get(optimizer::Optimizer, attr::MOI.AbstractModelAttribute) = MOI.get(optimizer.cache, attr)
MOI.get(optimizer::Optimizer, attr::MOI.AbstractVariableAttribute, index::MOI.VariableIndex) = MOI.get(optimizer.cache, attr, index)
MOI.get(optimizer::Optimizer, attr::MOI.AbstractConstraintAttribute, index::MOI.ConstraintIndex) = MOI.get(optimizer.cache, attr, index)
MOI.get(optimizer::Optimizer, ::Type{T}, name::String) where {T<:Union{MOI.VariableIndex,MOI.ConstraintIndex}} = MOI.get(optimizer.cache, T, name)
MOI.supports(optimizer::Optimizer, attr::Union{MOI.Name,MOI.ObjectiveSense}) = MOI.supports(optimizer.cache, attr)
MOI.supports(::Optimizer, ::MOI.ObjectiveFunction{F}) where {F} = F in (MOI.VariableIndex,MOI.ScalarAffineFunction{Float64})
MOI.supports(optimizer::Optimizer, attr::Union{MOI.VariableName,MOI.VariablePrimalStart}, ::Type{MOI.VariableIndex}) = MOI.supports(optimizer.cache, attr, MOI.VariableIndex)
MOI.supports(optimizer::Optimizer, attr::MOI.ConstraintName, ::Type{CI}) where {CI<:MOI.ConstraintIndex} = MOI.supports(optimizer.cache, attr, CI)

function MOI.set(optimizer::Optimizer, attr::MOI.AbstractModelAttribute, value)
    MOI.supports(optimizer, attr) || throw(MOI.UnsupportedAttribute(attr))
    _invalidate!(optimizer)
    return MOI.set(optimizer.cache, attr, value)
end
function MOI.set(optimizer::Optimizer, attr::MOI.AbstractVariableAttribute, index::MOI.VariableIndex, value)
    _invalidate!(optimizer)
    return MOI.set(optimizer.cache, attr, index, value)
end
function MOI.set(optimizer::Optimizer, attr::MOI.AbstractConstraintAttribute, index::MOI.ConstraintIndex, value)
    _invalidate!(optimizer)
    return MOI.set(optimizer.cache, attr, index, value)
end
function MOI.modify(optimizer::Optimizer, index::MOI.ConstraintIndex, change::MOI.AbstractFunctionModification)
    _invalidate!(optimizer)
    return MOI.modify(optimizer.cache, index, change)
end
function MOI.modify(optimizer::Optimizer, attr::MOI.ObjectiveFunction, change::MOI.AbstractFunctionModification)
    _invalidate!(optimizer)
    return MOI.modify(optimizer.cache, attr, change)
end

MOI.supports(::Optimizer, ::Union{MOI.Silent,MOI.TimeLimitSec,MOI.NumberOfThreads}) = true
MOI.get(optimizer::Optimizer, ::MOI.Silent) = optimizer.silent
MOI.get(optimizer::Optimizer, ::MOI.TimeLimitSec) = optimizer.time_limit
MOI.get(optimizer::Optimizer, ::MOI.NumberOfThreads) = optimizer.threads
function MOI.set(optimizer::Optimizer, ::MOI.Silent, value::Bool)
    optimizer.solving && error("Cannot change options during solve")
    optimizer.silent = value
    return nothing
end
function MOI.set(optimizer::Optimizer, ::MOI.TimeLimitSec, value::Union{Nothing,Real})
    optimizer.solving && error("Cannot change options during solve")
    if value !== nothing
        isfinite(value) && value > 0 || throw(ArgumentError("GHOST requires a finite positive time limit"))
    end
    optimizer.time_limit = value === nothing ? nothing : Float64(value)
    return nothing
end
function MOI.set(optimizer::Optimizer, ::MOI.NumberOfThreads, value::Union{Nothing,Integer})
    optimizer.solving && error("Cannot change options during solve")
    threads = value === nothing ? 1 : Int(value)
    1 <= threads <= typemax(Cint) || throw(ArgumentError("GHOST thread count must be positive and representable as a C int"))
    optimizer.threads = threads
    return nothing
end
MOI.supports(::Optimizer, attr::MOI.RawOptimizerAttribute) = haskey(_OPTION_TYPES, attr.name)
function MOI.set(optimizer::Optimizer, attr::MOI.RawOptimizerAttribute, value)
    optimizer.solving && error("Cannot change options during solve")
    MOI.supports(optimizer, attr) || throw(MOI.UnsupportedAttribute(attr))
    expected = _OPTION_TYPES[attr.name]
    value isa expected || throw(ArgumentError("$(attr.name) expects $expected"))
    if attr.name == "error_backend"
        value in ("icn", "native") || throw(ArgumentError("error_backend must be icn or native"))
    end
    if expected === Int
        -1 <= value <= typemax(Cint) || throw(ArgumentError("Invalid value for $(attr.name)"))
        if attr.name == "plateau_probability"
            0 <= value <= 100 || throw(ArgumentError("plateau_probability must be in 0:100"))
        end
    end
    optimizer.options[attr.name] = value
    return nothing
end
function MOI.get(optimizer::Optimizer, attr::MOI.RawOptimizerAttribute)
    MOI.supports(optimizer, attr) || throw(MOI.UnsupportedAttribute(attr))
    attr.name == "error_backend" && return get(optimizer.options, attr.name, "icn")
    return get(optimizer.options, attr.name, _OPTION_TYPES[attr.name] === Bool ?
        attr.name == "optimization_guidance" : -1)
end
MOI.get(::Optimizer, ::MOI.SolverName) = "GHOST (C++ development, callback ABI 1.0)"
MOI.get(::Optimizer, ::MOI.SolverVersion) = "3.5.0-dev"
MOI.get(optimizer::Optimizer, ::MOI.TerminationStatus) = optimizer.termination
MOI.get(optimizer::Optimizer, ::MOI.RawStatusString) = optimizer.raw_status
MOI.get(optimizer::Optimizer, ::MOI.SolveTimeSec) = optimizer.solve_time
MOI.get(optimizer::Optimizer, ::MOI.ResultCount) = isempty(optimizer.primal) ? 0 : 1
MOI.get(optimizer::Optimizer, attr::MOI.PrimalStatus) =
    1 <= attr.result_index <= MOI.get(optimizer, MOI.ResultCount()) ? MOI.FEASIBLE_POINT : MOI.NO_SOLUTION
MOI.get(::Optimizer, ::MOI.DualStatus) = MOI.NO_SOLUTION
function MOI.get(optimizer::Optimizer, attr::MOI.VariablePrimal, index::MOI.VariableIndex)
    MOI.check_result_index_bounds(optimizer, attr)
    MOI.throw_if_not_valid(optimizer.cache, index)
    return optimizer.primal[index]
end
function MOI.get(optimizer::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(optimizer, attr)
    MOI.get(optimizer.cache, MOI.ObjectiveSense()) == MOI.FEASIBILITY_SENSE && return 0.0
    F = MOI.get(optimizer.cache, MOI.ObjectiveFunctionType())
    f = MOI.get(optimizer.cache, MOI.ObjectiveFunction{F}())
    return MOI.Utilities.eval_variables(v -> optimizer.primal[v], f)
end
function MOI.get(optimizer::Optimizer, attr::MOI.ConstraintPrimal, index::MOI.ConstraintIndex)
    MOI.check_result_index_bounds(optimizer, attr)
    f = MOI.get(optimizer.cache, MOI.ConstraintFunction(), index)
    return MOI.Utilities.eval_variables(v -> optimizer.primal[v], f)
end

function _domains(cache, variables)
    lower = Dict(v => -Inf for v in variables)
    upper = Dict(v => Inf for v in variables)
    integer = Set{MOI.VariableIndex}()
    for (F, S) in MOI.get(cache, MOI.ListOfConstraintTypesPresent())
        F === MOI.VariableIndex || continue
        for index in MOI.get(cache, MOI.ListOfConstraintIndices{F,S}())
            v = MOI.get(cache, MOI.ConstraintFunction(), index)
            set = MOI.get(cache, MOI.ConstraintSet(), index)
            if set isa MOI.Integer
                push!(integer, v)
            elseif set isa MOI.ZeroOne
                push!(integer, v)
                lower[v] = max(lower[v], 0.0); upper[v] = min(upper[v], 1.0)
            elseif set isa MOI.GreaterThan
                lower[v] = max(lower[v], set.lower)
            elseif set isa MOI.LessThan
                upper[v] = min(upper[v], set.upper)
            elseif set isa MOI.EqualTo
                lower[v] = max(lower[v], set.value); upper[v] = min(upper[v], set.value)
            elseif set isa MOI.Interval
                lower[v] = max(lower[v], set.lower); upper[v] = min(upper[v], set.upper)
            end
        end
    end
    domains = Dict{MOI.VariableIndex,Tuple{Cint,Cint}}()
    for v in variables
        v in integer || throw(ArgumentError("GHOST supports integer variables only; add an Integer or ZeroOne constraint to $v"))
        isfinite(lower[v]) && isfinite(upper[v]) || throw(ArgumentError("$v requires finite bounds"))
        lo, hi = ceil(lower[v]), floor(upper[v])
        typemin(Cint) <= lo <= hi <= typemax(Cint) || throw(ArgumentError("$v has an empty or unrepresentable integer domain"))
        # Native GHOST explicitly materializes domains; avoid silent enormous allocations.
        hi - lo < 10_000_000 || throw(ArgumentError("$v has a domain too large for this explicit-domain solver"))
        domains[v] = (Cint(lo), Cint(hi))
    end
    return domains
end

function _affine_data(f::MOI.ScalarAffineFunction{Float64}, ids)
    f = MOI.Utilities.canonical(f)
    all(t -> isfinite(t.coefficient), f.terms) && isfinite(f.constant) || throw(ArgumentError("Nonfinite affine data"))
    scope = Cint[ids[t.variable] for t in f.terms]
    coefficients = Float64[t.coefficient for t in f.terms]
    if isempty(scope)
        push!(scope, first(values(ids))); push!(coefficients, 0.0)
    end
    return scope, coefficients, f.constant
end
function _add_affine(session, f, set, ids)
    scope, coefficients, constant = _affine_data(f, ids)
    if set isa MOI.EqualTo
        isfinite(set.value) || throw(ArgumentError("Nonfinite affine equality"))
        CAPI.add_linear(session, :ghost_add_linear_eq_constraint, scope, coefficients, set.value - constant)
    elseif set isa MOI.LessThan
        isfinite(set.upper) || throw(ArgumentError("Nonfinite affine upper bound"))
        CAPI.add_linear(session, :ghost_add_linear_le_constraint, scope, coefficients, set.upper - constant)
    elseif set isa MOI.GreaterThan
        isfinite(set.lower) || throw(ArgumentError("Nonfinite affine lower bound"))
        CAPI.add_linear(session, :ghost_add_linear_ge_constraint, scope, coefficients, set.lower - constant)
    else
        _add_affine(session, f, MOI.GreaterThan(set.lower), ids)
        _add_affine(session, f, MOI.LessThan(set.upper), ids)
    end
end

function _build_session(optimizer::Optimizer)
    cache = optimizer.cache
    variables = MOI.get(cache, MOI.ListOfVariableIndices())
    isempty(variables) && throw(ArgumentError("GHOST requires at least one bounded integer variable"))
    domains = _domains(cache, variables)
    session = CAPI.Session(get(optimizer.options, "permutation_problem", false))
    optimizer.session = session
    ids = Dict{MOI.VariableIndex,Cint}()
    starting_point = Dict{MOI.VariableIndex,Float64}()
    has_starts = false
    for v in variables
        lo, hi = domains[v]
        name = MOI.get(cache, MOI.VariableName(), v)
        ids[v] = Cint(CAPI.add_variable(session, lo, hi, name))
        start = MOI.get(cache, MOI.VariablePrimalStart(), v)
        if start !== nothing
            isinteger(start) && lo <= start <= hi || throw(ArgumentError("Invalid integer starting value for $v"))
            has_starts = true
        end
        starting_point[v] = start === nothing ? Float64(lo) : Float64(start)
    end
    for (F, S) in MOI.get(cache, MOI.ListOfConstraintTypesPresent())
        F === MOI.VariableIndex && continue
        for index in MOI.get(cache, MOI.ListOfConstraintIndices{F,S}())
            f = MOI.get(cache, MOI.ConstraintFunction(), index)
            set = MOI.get(cache, MOI.ConstraintSet(), index)
            if f isa MOI.ScalarAffineFunction{Float64}
                _add_affine(session, f, set, ids)
            elseif set isa MOI.AllDifferent
                if get(optimizer.options, "error_backend", "icn") == "native"
                    CAPI.add_alldifferent(session, Cint[ids[v] for v in f.variables])
                else
                    evaluator = _bind_catalogue(_catalogue_set(set), set.dimension)
                    optimizer.bindings[index] = _add_callback(session, Cint[ids[v] for v in f.variables], evaluator)
                end
            elseif _is_catalogue(set)
                evaluator = _bind_catalogue(_catalogue_set(set), MOI.dimension(set))
                optimizer.bindings[index] = _add_callback(session, Cint[ids[v] for v in f.variables], evaluator)
            elseif set isa MOIError
                state = _add_callback(session, Cint[ids[v] for v in f.variables], _bind_error(set.f, set.dimension))
                optimizer.bindings[index] = state
            else
                throw(MOI.UnsupportedConstraint{F,S}())
            end
            if haskey(optimizer.bindings, index)
                state = optimizer.bindings[index]
                # Compile saved ICNs and check the contract before the timed search.
                state.values .= Int[starting_point[v] for v in f.variables]
                score = Float64(Base.invokelatest(state.f, state.values))
                isfinite(score) && score >= 0 || throw(DomainError(score, "Invalid initial error evaluation"))
            end
        end
    end
    if !isempty(session.callbacks) && optimizer.threads != 1
        throw(ArgumentError("Julia error callbacks require one native thread per optimizer. Parallelize independent GHOST.Optimizer instances on Julia threads, each with its own workspace."))
    end
    sense = MOI.get(cache, MOI.ObjectiveSense())
    if sense != MOI.FEASIBILITY_SENSE
        F = MOI.get(cache, MOI.ObjectiveFunctionType())
        f = MOI.get(cache, MOI.ObjectiveFunction{F}())
        if f isa MOI.VariableIndex
            f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, f)], 0.0)
        end
        scope, coefficients, constant = _affine_data(f, ids)
        CAPI.set_objective(session, sense == MOI.MAX_SENSE, scope, coefficients, constant)
    end
    if has_starts
        for v in variables
            CAPI.set_start(session, ids[v], Cint(starting_point[v]))
        end
    end
    return session, variables, has_starts
end

_is_catalogue(set) = false

function _validate_primal!(optimizer::Optimizer)
    for (F, S) in MOI.get(optimizer.cache, MOI.ListOfConstraintTypesPresent())
        for index in MOI.get(optimizer.cache, MOI.ListOfConstraintIndices{F,S}())
            f = MOI.get(optimizer.cache, MOI.ConstraintFunction(), index)
            set = MOI.get(optimizer.cache, MOI.ConstraintSet(), index)
            value = MOI.Utilities.eval_variables(v -> optimizer.primal[v], f)
            valid = if set isa MOI.Integer
                isinteger(value)
            elseif set isa MOI.ZeroOne
                value == 0 || value == 1
            elseif set isa MOI.EqualTo
                value == set.value
            elseif set isa MOI.LessThan
                value <= set.upper
            elseif set isa MOI.GreaterThan
                value >= set.lower
            elseif set isa MOI.Interval
                set.lower <= value <= set.upper
            elseif set isa MOI.AllDifferent
                length(unique(value)) == length(value)
            elseif set isa MOIError
                evaluator = optimizer.bindings[index].f
                iszero(Base.invokelatest(evaluator, Int.(value)))
            elseif _is_catalogue(set)
                _validate_catalogue(_catalogue_set(set), Int.(value))
            else
                false
            end
            valid || error("GHOST returned a solution that violates original MOI constraint $index")
        end
    end
    return nothing
end

function MOI.optimize!(optimizer::Optimizer)
    _invalidate!(optimizer)
    optimizer.solving = true
    options = nothing
    try
        session, variables, has_starts = _build_session(optimizer)
        options = CAPI.Options()
        CAPI.set_option(options, :ghost_set_option_num_threads, optimizer.threads)
        CAPI.set_option(options, :ghost_set_option_parallel, optimizer.threads > 1)
        CAPI.set_option(options, :ghost_set_option_custom_starting_point, has_starts)
        for (name, value) in optimizer.options
            name in ("permutation_problem", "error_backend") && continue
            CAPI.set_option(options, Symbol("ghost_set_option_", name), value)
        end
        # No wall-clock bound is supplied by MOI when TimeLimitSec() is nothing;
        # this heuristic wrapper uses a documented finite 60-second default.
        seconds = something(optimizer.time_limit, 60.0)
        status = GC.@preserve optimizer session options CAPI.solve(session, options, seconds * 1e6)
        _callback_failure(session)
        CAPI.check(status, session)
        optimizer.solve_time = CAPI.scalar_result(session, :ghost_get_solve_time)
        optimizer.raw_status = CAPI.raw_status(session)
        optimizer.termination = status == CAPI.SAT_FOUND ? MOI.LOCALLY_SOLVED : MOI.TIME_LIMIT
        if status in (CAPI.SAT_FOUND, CAPI.FEASIBLE_FOUND)
            values = CAPI.values(session, length(variables))
            for (v, value) in zip(variables, values)
                optimizer.primal[v] = Float64(value)
            end
            _validate_primal!(optimizer)
        end
    catch
        optimizer.termination = MOI.OTHER_ERROR
        optimizer.raw_status = "MODEL_OR_CALLBACK_ERROR"
        empty!(optimizer.primal)
        rethrow()
    finally
        options === nothing || close(options)
        optimizer.solving = false
    end
    return nothing
end
