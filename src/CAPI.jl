module CAPI

using Libdl
import GHOST_jll

const SUCCESS = Cint(0)
const SAT_FOUND = Cint(1)
const FEASIBLE_FOUND = Cint(3)
const TIME_LIMIT = Cint(4)
const ERROR_SOLVER = Cint(-7)
const ABI_VERSION = UInt32(0x00010000)
const _lock = ReentrantLock()
const _handle = Ref{Ptr{Cvoid}}(C_NULL)
const _symbols = Dict{Symbol,Ptr{Cvoid}}()
library_path() = GHOST_jll.library_path()

function _symbol(name::Symbol)
    lock(_lock) do
        if _handle[] == C_NULL
            handle = Libdl.dlopen(library_path())
            version = Libdl.dlsym_e(handle, :ghost_c_api_version)
            if version == C_NULL || ccall(version, Cuint, ()) != ABI_VERSION
                Libdl.dlclose(handle)
                error("This GHOST library does not provide callback ABI 1.0; use the qualified development build.")
            end
            _handle[] = handle
        end
        return get!(_symbols, name) do
            Libdl.dlsym(_handle[], name)
        end
    end
end

mutable struct Session
    ptr::Ptr{Cvoid}
    callbacks::Vector{Any}
    destroy::Ptr{Cvoid}
end
Base.cconvert(::Type{Ptr{Cvoid}}, session::Session) = session
Base.unsafe_convert(::Type{Ptr{Cvoid}}, session::Session) = session.ptr
function Session(permutation::Bool)
    destroy = _symbol(:ghost_destroy_session)
    ptr = ccall(_symbol(:ghost_create_session), Ptr{Cvoid}, (Cuchar,), permutation)
    ptr == C_NULL && error("GHOST could not allocate a native session")
    session = Session(ptr, Any[], destroy)
    finalizer(close, session)
    return session
end
function Base.close(session::Session)
    if session.ptr != C_NULL
        ccall(session.destroy, Cvoid, (Ptr{Cvoid},), session)
        session.ptr = C_NULL
        empty!(session.callbacks)
    end
    return nothing
end

mutable struct Options
    ptr::Ptr{Cvoid}
    destroy::Ptr{Cvoid}
end
Base.cconvert(::Type{Ptr{Cvoid}}, options::Options) = options
Base.unsafe_convert(::Type{Ptr{Cvoid}}, options::Options) = options.ptr
function Options()
    destroy = _symbol(:ghost_destroy_options)
    ptr = ccall(_symbol(:ghost_create_options), Ptr{Cvoid}, ())
    ptr == C_NULL && error("GHOST could not allocate native options")
    options = Options(ptr, destroy)
    finalizer(close, options)
    return options
end
function Base.close(options::Options)
    if options.ptr != C_NULL
        ccall(options.destroy, Cvoid, (Ptr{Cvoid},), options)
        options.ptr = C_NULL
    end
    return nothing
end

function check(status::Integer, session::Session)
    status >= 0 && return status
    msg = ccall(_symbol(:ghost_get_last_error), Cstring, (Ptr{Cvoid},), session)
    error("GHOST C ABI failure ($status): $(msg == C_NULL ? "unknown error" : unsafe_string(msg))")
end

function add_variable(session, lower::Cint, upper::Cint, name::String)
    check(ccall(_symbol(:ghost_add_variable), Cint,
        (Ptr{Cvoid}, Cint, Cint, Cstring), session, lower, upper, name), session)
end
function set_start(session, id::Cint, value::Cint)
    check(ccall(_symbol(:ghost_set_variable_start), Cint,
        (Ptr{Cvoid}, Cint, Cint), session, id, value), session)
end
function add_linear(session, kind::Symbol, ids::Vector{Cint}, coeff::Vector{Float64}, rhs::Float64)
    check(ccall(_symbol(kind), Cint,
        (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cdouble}, Csize_t, Cdouble),
        session, ids, coeff, length(ids), rhs), session)
end
function add_alldifferent(session, ids::Vector{Cint})
    check(ccall(_symbol(:ghost_add_alldifferent_constraint), Cint,
        (Ptr{Cvoid}, Ptr{Cint}, Csize_t), session, ids, length(ids)), session)
end
function set_objective(session, maximize::Bool, ids::Vector{Cint}, coeff::Vector{Float64}, constant::Float64)
    check(ccall(_symbol(:ghost_set_linear_objective), Cint,
        (Ptr{Cvoid}, Cuchar, Ptr{Cint}, Ptr{Cdouble}, Csize_t, Cdouble),
        session, maximize, ids, coeff, length(ids), constant), session)
end
function set_option(options::Options, name::Symbol, value::Bool)
    status = ccall(_symbol(name), Cint, (Ptr{Cvoid}, Cuchar), options, value)
    status == SUCCESS || throw(ArgumentError("Invalid GHOST option $name: $value"))
end
function set_option(options::Options, name::Symbol, value::Integer)
    status = ccall(_symbol(name), Cint, (Ptr{Cvoid}, Cint), options, Cint(value))
    status == SUCCESS || throw(ArgumentError("Invalid GHOST option $name: $value"))
end
solve(session::Session, options::Options, microseconds::Float64) =
    ccall(_symbol(:ghost_solve), Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cdouble), session, options, microseconds)
function values(session::Session, count::Int)
    values = Vector{Cint}(undef, count)
    check(ccall(_symbol(:ghost_get_variable_values), Cint,
        (Ptr{Cvoid}, Ptr{Cint}, Csize_t), session, values, count), session)
    return values
end
function scalar_result(session::Session, name::Symbol)
    result = Ref{Cdouble}(NaN)
    check(ccall(_symbol(name), Cint, (Ptr{Cvoid}, Ref{Cdouble}), session, result), session)
    return result[]
end
function raw_status(session::Session)
    result = ccall(_symbol(:ghost_get_raw_status_string), Cstring, (Ptr{Cvoid},), session)
    return result == C_NULL ? "UNKNOWN" : unsafe_string(result)
end

end
