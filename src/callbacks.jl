mutable struct CallbackState{F}
    f::F
    values::Vector{Int}
    failure::Any
    calls::Int
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
        score >= 0 || throw(DomainError(score, "error functions must return a nonnegative score"))
        unsafe_store!(result, score)
        return CAPI.SUCCESS
    catch error
        state.failure === nothing && (state.failure = CapturedException(error, catch_backtrace()))
        return CAPI.ERROR_SOLVER
    end
end

const _callback_pointer = @cfunction(_callback, Cint,
    (Ptr{Cint}, Csize_t, Ptr{Cdouble}, Ptr{Cvoid}))

function _add_callback(session::CAPI.Session, ids::Vector{Cint}, f)
    state = CallbackState(f, zeros(Int, length(ids)), nothing, 0)
    push!(session.callbacks, state) # Root userdata until native destruction.
    GC.@preserve session state begin
        status = ccall(CAPI._symbol(:ghost_add_callback_constraint), Cint,
            (Ptr{Cvoid}, Ptr{Cint}, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}),
            session, ids, length(ids), _callback_pointer, pointer_from_objref(state))
        CAPI.check(status, session)
    end
    return state
end

function _callback_failure(session::CAPI.Session)
    for state in session.callbacks
        state.failure === nothing || throw(state.failure.ex)
    end
end
