mutable struct CallbackState{F}
    f::F
    values::Vector{Int}
    failure::Any
    calls::Int
    objective::Bool
end

function _callback(values::Ptr{Cint}, count::Csize_t, result::Ptr{Cdouble}, userdata::Ptr{Cvoid})::Cint
    state = unsafe_pointer_to_objref(userdata)::CallbackState
    try
        length(state.values) == count || throw(DimensionMismatch("GHOST callback scope"))
        @inbounds for i in eachindex(state.values)
            state.values[i] = unsafe_load(values, i)
        end
        state.calls += 1
        # Compiled ICNs can be generated after this trampoline's world age.
        score = Float64(Base.invokelatest(state.f, state.values))
        isfinite(score) || throw(DomainError(score, "error functions must return a finite score"))
        state.objective || score >= 0 || throw(DomainError(score, "error functions must return a nonnegative score"))
        unsafe_store!(result, score)
        return CAPI.SUCCESS
    catch error
        state.failure === nothing && (state.failure = CapturedException(error, catch_backtrace()))
        return CAPI.ERROR_SOLVER
    end
end

# A raw process address must never be restored from a precompiled package image.
const _callback_pointer = Ref{Ptr{Cvoid}}(C_NULL)

function _initialize_callbacks!()
    _callback_pointer[] = @cfunction(_callback, Cint,
        (Ptr{Cint}, Csize_t, Ptr{Cdouble}, Ptr{Cvoid}))
    return nothing
end

function _add_callback(session::CAPI.Session, ids::Vector{Cint}, f)
    state = CallbackState(f, zeros(Int, length(ids)), nothing, 0, false)
    push!(session.callbacks, state) # Root userdata until native destruction.
    GC.@preserve session state begin
        status = ccall(CAPI._symbol(:ghost_add_callback_constraint), Cint,
            (Ptr{Cvoid}, Ptr{Cint}, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
            session, ids, length(ids), _callback_pointer[], pointer_from_objref(state))
        CAPI.check(status, session)
    end
    return state
end

function _add_objective_callback(session::CAPI.Session, ids::Vector{Cint}, f, maximize::Bool)
    state = CallbackState(f, zeros(Int, length(ids)), nothing, 0, true)
    push!(session.callbacks, state)
    GC.@preserve session state begin
        status = ccall(CAPI._symbol(:ghost_set_callback_objective), Cint,
            (Ptr{Cvoid}, Cuchar, Ptr{Cint}, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
            session, maximize, ids, length(ids), _callback_pointer[], pointer_from_objref(state))
        CAPI.check(status, session)
    end
    return state
end

function _callback_failure(session::CAPI.Session)
    for state in session.callbacks
        state.failure === nothing || throw(state.failure.ex)
    end
end
