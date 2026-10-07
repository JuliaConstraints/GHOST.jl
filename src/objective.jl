"A scoped objective evaluated by GHOST's native callback ABI."
struct CallbackObjective{F} <: MOI.AbstractScalarFunction
    variables::Vector{MOI.VariableIndex}
    f::F
end
Base.copy(f::CallbackObjective) = CallbackObjective(copy(f.variables), deepcopy(f.f))
MOI.Utilities.map_indices(mapper::Function, f::CallbackObjective) =
    CallbackObjective(MOI.Utilities.map_indices(mapper, f.variables), deepcopy(f.f))
MOI.Utilities.map_indices(mapper::AbstractDict{T,T}, f::CallbackObjective) where
    {T<:Union{MOI.VariableIndex,MOI.ConstraintIndex}} =
    CallbackObjective(MOI.Utilities.map_indices(mapper, f.variables), deepcopy(f.f))
MOI.Utilities.eval_variables(evaluate::Function, f::CallbackObjective) =
    Float64(Base.invokelatest(f.f, Int[evaluate(v) for v in f.variables]))

"""
    set_callback_objective(model, sense, variables, f)

Set a finite scalar objective on the listed integer variables. `f` receives a
borrowed vector during search; each optimizer owns its callable and workspace.
Use `MOI.MIN_SENSE` or `MOI.MAX_SENSE`. Callback models use one native worker.
"""
function set_callback_objective(model::JuMP.Model, sense::MOI.OptimizationSense,
        variables::AbstractVector{<:JuMP.VariableRef}, f)
    sense in (MOI.MIN_SENSE, MOI.MAX_SENSE) || throw(ArgumentError("callback objectives require min or max"))
    isempty(variables) && throw(ArgumentError("callback objectives require a nonempty scope"))
    all(v -> JuMP.owner_model(v) === model, variables) || throw(ArgumentError("objective variables belong to another model"))
    function_value = CallbackObjective(JuMP.index.(variables), deepcopy(f))
    JuMP.set_objective_sense(model, sense)
    JuMP.set_objective_function(model, function_value)
    return nothing
end
