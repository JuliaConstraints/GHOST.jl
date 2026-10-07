"A scoped nonnegative error function, whose zero set defines the constraint."
struct MOIError{F} <: MOI.AbstractVectorSet
    f::F
    dimension::Int
    function MOIError(f, dimension::Integer)
        dimension > 0 || throw(ArgumentError("Error constraints require a nonempty scope"))
        new{typeof(f)}(f, dimension)
    end
end
Base.copy(set::MOIError) = MOIError(deepcopy(set.f), set.dimension)

"""
    GHOST.Error(f)

Use `@constraint(model, x in GHOST.Error(f))`. `f(values)` returns a finite,
nonnegative number and is zero exactly when the constraint is satisfied.
Mutable state is copied per native session. The input buffer is borrowed only
for an evaluation; do not retain it. Independent optimizers own separate buffers.
"""
struct Error{F} <: JuMP.AbstractVectorSet
    f::F
end
JuMP.moi_set(set::Error, dimension::Int) = MOIError(set.f, dimension)

# Factories such as learned ICNs allocate workspaces only when binding a session.
_bind_error(f, dimension::Int) = deepcopy(f)
